import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_attachment.dart';
import '../../models/direct_message.dart';
import '../../services/direct_message_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/chat/chat_attachment_view.dart';
import '../../widgets/chat/chat_background.dart';
import '../../widgets/chat/chat_composer.dart';
import '../../widgets/chat/reaction_picker.dart';
import '../../widgets/detail_header.dart';
import 'chat_media_screen.dart';
import 'chat_search_screen.dart';

/// WhatsApp's read-receipt blue — matches Group Chat's.
const _seenBlue = Color(0xFF34B7F1);

/// Faint yellow flash for a jumped-to message — matches WhatsApp's
/// highlight when you tap a search result.
const _highlightColor = Color(0xFFFFF3B0);

/// Private 1:1 chat with another member of the same trip, opened from
/// their tile in the Group Travel member list, or from the Personal
/// Message inbox. Same tick behavior as Group Chat: gray double-check
/// until the other person has read it, then blue — tap your own
/// message to see exactly when. Same settings menu too (background,
/// search), minus Group Chat's nickname (there's no group roster here
/// for one to mean anything to).
class DirectChatScreen extends StatefulWidget {
  const DirectChatScreen({
    super.key,
    required this.tripId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserColor,
  });

  final String tripId;
  final String otherUserId;
  final String otherUserName;
  final int otherUserColor;

  @override
  State<DirectChatScreen> createState() => _DirectChatScreenState();
}

/// A conversation's background is scoped by both trip and the other
/// participant, so each DM keeps its own choice, independent of the
/// trip's Group Chat background and every other DM in that trip.
String _backgroundConversationId(String tripId, String otherUserId) =>
    '$tripId/dm/$otherUserId';

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _dmService = DirectMessageService();
  final _scrollController = ScrollController();

  /// -1 until the first snapshot arrives, so the initial load always
  /// scrolls to the bottom; after that, only a message count *increase*
  /// triggers another jump.
  int _lastMessageCount = -1;

  ChatBackground _background = chatBackgrounds.first;

  /// Kept in sync with every messages-stream emission so "Search
  /// Messages" (opened from outside that stream, via the settings menu)
  /// has something current to search over.
  List<DirectMessage> _latestMessages = [];

  /// A GlobalKey per message, reused across rebuilds by id — lets
  /// [_jumpToMessage] find where a message actually landed in the list
  /// (via [Scrollable.ensureVisible]) once it's been scrolled near.
  final _messageKeys = <String, GlobalKey>{};
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, () => GlobalKey());

  // Cached once, not created inline in build() — `.stream()` returns a
  // new Supabase stream object on every call, so building these inline
  // would make each nested StreamBuilder below tear down and
  // resubscribe (briefly emitting null/empty data) on *every* rebuild
  // of this screen, not just when it first opens. For
  // _notifyNewReactions that resubscribe blip reset its "previous
  // reactions" baseline to empty, so the next real emission looked
  // like every existing reaction was brand new — showing the "reacted
  // to your message" toast again each time the chat reopened.
  late final _lastReadStream = _dmService.watchTheirLastRead(
    tripId: widget.tripId,
    otherUserId: widget.otherUserId,
  );
  late final _conversationStream = _dmService.watchConversation(
    tripId: widget.tripId,
    otherUserId: widget.otherUserId,
  );
  late final _reactionsStream = _dmService.watchReactions(widget.tripId);

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  /// The last reactions snapshot seen, so a new emission can be diffed
  /// against it to notice the other participant freshly reacting to one
  /// of *my* messages — the source for [_notifyNewReactions]'s in-chat
  /// toast. This only fires while the chat is actually open.
  Map<String, Map<String, String>> _previousReactions = {};
  bool _reactionsInitialized = false;

  @override
  void initState() {
    super.initState();
    final conversationId = _backgroundConversationId(
      widget.tripId,
      widget.otherUserId,
    );
    loadChatBackgroundKey(conversationId)
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
    return _dmService.sendMessage(
      tripId: widget.tripId,
      recipientId: widget.otherUserId,
      body: text,
    );
  }

  Future<void> _sendMedia(PickedChatMedia media) async {
    final url = await _dmService.uploadAttachment(
      tripId: widget.tripId,
      bytes: media.bytes,
      fileExt: media.fileExt,
      contentType: media.contentType,
    );
    await _dmService.sendMessage(
      tripId: widget.tripId,
      recipientId: widget.otherUserId,
      attachment: ChatAttachment(type: media.type, url: url),
    );
  }

  /// Toasts "{name} reacted {emoji} to your message" the moment the
  /// other participant reacts to a message the signed-in user sent, by
  /// diffing this reactions snapshot against the last one seen.
  void _notifyNewReactions(
    List<DirectMessage> rawMessages,
    Map<String, Map<String, String>> reactionsByMessage,
    String? myUid,
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
      if (message == null || message.senderId != myUid) continue;
      final oldReactions = _previousReactions[entry.key] ?? const {};
      final theirEmoji = entry.value[widget.otherUserId];
      if (theirEmoji == null) continue;
      if (oldReactions[widget.otherUserId] == theirEmoji) continue;
      toNotify.add(
        '${widget.otherUserName} reacted $theirEmoji to your message',
      );
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

  void _maybeScrollToBottom(int newCount) {
    final shouldScroll = newCount > _lastMessageCount;
    _lastMessageCount = newCount;
    if (!shouldScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
    // Covers both the initial load and a new message landing while
    // already open — either way, the viewer has now seen it.
    _dmService.markConversationRead(
      tripId: widget.tripId,
      otherUserId: widget.otherUserId,
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
    final conversationId = _backgroundConversationId(
      widget.tripId,
      widget.otherUserId,
    );
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
                          await saveChatBackgroundKey(conversationId, bg.key);
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

  Future<void> _openSearch() async {
    final messageId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ChatSearchScreen(
          subtitle: widget.otherUserName,
          messages: [
            for (final m in _latestMessages)
              SearchableChatMessage(
                id: m.id,
                senderLabel: m.senderId == widget.otherUserId
                    ? widget.otherUserName
                    : 'You',
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
          subtitle: widget.otherUserName,
          attachments: [
            for (final m in _latestMessages.reversed)
              if (m.attachment != null) m.attachment!,
          ],
        ),
      ),
    );
  }

  /// Scrolls to and briefly highlights [messageId] — see Group Chat's
  /// identical method for why the estimated-jump-then-refine approach.
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

  Future<void> _reactTo(DirectMessage message, String myUid) async {
    final picked = await showReactionPicker(
      context,
      selectedEmoji: message.reactions[myUid],
    );
    if (picked == null) return;
    if (message.reactions[myUid] == picked) {
      await _dmService.removeReaction(message.id);
    } else {
      await _dmService.setReaction(
        tripId: widget.tripId,
        messageId: message.id,
        emoji: picked,
      );
    }
  }

  /// Who reacted to this DM and with what — just the two participants,
  /// so a simple list rather than Group Chat's member lookup. The
  /// signed-in user's own row gets a "Remove" action.
  void _showReactionDetails(DirectMessage message, String? myUid) {
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
              for (final entry in message.reactions.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Text(entry.value, style: const TextStyle(fontSize: 20)),
                      const SizedBox(width: 10),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: entry.key == widget.otherUserId
                            ? Color(widget.otherUserColor)
                            : sheetContext.colors.muted,
                        child: Text(
                          (entry.key == widget.otherUserId
                                  ? widget.otherUserName
                                  : 'You')[0]
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
                          entry.key == myUid ? 'You' : widget.otherUserName,
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
                            _dmService.removeReaction(message.id);
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

  /// WhatsApp-style "message info" for a DM — just the one other
  /// participant, so it's a single row rather than Group Chat's list.
  void _showMessageInfo(DateTime? seenAt) {
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
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(widget.otherUserColor),
                    child: Text(
                      widget.otherUserName[0].toUpperCase(),
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
                      widget.otherUserName,
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
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
                  ),
                ],
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
            DetailHeader(
              title: widget.otherUserName,
              subtitle: 'Direct message',
              trailing: IconButton(
                onPressed: _showChatSettings,
                icon: Icon(Icons.more_vert_rounded, color: context.colors.ink),
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
                child: StreamBuilder<DateTime?>(
                  stream: _lastReadStream,
                  builder: (context, lastReadSnap) {
                    final theirLastRead = lastReadSnap.data;
                    return StreamBuilder<List<DirectMessage>>(
                      stream: _conversationStream,
                      builder: (context, snapshot) {
                        final rawMessages =
                            snapshot.data ?? const <DirectMessage>[];
                        if (rawMessages.isEmpty) {
                          return Center(
                            child: Text(
                              'No messages yet — say hi!',
                              style: TextStyle(color: context.colors.muted),
                            ),
                          );
                        }
                        _maybeScrollToBottom(rawMessages.length);
                        return StreamBuilder<Map<String, Map<String, String>>>(
                          stream: _reactionsStream,
                          builder: (context, reactionsSnapshot) {
                            final reactionsByMessage =
                                reactionsSnapshot.data ?? const {};
                            _notifyNewReactions(
                              rawMessages,
                              reactionsByMessage,
                              myUid,
                            );
                            final messages = [
                              for (final m in rawMessages)
                                m.withReactions(
                                  reactionsByMessage[m.id] ?? const {},
                                ),
                            ];
                            _latestMessages = messages;
                            return ListView.builder(
                              controller: _scrollController,
                              // Wider than the default 250 so
                              // _jumpToMessage's estimated jump lands
                              // somewhere ensureVisible can already
                              // find built.
                              cacheExtent: 3000,
                              padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final m = messages[index];
                                final mine = m.senderId == myUid;
                                final seenAt =
                                    mine &&
                                        theirLastRead != null &&
                                        !theirLastRead.isBefore(m.createdAt)
                                    ? theirLastRead
                                    : null;
                                return AnimatedContainer(
                                  key: _keyFor(m.id),
                                  duration: const Duration(milliseconds: 400),
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
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor: Color(
                                              widget.otherUserColor,
                                            ),
                                            child: Text(
                                              widget.otherUserName[0]
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
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
                                              GestureDetector(
                                                onTap: myUid == null
                                                    ? null
                                                    : mine
                                                    ? () => _showMessageInfo(
                                                        seenAt,
                                                      )
                                                    // Tapping their message
                                                    // reacts directly —
                                                    // long-press also still
                                                    // works, but holding a
                                                    // mouse button on desktop
                                                    // isn't discoverable the
                                                    // way it is on a
                                                    // touchscreen.
                                                    : () => _reactTo(m, myUid),
                                                onLongPress: myUid == null
                                                    ? null
                                                    : () => _reactTo(m, myUid),
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 14,
                                                    vertical: 10,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: mine
                                                        ? context.colors.ink
                                                        : context.colors.card,
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
                                                                ? Colors.white
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
                                                          myUid,
                                                        ),
                                                  ),
                                                ),
                                              GestureDetector(
                                                // A photo bubble has its own
                                                // tap target (open fullscreen
                                                // preview) that wins the
                                                // gesture arena over the
                                                // bubble's tap, so it can
                                                // never reach
                                                // _showMessageInfo. This
                                                // ticks row sits below the
                                                // image and is always free,
                                                // so it's the reliable way to
                                                // open "Seen" for photo
                                                // messages too.
                                                onTap: mine && myUid != null
                                                    ? () => _showMessageInfo(
                                                        seenAt,
                                                      )
                                                    : null,
                                                child: Padding(
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
                                                          color: seenAt != null
                                                              ? _seenBlue
                                                              : context
                                                                    .colors
                                                                    .muted,
                                                        ),
                                                      ],
                                                    ],
                                                  ),
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
