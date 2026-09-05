import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_attachment.dart';
import '../../models/direct_message.dart';
import '../../models/reaction_event.dart';
import '../../services/direct_message_service.dart';
import '../../services/reaction_seen_service.dart';
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
/// for one to mean anything to) and @mention (pointless in a 1:1).
/// Long-press any message for reply/edit/delete/pin.
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

  /// The message currently being replied to, shown as a quote banner in
  /// the composer — cleared once the reply is sent or cancelled.
  DirectMessage? _replyTarget;

  GlobalKey _keyFor(String messageId) =>
      _messageKeys.putIfAbsent(messageId, () => GlobalKey());

  // Cached once, not created inline in build() — `.stream()` returns a
  // new Supabase stream object on every call, so building these inline
  // would make each nested StreamBuilder below tear down and
  // resubscribe (briefly emitting null/empty data) on *every* rebuild
  // of this screen, not just when it first opens.
  late final _lastReadStream = _dmService.watchTheirLastRead(
    tripId: widget.tripId,
    otherUserId: widget.otherUserId,
  );
  late final _conversationStream = _dmService.watchConversation(
    tripId: widget.tripId,
    otherUserId: widget.otherUserId,
  );
  late final _reactionsStream = _dmService.watchReactions(widget.tripId);
  late final _reactionEventsStream = _dmService.watchReactionEvents(
    widget.tripId,
  );

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  /// Cutoff up to which the "reacted to your message" toast has already
  /// run — persisted server-side (chat_reaction_seen_state) so it
  /// survives leaving and reopening the chat, or switching devices,
  /// instead of resetting every time this screen is rebuilt. `null`
  /// until [_initReactionsSeenState] has loaded it (or bootstrapped it
  /// for a conversation that's never used this feature before) —
  /// [_notifyNewReactions] stays a no-op until [_reactionsSeenAtReady].
  DateTime? _reactionsSeenAt;
  bool _reactionsSeenAtReady = false;

  /// WhatsApp-style "jump to latest" — shown once the user has scrolled
  /// away from the bottom, so a new message doesn't yank them back down
  /// mid-read (see [_maybeScrollToBottom]).
  bool _showJumpToLatest = false;

  bool _otherTyping = false;
  Timer? _typingTimer;
  StreamSubscription<void>? _typingSub;

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
    _initReactionsSeenState(conversationId);
    _scrollController.addListener(_onScroll);
    _typingSub = _dmService
        .watchTyping(tripId: widget.tripId, otherUserId: widget.otherUserId)
        .listen((_) => _onTyping());
  }

  Future<void> _initReactionsSeenState(String conversationId) async {
    DateTime? seenAt;
    try {
      seenAt = await loadReactionsSeenAt(conversationId);
    } catch (_) {
      // Fall through — treat as "never seen", same as a brand new
      // conversation.
    }
    // First time this feature has run for this conversation: bootstrap
    // to the epoch (not now) so any reaction that already landed on one
    // of my messages — including while I hadn't opened this
    // conversation yet — still gets notified once, instead of being
    // silently treated as already-seen.
    seenAt ??= DateTime.fromMillisecondsSinceEpoch(0);
    if (!mounted) return;
    setState(() {
      _reactionsSeenAt = seenAt;
      _reactionsSeenAtReady = true;
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

  void _onTyping() {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _otherTyping = false);
    });
    if (!_otherTyping) setState(() => _otherTyping = true);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _highlightTimer?.cancel();
    _typingTimer?.cancel();
    _typingSub?.cancel();
    super.dispose();
  }

  Future<void> _send(
    String text, {
    String? replyToId,
    List<String>? mentionedUserIds,
  }) {
    return _dmService.sendMessage(
      tripId: widget.tripId,
      recipientId: widget.otherUserId,
      body: text,
      replyToId: replyToId,
    );
  }

  Future<void> _sendMedia(
    PickedChatMedia media, {
    String? replyToId,
    String? caption,
  }) async {
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
      replyToId: replyToId,
      body: caption,
    );
  }

  /// Toasts "{name} reacted {emoji} to your message" the moment the
  /// other participant reacts to a message the signed-in user sent,
  /// then jumps to and highlights that message — like tapping a
  /// notification. Each reaction only ever triggers this once:
  /// [_reactionsSeenAt] is the persisted (chat_reaction_seen_state)
  /// cutoff, advanced past the newest notified reaction's timestamp
  /// every time this runs, so re-opening the chat later (even on
  /// another device) never replays it.
  void _notifyNewReactions(
    List<DirectMessage> rawMessages,
    List<ReactionEvent> events,
    String? myUid,
  ) {
    if (myUid == null || !_reactionsSeenAtReady) return;
    final cutoff = _reactionsSeenAt;
    final messageById = {for (final m in rawMessages) m.id: m};
    final newEvents = <ReactionEvent>[];
    for (final e in events) {
      if (e.userId != widget.otherUserId) continue;
      if (cutoff != null && !e.createdAt.isAfter(cutoff)) continue;
      final message = messageById[e.messageId];
      if (message == null || message.senderId != myUid) continue;
      newEvents.add(e);
    }
    if (newEvents.isEmpty) return;
    newEvents.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final newCutoff = newEvents.last.createdAt;
    final conversationId = _backgroundConversationId(
      widget.tripId,
      widget.otherUserId,
    );
    // Advance the in-memory cutoff synchronously (not via setState) so a
    // rebuild triggered before the save below completes doesn't re-toast
    // the same events.
    _reactionsSeenAt = newCutoff;
    unawaited(saveReactionsSeenAt(conversationId, newCutoff));

    final toNotify = [
      for (final e in newEvents)
        '${widget.otherUserName} reacted ${e.emoji} to your message',
    ];
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
    // Covers both the initial load and a new message landing while
    // already open (and already at the bottom) — either way, the
    // viewer has now seen it.
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

  void _startReply(DirectMessage message) {
    setState(() => _replyTarget = message);
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  Future<void> _editMessage(DirectMessage message) async {
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
      await _dmService.editMessage(messageId: message.id, body: result);
    } catch (e) {
      _showError('Could not save: $e');
    }
  }

  Future<void> _confirmDelete(DirectMessage message) async {
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
      await _dmService.deleteMessage(message.id);
    } catch (e) {
      _showError('Could not delete: $e');
    }
  }

  Future<void> _togglePin(DirectMessage message) async {
    try {
      await _dmService.setPinnedMessage(
        tripId: widget.tripId,
        otherUserId: widget.otherUserId,
        messageId: message.isPinned ? null : message.id,
      );
    } catch (e) {
      _showError('Could not update pin: $e');
    }
  }

  /// Long-press action sheet — Reply always; Edit/Delete only for a
  /// message the signed-in user sent (and hasn't been deleted); Pin/
  /// Unpin for either participant, on any non-deleted message.
  void _showMessageActions(DirectMessage message, String? myUid) {
    if (message.isDeleted) return;
    final mine = message.senderId == myUid;
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

  String _labelFor(String userId, String? myUid) =>
      userId == myUid ? 'You' : widget.otherUserName;

  Widget _buildReplyQuote(DirectMessage m, bool mine, String? myUid) {
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
              preview.isDeleted
                  ? 'Deleted message'
                  : _labelFor(preview.senderId, myUid),
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

  Widget _buildPinnedBanner(DirectMessage pinned, String? myUid) {
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
                    'Pinned · ${_labelFor(pinned.senderId, myUid)}',
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

  Widget _buildTypingIndicator() {
    if (!_otherTyping) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Text(
        '${widget.otherUserName} is typing…',
        style: TextStyle(
          color: context.colors.muted,
          fontSize: 11.5,
          fontStyle: FontStyle.italic,
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
                            return StreamBuilder<List<ReactionEvent>>(
                              stream: _reactionEventsStream,
                              builder: (context, eventsSnapshot) {
                                _notifyNewReactions(
                                  rawMessages,
                                  eventsSnapshot.data ??
                                      const <ReactionEvent>[],
                                  myUid,
                                );
                                final messages = [
                                  for (final m in rawMessages)
                                    m.withReactions(
                                      reactionsByMessage[m.id] ?? const {},
                                    ),
                                ];
                                _latestMessages = messages;
                                DirectMessage? pinned;
                                for (final m in messages) {
                                  if (m.isPinned) {
                                    pinned = m;
                                    break;
                                  }
                                }
                                return Column(
                                  children: [
                                    if (pinned != null)
                                      _buildPinnedBanner(pinned, myUid),
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          ListView.builder(
                                            controller: _scrollController,
                                            // Wider than the default 250 so
                                            // _jumpToMessage's estimated
                                            // jump lands somewhere
                                            // ensureVisible can already find
                                            // built.
                                            cacheExtent: 3000,
                                            padding: EdgeInsets.fromLTRB(
                                              20,
                                              8,
                                              20,
                                              8,
                                            ),
                                            itemCount: messages.length,
                                            itemBuilder: (context, index) {
                                              final m = messages[index];
                                              final mine = m.senderId == myUid;
                                              final seenAt =
                                                  mine &&
                                                      theirLastRead != null &&
                                                      !theirLastRead.isBefore(
                                                        m.createdAt,
                                                      )
                                                  ? theirLastRead
                                                  : null;
                                              return AnimatedContainer(
                                                key: _keyFor(m.id),
                                                duration: const Duration(
                                                  milliseconds: 400,
                                                ),
                                                color:
                                                    _highlightedMessageId ==
                                                        m.id
                                                    ? _highlightColor
                                                    : Colors.transparent,
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                    bottom: 12,
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: mine
                                                        ? MainAxisAlignment.end
                                                        : MainAxisAlignment
                                                              .start,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      if (!mine) ...[
                                                        CircleAvatar(
                                                          radius: 14,
                                                          backgroundColor: Color(
                                                            widget
                                                                .otherUserColor,
                                                          ),
                                                          child: Text(
                                                            widget
                                                                .otherUserName[0]
                                                                .toUpperCase(),
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(width: 8),
                                                      ],
                                                      Flexible(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              mine
                                                              ? CrossAxisAlignment
                                                                    .end
                                                              : CrossAxisAlignment
                                                                    .start,
                                                          children: [
                                                            GestureDetector(
                                                              onTap:
                                                                  myUid == null
                                                                  ? null
                                                                  : mine
                                                                  ? () =>
                                                                        _showMessageInfo(
                                                                          seenAt,
                                                                        )
                                                                  // Tapping
                                                                  // their
                                                                  // message
                                                                  // reacts
                                                                  // directly —
                                                                  // long-press
                                                                  // opens the
                                                                  // full
                                                                  // action
                                                                  // sheet.
                                                                  : () =>
                                                                        _reactTo(
                                                                          m,
                                                                          myUid,
                                                                        ),
                                                              onLongPress:
                                                                  myUid == null
                                                                  ? null
                                                                  : () =>
                                                                        _showMessageActions(
                                                                          m,
                                                                          myUid,
                                                                        ),
                                                              child: Container(
                                                                padding:
                                                                    EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          14,
                                                                      vertical:
                                                                          10,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: mine
                                                                      ? context
                                                                            .colors
                                                                            .ink
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
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    _buildReplyQuote(
                                                                      m,
                                                                      mine,
                                                                      myUid,
                                                                    ),
                                                                    if (m
                                                                        .isDeleted)
                                                                      Text(
                                                                        'This message was deleted',
                                                                        style: TextStyle(
                                                                          color:
                                                                              mine
                                                                              ? Colors.white.withValues(
                                                                                  alpha: 0.6,
                                                                                )
                                                                              : context.colors.muted,
                                                                          fontStyle:
                                                                              FontStyle.italic,
                                                                          fontSize:
                                                                              13,
                                                                        ),
                                                                      )
                                                                    else ...[
                                                                      if (m.attachment !=
                                                                          null) ...[
                                                                        ChatAttachmentView(
                                                                          attachment:
                                                                              m.attachment!,
                                                                        ),
                                                                        if (m.body !=
                                                                            null)
                                                                          const SizedBox(
                                                                            height:
                                                                                6,
                                                                          ),
                                                                      ],
                                                                      if (m.body !=
                                                                          null)
                                                                        Text(
                                                                          m.body!,
                                                                          style: TextStyle(
                                                                            color:
                                                                                mine
                                                                                ? Colors.white
                                                                                : context.colors.ink,
                                                                            fontSize:
                                                                                13,
                                                                            height:
                                                                                1.35,
                                                                          ),
                                                                        ),
                                                                    ],
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                            if (m
                                                                .reactions
                                                                .isNotEmpty)
                                                              Padding(
                                                                padding:
                                                                    EdgeInsets.only(
                                                                      top: 4,
                                                                      left: mine
                                                                          ? 0
                                                                          : 4,
                                                                      right:
                                                                          mine
                                                                          ? 4
                                                                          : 0,
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
                                                              // A photo
                                                              // bubble has
                                                              // its own tap
                                                              // target (open
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
                                                              // reliable way
                                                              // to open
                                                              // "Seen" for
                                                              // photo
                                                              // messages
                                                              // too.
                                                              onTap:
                                                                  mine &&
                                                                      myUid !=
                                                                          null
                                                                  ? () =>
                                                                        _showMessageInfo(
                                                                          seenAt,
                                                                        )
                                                                  : null,
                                                              child: Padding(
                                                                padding:
                                                                    EdgeInsets.only(
                                                                      top: 4,
                                                                      left: mine
                                                                          ? 0
                                                                          : 4,
                                                                      right:
                                                                          mine
                                                                          ? 4
                                                                          : 0,
                                                                    ),
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Text(
                                                                      formatChatDateTime(
                                                                        m.createdAt,
                                                                      ),
                                                                      style: TextStyle(
                                                                        color: context
                                                                            .colors
                                                                            .muted,
                                                                        fontSize:
                                                                            10,
                                                                      ),
                                                                    ),
                                                                    if (m.editedAt !=
                                                                            null &&
                                                                        !m.isDeleted) ...[
                                                                      SizedBox(
                                                                        width:
                                                                            3,
                                                                      ),
                                                                      Text(
                                                                        '· edited',
                                                                        style: TextStyle(
                                                                          color: context
                                                                              .colors
                                                                              .muted,
                                                                          fontSize:
                                                                              10,
                                                                          fontStyle:
                                                                              FontStyle.italic,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                    if (mine) ...[
                                                                      SizedBox(
                                                                        width:
                                                                            4,
                                                                      ),
                                                                      Icon(
                                                                        Icons
                                                                            .done_all_rounded,
                                                                        size:
                                                                            14,
                                                                        color:
                                                                            seenAt !=
                                                                                null
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
                                    _buildTypingIndicator(),
                                  ],
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
                        senderLabel: _labelFor(_replyTarget!.senderId, myUid),
                        body: _replyTarget!.body,
                        hasAttachment: _replyTarget!.attachment != null,
                      ),
                onCancelReply: _cancelReply,
                onTyping: () => _dmService.sendTyping(
                  tripId: widget.tripId,
                  otherUserId: widget.otherUserId,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
