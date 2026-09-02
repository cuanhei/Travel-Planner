import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_attachment.dart';
import '../../models/group_message.dart';
import '../../services/chat_service.dart';
import '../../services/group_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/chat/chat_attachment_view.dart';
import '../../widgets/chat/chat_background.dart';
import '../../widgets/chat/chat_composer.dart';
import '../../widgets/detail_header.dart';
import 'direct_chat_screen.dart';

/// WhatsApp's read-receipt blue.
const _seenBlue = Color(0xFF34B7F1);

/// Live group chat for a trip, backed by Supabase Realtime. Every
/// message shows when it was sent; a message you sent also shows a
/// tick — gray for sent-but-unseen, blue (with a "Seen" timestamp) once
/// another member has opened the chat and read it.
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

  @override
  void initState() {
    super.initState();
    loadChatBackgroundKey(widget.tripId).then((key) {
      if (mounted) setState(() => _background = chatBackgroundByKey(key));
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
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
      attachment: ChatAttachment(
        type: media.type,
        url: url,
        durationMs: media.durationMs,
      ),
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
                        await saveChatBackgroundKey(widget.tripId, bg.key);
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
                child: StreamBuilder<List<GroupMessage>>(
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
                    final rawMessages = snapshot.data ?? const <GroupMessage>[];
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
                    return StreamBuilder<Map<String, Map<String, DateTime>>>(
                      stream: _chatService.watchReadReceipts(widget.tripId),
                      builder: (context, readsSnapshot) {
                        final reads = readsSnapshot.data ?? const {};
                        final messages = [
                          for (final m in rawMessages)
                            m.withReadBy(reads[m.id] ?? const {}),
                        ];
                        return ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final m = messages[index];
                            final mine = m.userId == myUid;
                            final seenAt = myUid == null
                                ? null
                                : m.seenAt(myUid);
                            return Padding(
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
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: mine
                                                ? context.colors.ink
                                                : context.colors.card,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (m.attachment != null) ...[
                                                ChatAttachmentView(
                                                  attachment: m.attachment!,
                                                  mine: mine,
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
                                          ),
                                        ),
                                        Padding(
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
                                              if (mine) ...[
                                                SizedBox(width: 4),
                                                Icon(
                                                  seenAt != null
                                                      ? Icons.done_all_rounded
                                                      : Icons.check_rounded,
                                                  size: 14,
                                                  color: seenAt != null
                                                      ? _seenBlue
                                                      : context.colors.muted,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (mine && seenAt != null)
                                          Padding(
                                            padding: EdgeInsets.only(
                                              top: 2,
                                              right: 4,
                                            ),
                                            child: Text(
                                              'Seen ${formatChatDateTime(seenAt)}',
                                              style: TextStyle(
                                                color: _seenBlue,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
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
