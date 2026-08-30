import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/group_message.dart';
import '../../services/chat_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Live group chat for a trip, backed by Supabase Realtime.
class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _controller = TextEditingController();
  final _chatService = ChatService();
  late final Future<String> _tripNameFuture = TripService().getTripName(
    widget.tripId,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _chatService.sendMessage(tripId: widget.tripId, body: text);
    FocusScope.of(context).unfocus();
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
              ),
            ),
            Expanded(
              child: StreamBuilder<List<GroupMessage>>(
                stream: _chatService.watchMessages(widget.tripId),
                builder: (context, snapshot) {
                  final messages = snapshot.data ?? const <GroupMessage>[];
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        'No messages yet — say hi!',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final m = messages[index];
                      final mine = m.userId == myUid;
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
                              SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Column(
                                crossAxisAlignment: mine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  if (!mine)
                                    Padding(
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
                                    child: Text(
                                      m.body,
                                      style: TextStyle(
                                        color: mine
                                            ? Colors.white
                                            : context.colors.ink,
                                        fontSize: 13,
                                        height: 1.35,
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: context.colors.ink, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Message the group…',
                        hintStyle: TextStyle(color: context.colors.muted),
                        filled: true,
                        fillColor: context.colors.card,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  SizedBox(width: 8),
                  Material(
                    color: context.colors.ink,
                    shape: CircleBorder(),
                    child: InkWell(
                      customBorder: CircleBorder(),
                      onTap: _send,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
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
  }
}
