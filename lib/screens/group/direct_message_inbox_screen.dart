import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_attachment.dart';
import '../../models/direct_message.dart';
import '../../models/group_member.dart';
import '../../services/direct_message_service.dart';
import '../../services/group_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/detail_header.dart';
import 'direct_chat_screen.dart';

String _previewFor(DirectMessage? message) {
  if (message == null) return 'Say hi!';
  final attachment = message.attachment;
  if (attachment != null) {
    return switch (attachment.type) {
      ChatAttachmentType.image => '📷 Photo',
      ChatAttachmentType.video => '🎥 Video',
    };
  }
  return message.body ?? '';
}

class DirectMessageInboxScreen extends StatefulWidget {
  const DirectMessageInboxScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<DirectMessageInboxScreen> createState() =>
      _DirectMessageInboxScreenState();
}

class _DirectMessageInboxScreenState extends State<DirectMessageInboxScreen> {
  final _groupService = GroupService();
  final _dmService = DirectMessageService();

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Personal Messages',
              subtitle: 'Message a trip-mate directly',
            ),
            Expanded(
              child: StreamBuilder<List<GroupMember>>(
                stream: _groupService.watchMembers(widget.tripId),
                builder: (context, memberSnap) {
                  final members = (memberSnap.data ?? const <GroupMember>[])
                      .where((m) => m.userId != myUid)
                      .toList();
                  if (members.isEmpty) {
                    return Center(
                      child: Text(
                        'No other members yet',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  return StreamBuilder<List<DirectMessage>>(
                    stream: _dmService.watchAllMyMessages(widget.tripId),
                    builder: (context, msgSnap) {
                      final messages = msgSnap.data ?? const <DirectMessage>[];
                      return StreamBuilder<Map<String, DateTime>>(
                        stream: _dmService.watchAllLastRead(widget.tripId),
                        builder: (context, readSnap) {
                          final lastRead = readSnap.data ?? const {};

                          DirectMessage? lastMessageWith(String otherId) {
                            DirectMessage? latest;
                            for (final m in messages) {
                              if (m.senderId != otherId &&
                                  m.recipientId != otherId) {
                                continue;
                              }
                              if (latest == null ||
                                  m.createdAt.isAfter(latest.createdAt)) {
                                latest = m;
                              }
                            }
                            return latest;
                          }

                          int unreadFrom(String otherId) {
                            final since = lastRead[otherId];
                            return messages
                                .where(
                                  (m) =>
                                      m.senderId == otherId &&
                                      (since == null ||
                                          m.createdAt.isAfter(since)),
                                )
                                .length;
                          }

                          final rows =
                              members
                                  .map(
                                    (m) => (
                                      member: m,
                                      last: lastMessageWith(m.userId),
                                      unread: unreadFrom(m.userId),
                                    ),
                                  )
                                  .toList()
                                ..sort((a, b) {
                                  if (a.last == null && b.last == null) {
                                    return a.member.displayName.compareTo(
                                      b.member.displayName,
                                    );
                                  }
                                  if (a.last == null) return 1;
                                  if (b.last == null) return -1;
                                  return b.last!.createdAt.compareTo(
                                    a.last!.createdAt,
                                  );
                                });

                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                            itemCount: rows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final row = rows[index];
                              final member = row.member;
                              return Material(
                                color: context.colors.card,
                                borderRadius: BorderRadius.circular(16),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => DirectChatScreen(
                                        tripId: widget.tripId,
                                        otherUserId: member.userId,
                                        otherUserName: member.displayName,
                                        otherUserColor: member.avatarColor,
                                      ),
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 22,
                                          backgroundColor: Color(
                                            member.avatarColor,
                                          ),
                                          child: Text(
                                            member.displayName[0].toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                member.displayName,
                                                style: TextStyle(
                                                  color: context.colors.ink,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _previewFor(row.last),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: context.colors.muted,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            if (row.last != null)
                                              Text(
                                                formatChatDateTime(
                                                  row.last!.createdAt,
                                                ),
                                                style: TextStyle(
                                                  color: context.colors.muted,
                                                  fontSize: 9.5,
                                                ),
                                              ),
                                            if (row.unread > 0) ...[
                                              const SizedBox(height: 4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 3,
                                                    ),
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 20,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  row.unread > 99
                                                      ? '99+'
                                                      : '${row.unread}',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
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
          ],
        ),
      ),
    );
  }
}
