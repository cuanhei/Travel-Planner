import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_attachment.dart';
import '../../models/direct_message.dart';
import '../../services/direct_message_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/chat/chat_attachment_view.dart';
import '../../widgets/chat/chat_composer.dart';
import '../../widgets/detail_header.dart';

/// Private 1:1 chat with another member of the same trip, opened from
/// their tile in the Group Travel member list, or from the Personal
/// Message inbox. No per-message ticks here (unlike Group Chat) — just
/// who sent what and when, plus a single "read up to here" marker that
/// drives the inbox's unread badge.
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

class _DirectChatScreenState extends State<DirectChatScreen> {
  final _dmService = DirectMessageService();
  final _scrollController = ScrollController();

  /// -1 until the first snapshot arrives, so the initial load always
  /// scrolls to the bottom; after that, only a message count *increase*
  /// triggers another jump.
  int _lastMessageCount = -1;

  @override
  void dispose() {
    _scrollController.dispose();
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
      attachment: ChatAttachment(
        type: media.type,
        url: url,
        durationMs: media.durationMs,
      ),
    );
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
            ),
            Expanded(
              child: StreamBuilder<List<DirectMessage>>(
                stream: _dmService.watchConversation(
                  tripId: widget.tripId,
                  otherUserId: widget.otherUserId,
                ),
                builder: (context, snapshot) {
                  final messages = snapshot.data ?? const <DirectMessage>[];
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet — say hi!',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  _maybeScrollToBottom(messages.length);
                  return ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final m = messages[index];
                      final mine = m.senderId == myUid;
                      return Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisAlignment: mine
                              ? MainAxisAlignment.end
                              : MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!mine) ...[
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: Color(widget.otherUserColor),
                                child: Text(
                                  widget.otherUserName[0].toUpperCase(),
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
                                  Container(
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
                                    child: Text(
                                      formatChatDateTime(m.createdAt),
                                      style: TextStyle(
                                        color: context.colors.muted,
                                        fontSize: 10,
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
