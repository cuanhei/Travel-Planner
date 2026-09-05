import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_attachment.dart';
import '../../models/group_activity_event.dart';
import '../../models/group_member.dart';
import '../../models/group_message.dart';
import '../../models/reaction_event.dart';
import '../../services/chat_service.dart';
import '../../services/group_service.dart';
import '../../services/reaction_seen_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/chat/chat_attachment_view.dart';
import '../../widgets/chat/chat_background.dart';
import '../../widgets/chat/chat_composer.dart';
import '../../widgets/chat/jump_to_latest_button.dart';
import '../../widgets/chat/reaction_picker.dart';
import '../../widgets/detail_header.dart';
import 'chat_media_screen.dart';
import 'chat_search_screen.dart';
import 'direct_chat_screen.dart';
import 'group_activity_log_screen.dart';

/// Faint yellow flash for a jumped-to message — matches WhatsApp's
/// highlight when you tap a search result.
const _highlightColor = Color(0xFFFFF3B0);

/// WhatsApp's read-receipt blue.
const _seenBlue = Color(0xFF34B7F1);

/// One row in the chat feed — either a real message or a "so-and-so
/// joined/left" system event — merged and sorted by time so the two
/// render interleaved, WhatsApp-style, in a single scrolling list.
class _ChatFeedItem {
  const _ChatFeedItem.message(GroupMessage this.message) : activity = null;
  const _ChatFeedItem.activity(GroupActivityEvent this.activity)
    : message = null;

  final GroupMessage? message;
  final GroupActivityEvent? activity;

  DateTime get createdAt => (message?.createdAt ?? activity?.createdAt)!;
}

/// Live group chat for a trip, backed by Supabase Realtime. Every
/// message shows when it was sent; a message you sent also shows a
/// double-check tick — gray until *every other member* has read it,
/// then blue. Tapping your own message shows exactly who's seen it and
/// when, like WhatsApp's message info screen. Long-press any message
/// for reply/edit/delete/pin.
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

  // Cached once, not created inline in build() — `.stream()` returns a
  // new Supabase stream object on every call, so building these inline
  // would make each nested StreamBuilder below tear down and
  // resubscribe (briefly emitting null/empty data) on *every* rebuild
  // of this screen, not just when it first opens.
  late final _membersStream = _groupService.watchMembers(widget.tripId);
  late final _messagesStream = _chatService.watchMessages(widget.tripId);
  late final _readsStream = _chatService.watchReadReceipts(widget.tripId);
  late final _reactionsStream = _chatService.watchReactions(widget.tripId);
  late final _reactionEventsStream = _chatService.watchReactionEvents(
    widget.tripId,
  );
  late final _activityStream = _groupService.watchActivityLog(widget.tripId);

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
  List<GroupMember> _latestMembers = [];

  /// A GlobalKey per message, reused across rebuilds by id — lets
  /// [_jumpToMessage] find where a message actually landed in the list
  /// (via [Scrollable.ensureVisible]) once it's been scrolled near.
  final _messageKeys = <String, GlobalKey>{};
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  /// The message currently being replied to, shown as a quote banner in
  /// the composer — cleared once the reply is sent or cancelled.
  GroupMessage? _replyTarget;

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, () => GlobalKey());

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  /// Cutoff up to which the "so-and-so reacted to your message" toast
  /// has already run — persisted server-side (chat_reaction_seen_state)
  /// so it survives leaving and reopening the chat, or switching
  /// devices, instead of resetting every time this screen is rebuilt.
  /// `null` until [_initReactionsSeenState] has loaded it (or bootstrapped
  /// it for a conversation that's never used this feature before) —
  /// [_notifyNewReactions] stays a no-op until [_reactionsSeenAtReady].
  DateTime? _reactionsSeenAt;
  bool _reactionsSeenAtReady = false;

  /// Cutoff up to which the "so-and-so mentioned you" toast has already
  /// run — same persisted-cutoff mechanism as [_reactionsSeenAt] (reuses
  /// chat_reaction_seen_state via a `mentions:` key, since it's just a
  /// generic per-user, per-key "seen up to" cursor), so a mention that
  /// lands while this chat isn't open still gets toasted once the next
  /// time it's opened, instead of only ever firing live.
  DateTime? _mentionsSeenAt;
  bool _mentionsSeenAtReady = false;
  String get _mentionsSeenKey => 'mentions:${widget.tripId}';

  /// WhatsApp-style "jump to latest" — shown once the user has scrolled
  /// away from the bottom, so a new message doesn't yank them back down
  /// mid-read (see [_maybeScrollToBottom]).
  bool _showJumpToLatest = false;

  /// Other members currently typing — each id is removed a few seconds
  /// after its last broadcast (see [_onTypingEvent]), since Realtime
  /// Broadcast has no "stopped typing" signal of its own.
  final Set<String> _typingUserIds = {};
  final Map<String, Timer> _typingTimers = {};
  StreamSubscription<String>? _typingSub;

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
    _initReactionsSeenState();
    _initMentionsSeenState();
    _scrollController.addListener(_onScroll);
    _typingSub = _chatService.watchTyping(widget.tripId).listen(_onTyping);
  }

  Future<void> _initReactionsSeenState() async {
    DateTime? seenAt;
    try {
      seenAt = await loadReactionsSeenAt(widget.tripId);
    } catch (_) {
      // Fall through — treat as "never seen", same as a brand new
      // conversation.
    }
    // First time this feature has run for this conversation: bootstrap
    // to the epoch (not now) so any reaction that already landed on one
    // of my messages — including while I hadn't opened this chat yet —
    // still gets notified once, instead of being silently treated as
    // already-seen.
    seenAt ??= DateTime.fromMillisecondsSinceEpoch(0);
    if (!mounted) return;
    setState(() {
      _reactionsSeenAt = seenAt;
      _reactionsSeenAtReady = true;
    });
  }

  Future<void> _initMentionsSeenState() async {
    DateTime? seenAt;
    try {
      seenAt = await loadReactionsSeenAt(_mentionsSeenKey);
    } catch (_) {
      // Fall through — treat as "never seen", same as a brand new
      // conversation.
    }
    // Same epoch bootstrap as reactions: a mention that already landed
    // before this feature's first-ever run still gets toasted once,
    // rather than silently treated as already-seen.
    seenAt ??= DateTime.fromMillisecondsSinceEpoch(0);
    if (!mounted) return;
    setState(() {
      _mentionsSeenAt = seenAt;
      _mentionsSeenAtReady = true;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final shouldShow = position.maxScrollExtent - position.pixels > 300;
    if (shouldShow != _showJumpToLatest) {
      setState(() => _showJumpToLatest = shouldShow);
    }
  }

  void _scrollToLatest() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _onTyping(String userId) {
    _typingTimers[userId]?.cancel();
    _typingTimers[userId] = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _typingUserIds.remove(userId));
    });
    if (_typingUserIds.add(userId) && mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _typingSub?.cancel();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  Future<void> _send(
    String text, {
    String? replyToId,
    List<String>? mentionedUserIds,
  }) {
    return _chatService.sendMessage(
      tripId: widget.tripId,
      body: text,
      replyToId: replyToId,
      mentionedUserIds: mentionedUserIds,
    );
  }

  Future<void> _sendMedia(
    PickedChatMedia media, {
    String? replyToId,
    String? caption,
  }) async {
    final url = await _chatService.uploadAttachment(
      tripId: widget.tripId,
      bytes: media.bytes,
      fileExt: media.fileExt,
      contentType: media.contentType,
    );
    await _chatService.sendMessage(
      tripId: widget.tripId,
      attachment: ChatAttachment(type: media.type, url: url),
      replyToId: replyToId,
      body: caption,
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
  /// someone else reacts to a message the signed-in user sent, then
  /// jumps to and highlights that message — like tapping a
  /// notification. Each reaction only ever triggers this once:
  /// [_reactionsSeenAt] is the persisted (chat_reaction_seen_state)
  /// cutoff, advanced past the newest notified reaction's timestamp
  /// every time this runs, so re-opening the chat later (even on
  /// another device) never replays it.
  void _notifyNewReactions(
    List<GroupMessage> rawMessages,
    List<ReactionEvent> events,
    String? myUid,
    List<GroupMember> members,
  ) {
    if (myUid == null || !_reactionsSeenAtReady) return;
    final cutoff = _reactionsSeenAt;
    final messageById = {for (final m in rawMessages) m.id: m};
    final newEvents = <ReactionEvent>[];
    for (final e in events) {
      if (e.userId == myUid) continue;
      if (cutoff != null && !e.createdAt.isAfter(cutoff)) continue;
      final message = messageById[e.messageId];
      if (message == null || message.userId != myUid) continue;
      newEvents.add(e);
    }
    if (newEvents.isEmpty) return;
    newEvents.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final newCutoff = newEvents.last.createdAt;
    // Advance the in-memory cutoff synchronously (not via setState) so a
    // rebuild triggered before the save below completes doesn't re-toast
    // the same events.
    _reactionsSeenAt = newCutoff;
    unawaited(saveReactionsSeenAt(widget.tripId, newCutoff));

    final toNotify = <String>[];
    for (final e in newEvents) {
      var reactorName = 'Someone';
      for (final member in members) {
        if (member.userId == e.userId) {
          reactorName = member.label;
          break;
        }
      }
      toNotify.add('$reactorName reacted ${e.emoji} to your message');
    }
    final jumpToMessageId = newEvents.last.messageId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      for (final message in toNotify) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
        );
      }
      await _jumpToMessage(jumpToMessageId);
    });
  }

  /// Toasts "{name} mentioned you" the moment a message mentioning the
  /// signed-in user lands *while this screen is open* — live-only,
  /// unlike the reaction toast: [_knownMessageIds] resets every time
  /// this screen is reopened, so a mention that happened while away
  /// doesn't replay (there's no persisted cutoff for it).
  void _notifyMentions(List<GroupMessage> rawMessages, String? myUid) {
    if (myUid == null || !_mentionsSeenAtReady) return;
    final cutoff = _mentionsSeenAt;
    final newMentions = <GroupMessage>[];
    for (final m in rawMessages) {
      if (m.userId == myUid) continue;
      if (m.isDeleted) continue;
      if (!m.mentionedUserIds.contains(myUid)) continue;
      if (cutoff != null && !m.createdAt.isAfter(cutoff)) continue;
      newMentions.add(m);
    }
    if (newMentions.isEmpty) return;
    newMentions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final newCutoff = newMentions.last.createdAt;
    // Advance the in-memory cutoff synchronously (not via setState) so a
    // rebuild triggered before the save below completes doesn't re-toast
    // the same messages.
    _mentionsSeenAt = newCutoff;
    unawaited(saveReactionsSeenAt(_mentionsSeenKey, newCutoff));

    final message = newMentions.last;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${message.senderName} mentioned you'),
        ),
      );
      await _jumpToMessage(message.id);
    });
  }

  /// Opening the chat (or a new message landing) should show the
  /// latest message — but only when already at the bottom. A message
  /// arriving while the user has scrolled up to read older ones leaves
  /// their scroll position alone (the [_showJumpToLatest] button is how
  /// they get back down when they're ready), instead of yanking them
  /// away from what they were reading.
  void _maybeScrollToBottom(int newCount) {
    final shouldScroll = newCount > _lastMessageCount && !_showJumpToLatest;
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

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GroupActivityLogScreen(tripId: widget.tripId),
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

  void _startReply(GroupMessage message) {
    setState(() => _replyTarget = message);
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  Future<void> _editMessage(GroupMessage message) async {
    final controller = TextEditingController(text: message.body ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Edit Message',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          style: TextStyle(color: dialogContext.colors.ink),
          decoration: InputDecoration(
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
    if (result.isEmpty && message.attachment == null) {
      _showError('A message needs some text or a photo/video.');
      return;
    }
    try {
      await _chatService.editMessage(messageId: message.id, body: result);
    } catch (e) {
      _showError('Could not save: $e');
    }
  }

  Future<void> _confirmDelete(GroupMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete for everyone?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          "This can't be undone.",
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _chatService.deleteMessage(message.id);
    } catch (e) {
      _showError('Could not delete: $e');
    }
  }

  Future<void> _togglePin(GroupMessage message) async {
    try {
      await _chatService.setPinnedMessage(
        tripId: widget.tripId,
        messageId: message.isPinned ? null : message.id,
      );
    } catch (e) {
      _showError('Could not update pin: $e');
    }
  }

  /// Long-press action sheet — Reply always; Edit/Delete only for a
  /// message the signed-in user sent (and hasn't been deleted); Pin/
  /// Unpin for anyone, on any non-deleted message.
  void _showMessageActions(GroupMessage message, String? myUid) {
    if (message.isDeleted) return;
    final mine = message.userId == myUid;
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
                Icons.reply_rounded,
                color: sheetContext.colors.ink,
              ),
              title: Text(
                'Reply',
                style: TextStyle(color: sheetContext.colors.ink),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _startReply(message);
              },
            ),
            ListTile(
              leading: Icon(
                message.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                color: sheetContext.colors.ink,
              ),
              title: Text(
                message.isPinned ? 'Unpin' : 'Pin',
                style: TextStyle(color: sheetContext.colors.ink),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _togglePin(message);
              },
            ),
            if (mine && message.body != null)
              ListTile(
                leading: Icon(
                  Icons.edit_rounded,
                  color: sheetContext.colors.ink,
                ),
                title: Text(
                  'Edit',
                  style: TextStyle(color: sheetContext.colors.ink),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _editMessage(message);
                },
              ),
            if (mine)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete for everyone',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDelete(message);
                },
              ),
          ],
        ),
      ),
    );
  }

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
            ListTile(
              leading: Icon(
                Icons.history_rounded,
                color: sheetContext.colors.ink,
              ),
              title: Text(
                'History',
                style: TextStyle(color: sheetContext.colors.ink),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _openHistory();
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

  Widget _buildReplyQuote(GroupMessage m, bool mine) {
    final preview = m.replyPreview;
    if (preview == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => _jumpToMessage(preview.messageId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: mine
              ? Colors.white.withValues(alpha: 0.12)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: mine
                  ? Colors.white.withValues(alpha: 0.6)
                  : AppColors.accent,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              preview.isDeleted ? 'Deleted message' : preview.senderName,
              style: TextStyle(
                color: mine
                    ? Colors.white.withValues(alpha: 0.85)
                    : AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
            if (!preview.isDeleted)
              Text(
                preview.body ?? (preview.hasAttachment ? 'Photo/Video' : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mine
                      ? Colors.white.withValues(alpha: 0.75)
                      : context.colors.muted,
                  fontSize: 11.5,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPinnedBanner(GroupMessage pinned) {
    return GestureDetector(
      onTap: () => _jumpToMessage(pinned.id),
      child: Container(
        color: context.colors.card,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.push_pin_rounded, size: 15, color: AppColors.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pinned · ${pinned.senderName}',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 10.5,
                    ),
                  ),
                  Text(
                    pinned.body ??
                        (pinned.attachment != null ? 'Photo/Video' : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.ink, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              iconSize: 18,
              onPressed: () => _togglePin(pinned),
              icon: Icon(Icons.close_rounded, color: context.colors.muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(List<GroupMember> members) {
    if (_typingUserIds.isEmpty) return const SizedBox.shrink();
    final memberById = {for (final m in members) m.userId: m};
    final names = [
      for (final id in _typingUserIds) memberById[id]?.label ?? 'Someone',
    ];
    final text = names.length == 1
        ? '${names.first} is typing…'
        : '${names.join(', ')} are typing…';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Text(
        text,
        style: TextStyle(
          color: context.colors.muted,
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  /// A "so-and-so joined/left the group" system message — centered,
  /// muted, no bubble — interleaved into the chat feed by
  /// [_buildMessageColumn]'s [_ChatFeedItem] list, same as WhatsApp.
  Widget _buildActivityTile(GroupActivityEvent event) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            event.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageColumn(
    GroupMessage? pinned,
    List<_ChatFeedItem> feedItems,
    List<GroupMember> members,
    String? myUid,
  ) {
    return Column(
      children: [
        if (pinned != null) _buildPinnedBanner(pinned),
        Expanded(
          child: Stack(
            children: [
              ListView.builder(
                controller: _scrollController,
                // Wider than the default 250
                // so _jumpToMessage's
                // estimated jump lands
                // somewhere ensureVisible can
                // already find built, even
                // when the 70px/message
                // guess is off.
                cacheExtent: 3000,
                padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                itemCount: feedItems.length,
                itemBuilder: (context, index) {
                  final item = feedItems[index];
                  final activity = item.activity;
                  if (activity != null) {
                    return _buildActivityTile(activity);
                  }
                  final m = item.message!;
                  final mine = m.userId == myUid;
                  final otherMemberIds = members
                      .map((mem) => mem.userId)
                      .where((id) => id != m.userId);
                  final seenByAll = m.seenByAll(otherMemberIds);
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
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!mine) ...[
                            GestureDetector(
                              onTap: () => _showMemberProfile(m),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Color(m.senderColor),
                                child: Text(
                                  m.senderName[0].toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
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
                                    onTap: () => _showMemberProfile(m),
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        bottom: 3,
                                        left: 4,
                                      ),
                                      child: Text(
                                        m.senderName,
                                        style: TextStyle(
                                          color: context.colors.muted,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                GestureDetector(
                                  onTap: myUid == null
                                      ? null
                                      : mine
                                      ? () => _showMessageInfo(m, members)
                                      // Tapping
                                      // someone
                                      // else's
                                      // message
                                      // reacts
                                      // directly —
                                      // long-press
                                      // opens
                                      // the full
                                      // action
                                      // sheet.
                                      : () => _reactTo(m, myUid),
                                  onLongPress: myUid == null
                                      ? null
                                      : () => _showMessageActions(m, myUid),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: mine
                                          ? context.colors.ink
                                          : context.colors.card,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildReplyQuote(m, mine),
                                        if (m.isDeleted)
                                          Text(
                                            'This message was deleted',
                                            style: TextStyle(
                                              color: mine
                                                  ? Colors.white.withValues(
                                                      alpha: 0.6,
                                                    )
                                                  : context.colors.muted,
                                              fontStyle: FontStyle.italic,
                                              fontSize: 13,
                                            ),
                                          )
                                        else ...[
                                          if (m.attachment != null) ...[
                                            ChatAttachmentView(
                                              attachment: m.attachment!,
                                            ),
                                            if (m.body != null)
                                              const SizedBox(height: 6),
                                          ],
                                          if (m.body != null)
                                            Text(
                                              m.body!,
                                              style: TextStyle(
                                                color: mine
                                                    ? Colors.white
                                                    : context.colors.ink,
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                        ],
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
                                      reactionsByUser: m.reactions,
                                      onTap: () =>
                                          _showReactionDetails(m, members),
                                    ),
                                  ),
                                GestureDetector(
                                  // A photo
                                  // bubble has
                                  // its own tap
                                  // target
                                  // (open
                                  // fullscreen
                                  // preview)
                                  // that wins
                                  // the gesture
                                  // arena over
                                  // the
                                  // bubble's
                                  // tap, so it
                                  // can never
                                  // reach
                                  // _showMessageInfo.
                                  // This ticks
                                  // row sits
                                  // below the
                                  // image and
                                  // is always
                                  // free, so
                                  // it's the
                                  // reliable
                                  // way to open
                                  // "Seen by"
                                  // for photo
                                  // messages
                                  // too.
                                  onTap: mine && myUid != null
                                      ? () => _showMessageInfo(m, members)
                                      : null,
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      top: 4,
                                      left: mine ? 0 : 4,
                                      right: mine ? 4 : 0,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          formatChatDateTime(m.createdAt),
                                          style: TextStyle(
                                            color: context.colors.muted,
                                            fontSize: 10,
                                          ),
                                        ),
                                        if (m.editedAt != null &&
                                            !m.isDeleted) ...[
                                          SizedBox(width: 3),
                                          Text(
                                            '· edited',
                                            style: TextStyle(
                                              color: context.colors.muted,
                                              fontSize: 10,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                        if (mine) ...[
                                          SizedBox(width: 4),
                                          Icon(
                                            Icons.done_all_rounded,
                                            size: 14,
                                            color: seenByAll
                                                ? _seenBlue
                                                : context.colors.muted,
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
              ),
              JumpToLatestButton(
                show: _showJumpToLatest,
                onTap: _scrollToLatest,
              ),
            ],
          ),
        ),
        _buildTypingIndicator(members),
      ],
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
                  stream: _membersStream,
                  builder: (context, memberSnap) {
                    final members = memberSnap.data ?? const <GroupMember>[];
                    _latestMembers = members;
                    return StreamBuilder<List<GroupMessage>>(
                      stream: _messagesStream,
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
                        _notifyMentions(rawMessages, myUid);
                        return StreamBuilder<
                          Map<String, Map<String, DateTime>>
                        >(
                          stream: _readsStream,
                          builder: (context, readsSnapshot) {
                            final reads = readsSnapshot.data ?? const {};
                            return StreamBuilder<
                              Map<String, Map<String, String>>
                            >(
                              stream: _reactionsStream,
                              builder: (context, reactionsSnapshot) {
                                final reactionsByMessage =
                                    reactionsSnapshot.data ?? const {};
                                return StreamBuilder<List<ReactionEvent>>(
                                  stream: _reactionEventsStream,
                                  builder: (context, eventsSnapshot) {
                                    _notifyNewReactions(
                                      rawMessages,
                                      eventsSnapshot.data ??
                                          const <ReactionEvent>[],
                                      myUid,
                                      members,
                                    );
                                    return StreamBuilder<
                                      List<GroupActivityEvent>
                                    >(
                                      stream: _activityStream,
                                      builder: (context, activitySnapshot) {
                                        final activityEvents =
                                            activitySnapshot.data ??
                                            const <GroupActivityEvent>[];
                                        final messages = [
                                          for (final m in rawMessages)
                                            m
                                                .withReadBy(
                                                  reads[m.id] ?? const {},
                                                )
                                                .withReactions(
                                                  reactionsByMessage[m.id] ??
                                                      const {},
                                                ),
                                        ];
                                        _latestMessages = messages;
                                        GroupMessage? pinned;
                                        for (final m in messages) {
                                          if (m.isPinned) {
                                            pinned = m;
                                            break;
                                          }
                                        }
                                        final feedItems =
                                            <_ChatFeedItem>[
                                              for (final m in messages)
                                                _ChatFeedItem.message(m),
                                              for (final e in activityEvents)
                                                _ChatFeedItem.activity(e),
                                            ]..sort(
                                              (a, b) => a.createdAt.compareTo(
                                                b.createdAt,
                                              ),
                                            );
                                        return _buildMessageColumn(
                                          pinned,
                                          feedItems,
                                          members,
                                          myUid,
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
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: ChatComposer(
                onSendText: _send,
                onSendMedia: _sendMedia,
                replyTarget: _replyTarget == null
                    ? null
                    : ComposerReplyTarget(
                        messageId: _replyTarget!.id,
                        senderLabel: _replyTarget!.senderName,
                        body: _replyTarget!.body,
                        hasAttachment: _replyTarget!.attachment != null,
                      ),
                onCancelReply: _cancelReply,
                mentionCandidates: [
                  for (final m in _latestMembers)
                    if (m.userId != myUid)
                      MentionCandidate(
                        userId: m.userId,
                        label: m.label,
                        avatarColor: m.avatarColor,
                      ),
                ],
                onTyping: () => _chatService.sendTyping(widget.tripId),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
