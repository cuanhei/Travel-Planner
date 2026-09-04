import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_attachment.dart';
import '../../models/group_member.dart';
import '../../models/group_message.dart';
import '../../services/chat_service.dart';
import '../../services/group_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/chat/chat_attachment_view.dart';
import '../../widgets/chat/chat_background.dart';
import '../../widgets/chat/chat_composer.dart';
import '../../widgets/chat/reaction_picker.dart';
import '../../widgets/detail_header.dart';
import 'chat_media_screen.dart';
import 'chat_search_screen.dart';
import 'direct_chat_screen.dart';

/// Faint yellow flash for a jumped-to message — matches WhatsApp's
/// highlight when you tap a search result.
const _highlightColor = Color(0xFFFFF3B0);

/// WhatsApp's read-receipt blue.
const _seenBlue = Color(0xFF34B7F1);

/// Live group chat for a trip, backed by Supabase Realtime. Every
/// message shows when it was sent; a message you sent also shows a
/// double-check tick — gray until *every other member* has read it,
/// then blue. Tapping your own message shows exactly who's seen it and
/// when, like WhatsApp's message info screen.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _chatService = ChatService();
  final _groupService = GroupService();
  final _scrollController = ScrollController();
  late final Future<String> _tripNameFuture = TripService().getTripName(
    widget.tripId,
  );

  /// Message ids already reported as read this screen session — avoids
  /// re-sending the same read receipt on every rebuild of the messages
  /// stream (harmless since the upsert ignores duplicates, but pointless
  /// network chatter otherwise).
  final _markedRead = <String>{};

  /// -1 until the first snapshot arrives, so the initial load always
  /// scrolls to the bottom; after that, only a message count *increase*
  /// (a new message landing) triggers another jump.
  int _lastMessageCount = -1;

  ChatBackground _background = chatBackgrounds.first;

  /// Kept in sync with every messages-stream emission so "Search
  /// Messages" (opened from outside that stream, via the settings menu)
  /// has something current to search over.
  List<GroupMessage> _latestMessages = [];

  /// A GlobalKey per message, reused across rebuilds by id — lets
  /// [_jumpToMessage] find where a message actually landed in the list
  /// (via [Scrollable.ensureVisible]) once it's been scrolled near.
  final _messageKeys = <String, GlobalKey>{};
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, () => GlobalKey());

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  /// The last reactions snapshot seen, so a new emission can be diffed
  /// against it to notice a fresh reaction landing on one of *my*
  /// messages — the source for [_notifyNewReactions]'s in-chat toast.
  /// This only fires while the chat is actually open, not as a
  /// persistent notification the recipient sees later.
  Map<String, Map<String, String>> _previousReactions = {};
  bool _reactionsInitialized = false;

  @override
  void initState() {
    super.initState();
    loadChatBackgroundKey(widget.tripId)
        .then((key) {
          if (mounted) setState(() => _background = chatBackgroundByKey(key));
        })
        .catchError((_) {
          // Fall through with the default background.
        });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _highlightTimer?.cancel();
    super.dispose();
  }

  Future<void> _send(String text) {
    return _chatService.sendMessage(tripId: widget.tripId, body: text);
  }

  Future<void> _sendMedia(PickedChatMedia media) async {
    final url = await _chatService.uploadAttachment(
      tripId: widget.tripId,
      bytes: media.bytes,
      fileExt: media.fileExt,
      contentType: media.contentType,
    );
    await _chatService.sendMessage(
      tripId: widget.tripId,
      attachment: ChatAttachment(type: media.type, url: url),
    );
  }

  void _markUnreadAsRead(List<GroupMessage> messages, String myUid) {
    final toMark = <String>[];
    for (final m in messages) {
      if (m.userId == myUid) continue;
      if (_markedRead.add(m.id)) toMark.add(m.id);
    }
    if (toMark.isEmpty) return;
    _chatService.markMessagesRead(tripId: widget.tripId, messageIds: toMark);
  }

  /// Toasts "{name} reacted {emoji} to your message" the moment
  /// someone else reacts to a message the signed-in user sent, by
  /// diffing this reactions snapshot against the last one seen. Only
  /// fires while this screen is open and subscribed — there's no
  /// persistent notification for it beyond that.
  void _notifyNewReactions(
    List<GroupMessage> rawMessages,
    Map<String, Map<String, String>> reactionsByMessage,
    String? myUid,
    List<GroupMember> members,
  ) {
    if (myUid == null) {
      _previousReactions = reactionsByMessage;
      return;
    }
    if (!_reactionsInitialized) {
      _reactionsInitialized = true;
      _previousReactions = reactionsByMessage;
      return;
    }
    final messageById = {for (final m in rawMessages) m.id: m};
    final toNotify = <String>[];
    for (final entry in reactionsByMessage.entries) {
      final message = messageById[entry.key];
      if (message == null || message.userId != myUid) continue;
      final oldReactions = _previousReactions[entry.key] ?? const {};
      for (final reactorEntry in entry.value.entries) {
        if (reactorEntry.key == myUid) continue;
        if (oldReactions[reactorEntry.key] == reactorEntry.value) continue;
        var reactorName = 'Someone';
        for (final member in members) {
          if (member.userId == reactorEntry.key) {
            reactorName = member.label;
            break;
          }
        }
        toNotify.add(
          '$reactorName reacted ${reactorEntry.value} to your message',
        );
      }
    }
    _previousReactions = reactionsByMessage;
    if (toNotify.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final message in toNotify) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
        );
      }
    });
  }

  /// Opening the chat (or a new message landing) should show the
  /// latest message, not leave the view sitting at the oldest one.
  void _maybeScrollToBottom(int newCount) {
    final shouldScroll = newCount > _lastMessageCount;
    _lastMessageCount = newCount;
    if (!shouldScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Future<void> _openSearch() async {
    final messageId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ChatSearchScreen(
          subtitle: 'Group Chat',
          messages: [
            for (final m in _latestMessages)
              SearchableChatMessage(
                id: m.id,
                senderLabel: m.senderName,
                body: m.body,
                createdAt: m.createdAt,
                hasAttachment: m.attachment != null,
              ),
          ],
        ),
      ),
    );
    if (messageId != null) _jumpToMessage(messageId);
  }

  void _openMedia() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatMediaScreen(
          subtitle: 'Group Chat',
          attachments: [
            for (final m in _latestMessages.reversed)
              if (m.attachment != null) m.attachment!,
          ],
        ),
      ),
    );
  }

  /// Scrolls to and briefly highlights [messageId] — e.g. after tapping
  /// a search result. `ensureVisible` only works on an already-built
  /// widget, which for a message far from the current scroll position
  /// won't exist yet; jumping to an estimated offset first gets
  /// `ListView.builder` to build around there, then `ensureVisible`
  /// (once the frame settles) corrects to the exact position.
  Future<void> _jumpToMessage(String messageId) async {
    final index = _latestMessages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    setState(() => _highlightedMessageId = messageId);

    if (_scrollController.hasClients) {
      const estimatedItemExtent = 70.0;
      final estimatedOffset = (index * estimatedItemExtent).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(estimatedOffset);
    }

    await Future.delayed(const Duration(milliseconds: 80));
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        alignment: 0.3,
      );
    }

    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });
  }

  Future<void> _reactTo(GroupMessage message, String myUid) async {
    final picked = await showReactionPicker(
      context,
      selectedEmoji: message.reactions[myUid],
    );
    if (picked == null) return;
    if (message.reactions[myUid] == picked) {
      await _chatService.removeReaction(message.id);
    } else {
      await _chatService.setReaction(
        tripId: widget.tripId,
        messageId: message.id,
        emoji: picked,
      );
    }
  }

  Future<void> _removeMyReaction(String messageId) =>
      _chatService.removeReaction(messageId);

  /// Who reacted to this message and with what — tapping a reaction
  /// pill opens this, like WhatsApp's reaction details. The
  /// signed-in user's own row gets a "Remove" action instead of just a
  /// timestamp-free label, so removing a reaction doesn't require
  /// reopening the emoji picker and re-tapping the same emoji.
  void _showReactionDetails(GroupMessage message, List<GroupMember> members) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;
    final memberById = {for (final m in members) m.userId: m};
    final reactors = message.reactions.entries.toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reactions',
                style: TextStyle(
                  color: sheetContext.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 16),
              for (final entry in reactors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Text(entry.value, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(
                          memberById[entry.key]?.avatarColor ?? 0xFF9E9E9E,
                        ),
                        child: Text(
                          (memberById[entry.key]?.label ?? '?')[0]
                              .toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.key == myUid
                              ? 'You'
                              : (memberById[entry.key]?.label ?? 'Someone'),
                          style: TextStyle(
                            color: sheetContext.colors.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (entry.key == myUid)
                        TextButton(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            _removeMyReaction(message.id);
                          },
                          child: const Text(
                            'Remove',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showChatSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                Icons.wallpaper_rounded,
                color: sheetContext.colors.ink,
              ),
              title: Text(
                'Change Background',
                style: TextStyle(color: sheetContext.colors.ink),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showBackgroundPicker();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.badge_outlined,
                color: sheetContext.colors.ink,
              ),
              title: Text(
                'Change Nickname',
                style: TextStyle(color: sheetContext.colors.ink),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showNicknameDialog();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.search_rounded,
                color: sheetContext.colors.ink,
              ),
              title: Text(
                'Search Messages',
                style: TextStyle(color: sheetContext.colors.ink),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openSearch();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_outlined,
                color: sheetContext.colors.ink,
              ),
              title: Text(
                'Media',
                style: TextStyle(color: sheetContext.colors.ink),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openMedia();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBackgroundPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Chat Background',
                style: TextStyle(
                  color: sheetContext.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Only visible to you on this device',
                style: TextStyle(
                  color: sheetContext.colors.muted,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final bg in chatBackgrounds)
                    GestureDetector(
                      onTap: () async {
                        setState(() => _background = bg);
                        try {
                          await saveChatBackgroundKey(widget.tripId, bg.key);
                        } catch (e) {
                          if (mounted) _showError('Could not save: $e');
                        }
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: bg.colors.isEmpty
                                  ? null
                                  : LinearGradient(
                                      colors: bg.colors,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                              color: bg.colors.isEmpty
                                  ? sheetContext.colors.surface
                                  : null,
                              border: Border.all(
                                color: bg.key == _background.key
                                    ? AppColors.accent
                                    : sheetContext.colors.muted.withValues(
                                        alpha: 0.3,
                                      ),
                                width: bg.key == _background.key ? 2.5 : 1,
                              ),
                            ),
                            child: bg.key == _background.key
                                ? Icon(
                                    Icons.check_rounded,
                                    color: bg.colors.isEmpty
                                        ? sheetContext.colors.ink
                                        : Colors.black54,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            bg.label,
                            style: TextStyle(
                              color: sheetContext.colors.muted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNicknameDialog() async {
    final current = await _groupService.getMyNickname(widget.tripId);
    if (!mounted) return;
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Change Nickname',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: dialogContext.colors.ink),
          decoration: InputDecoration(
            hintText: 'How you appear in this Group Chat',
            filled: true,
            fillColor: dialogContext.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await _groupService.setMyNickname(tripId: widget.tripId, nickname: result);
  }

  void _showMemberProfile(GroupMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: Color(message.senderColor),
                child: Text(
                  message.senderName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                message.senderName,
                style: TextStyle(
                  color: sheetContext.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DirectChatScreen(
                          tripId: widget.tripId,
                          otherUserId: message.userId,
                          otherUserName: message.senderName,
                          otherUserColor: message.senderColor,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const Text('Message'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// WhatsApp-style "message info": who's seen this message and when,
  /// listed for every other trip member (not just the ones who have).
  void _showMessageInfo(GroupMessage message, List<GroupMember> members) {
    final others = members.where((m) => m.userId != message.userId).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seen by',
                style: TextStyle(
                  color: sheetContext.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 16),
              if (others.isEmpty)
                Text(
                  'No other members in this trip yet',
                  style: TextStyle(color: sheetContext.colors.muted),
                )
              else
                for (final member in others)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(member.avatarColor),
                          child: Text(
                            member.label[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            member.label,
                            style: TextStyle(
                              color: sheetContext.colors.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Builder(
                          builder: (_) {
                            final seenAt = message.readBy[member.userId];
                            return Text(
                              seenAt != null
                                  ? formatChatDateTime(seenAt)
                                  : 'Not seen yet',
                              style: TextStyle(
                                color: seenAt != null
                                    ? _seenBlue
                                    : sheetContext.colors.muted,
                                fontWeight: seenAt != null
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 11.5,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            FutureBuilder<String>(
              future: _tripNameFuture,
              builder: (context, nameSnap) => DetailHeader(
                title: 'Group Chat',
                subtitle: nameSnap.data ?? '',
                trailing: IconButton(
                  onPressed: _showChatSettings,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: context.colors.ink,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  gradient: _background.colors.isEmpty
                      ? null
                      : LinearGradient(
                          colors: _background.colors,
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                ),
                child: StreamBuilder<List<GroupMember>>(
                  stream: _groupService.watchMembers(widget.tripId),
                  builder: (context, memberSnap) {
                    final members = memberSnap.data ?? const <GroupMember>[];
                    return StreamBuilder<List<GroupMessage>>(
                      stream: _chatService.watchMessages(widget.tripId),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Could not load messages:\n${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: context.colors.muted),
                              ),
                            ),
                          );
                        }
                        final rawMessages =
                            snapshot.data ?? const <GroupMessage>[];
                        if (rawMessages.isEmpty) {
                          return Center(
                            child: Text(
                              'No messages yet — say hi!',
                              style: TextStyle(color: context.colors.muted),
                            ),
                          );
                        }
                        if (myUid != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _markUnreadAsRead(rawMessages, myUid);
                          });
                        }
                        _maybeScrollToBottom(rawMessages.length);
                        return StreamBuilder<
                          Map<String, Map<String, DateTime>>
                        >(
                          stream: _chatService.watchReadReceipts(widget.tripId),
                          builder: (context, readsSnapshot) {
                            final reads = readsSnapshot.data ?? const {};
                            return StreamBuilder<
                              Map<String, Map<String, String>>
                            >(
                              stream: _chatService.watchReactions(
                                widget.tripId,
                              ),
                              builder: (context, reactionsSnapshot) {
                                final reactionsByMessage =
                                    reactionsSnapshot.data ?? const {};
                                _notifyNewReactions(
                                  rawMessages,
                                  reactionsByMessage,
                                  myUid,
                                  members,
                                );
                                final messages = [
                                  for (final m in rawMessages)
                                    m
                                        .withReadBy(reads[m.id] ?? const {})
                                        .withReactions(
                                          reactionsByMessage[m.id] ?? const {},
                                        ),
                                ];
                                _latestMessages = messages;
                                return ListView.builder(
                                  controller: _scrollController,
                                  // Wider than the default 250 so
                                  // _jumpToMessage's estimated jump
                                  // lands somewhere ensureVisible can
                                  // already find built, even when the
                                  // 70px/message guess is off.
                                  cacheExtent: 3000,
                                  padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final m = messages[index];
                                    final mine = m.userId == myUid;
                                    final otherMemberIds = members
                                        .map((mem) => mem.userId)
                                        .where((id) => id != m.userId);
                                    final seenByAll = m.seenByAll(
                                      otherMemberIds,
                                    );
                                    return AnimatedContainer(
                                      key: _keyFor(m.id),
                                      duration: const Duration(
                                        milliseconds: 400,
                                      ),
                                      color: _highlightedMessageId == m.id
                                          ? _highlightColor
                                          : Colors.transparent,
                                      child: Padding(
                                        padding: EdgeInsets.only(bottom: 12),
                                        child: Row(
                                          mainAxisAlignment: mine
                                              ? MainAxisAlignment.end
                                              : MainAxisAlignment.start,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (!mine) ...[
                                              GestureDetector(
                                                onTap: () =>
                                                    _showMemberProfile(m),
                                                child: CircleAvatar(
                                                  radius: 14,
                                                  backgroundColor: Color(
                                                    m.senderColor,
                                                  ),
                                                  child: Text(
                                                    m.senderName[0]
                                                        .toUpperCase(),
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                            ],
                                            Flexible(
                                              child: Column(
                                                crossAxisAlignment: mine
                                                    ? CrossAxisAlignment.end
                                                    : CrossAxisAlignment.start,
                                                children: [
                                                  if (!mine)
                                                    GestureDetector(
                                                      onTap: () =>
                                                          _showMemberProfile(m),
                                                      child: Padding(
                                                        padding:
                                                            EdgeInsets.only(
                                                              bottom: 3,
                                                              left: 4,
                                                            ),
                                                        child: Text(
                                                          m.senderName,
                                                          style: TextStyle(
                                                            color: context
                                                                .colors
                                                                .muted,
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  GestureDetector(
                                                    onTap: myUid == null
                                                        ? null
                                                        : mine
                                                        ? () =>
                                                              _showMessageInfo(
                                                                m,
                                                                members,
                                                              )
                                                        // Tapping someone
                                                        // else's message
                                                        // reacts directly —
                                                        // long-press also
                                                        // still works, but
                                                        // holding a mouse
                                                        // button on desktop
                                                        // isn't discoverable
                                                        // the way it is on
                                                        // a touchscreen.
                                                        : () => _reactTo(
                                                            m,
                                                            myUid,
                                                          ),
                                                    onLongPress: myUid == null
                                                        ? null
                                                        : () => _reactTo(
                                                            m,
                                                            myUid,
                                                          ),
                                                    child: Container(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 14,
                                                            vertical: 10,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: mine
                                                            ? context.colors.ink
                                                            : context
                                                                  .colors
                                                                  .card,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              16,
                                                            ),
                                                      ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (m.attachment !=
                                                              null) ...[
                                                            ChatAttachmentView(
                                                              attachment:
                                                                  m.attachment!,
                                                            ),
                                                            if (m.body != null)
                                                              const SizedBox(
                                                                height: 6,
                                                              ),
                                                          ],
                                                          if (m.body != null)
                                                            Text(
                                                              m.body!,
                                                              style: TextStyle(
                                                                color: mine
                                                                    ? Colors
                                                                          .white
                                                                    : context
                                                                          .colors
                                                                          .ink,
                                                                fontSize: 13,
                                                                height: 1.35,
                                                              ),
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  if (m.reactions.isNotEmpty)
                                                    Padding(
                                                      padding: EdgeInsets.only(
                                                        top: 4,
                                                        left: mine ? 0 : 4,
                                                        right: mine ? 4 : 0,
                                                      ),
                                                      child: ReactionsBar(
                                                        reactionsByUser:
                                                            m.reactions,
                                                        onTap: () =>
                                                            _showReactionDetails(
                                                              m,
                                                              members,
                                                            ),
                                                      ),
                                                    ),
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 4,
                                                      left: mine ? 0 : 4,
                                                      right: mine ? 4 : 0,
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Text(
                                                          formatChatDateTime(
                                                            m.createdAt,
                                                          ),
                                                          style: TextStyle(
                                                            color: context
                                                                .colors
                                                                .muted,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                        if (mine) ...[
                                                          SizedBox(width: 4),
                                                          Icon(
                                                            Icons
                                                                .done_all_rounded,
                                                            size: 14,
                                                            color: seenByAll
                                                                ? _seenBlue
                                                                : context
                                                                      .colors
                                                                      .muted,
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ChatComposer(onSendText: _send, onSendMedia: _sendMedia),
            ),
          ],
        ),
      ),
    );
  }
}
