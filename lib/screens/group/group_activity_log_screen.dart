import 'package:flutter/material.dart';

import '../../models/group_activity_event.dart';
import '../../services/group_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/chat_time.dart';
import '../../widgets/detail_header.dart';

/// Full activity feed for a trip's group — currently just membership
/// changes (joined/left), the same events Group Chat shows inline as
/// system messages, opened from its "⋮" > History menu entry.
class GroupActivityLogScreen extends StatelessWidget {
  const GroupActivityLogScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(title: 'History'),
            Expanded(
              child: StreamBuilder<List<GroupActivityEvent>>(
                stream: GroupService().watchActivityLog(tripId),
                builder: (context, snapshot) {
                  final events = snapshot.data ?? const <GroupActivityEvent>[];
                  if (events.isEmpty) {
                    return Center(
                      child: Text(
                        'No activity yet',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final event = events[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: Color(event.avatarColor),
                              child: Icon(
                                event.isJoined
                                    ? Icons.login_rounded
                                    : Icons.logout_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                event.message,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            Text(
                              formatChatDateTime(event.createdAt),
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 11,
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
          ],
        ),
      ),
    );
  }
}
