import 'package:flutter/material.dart';

import '../../models/group_member.dart';
import '../../services/group_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'group_chat_screen.dart';
import 'invite_member_screen.dart';
import 'voting_screen.dart';

/// Group trip hub: members list and links to shared itinerary, chat,
/// and voting. Backed live by Supabase.
class GroupDashboardScreen extends StatefulWidget {
  const GroupDashboardScreen({super.key});

  @override
  State<GroupDashboardScreen> createState() => _GroupDashboardScreenState();
}

class _GroupDashboardScreenState extends State<GroupDashboardScreen> {
  final _groupService = GroupService();
  late final Future<String> _tripIdFuture = TripService().ensureDemoTrip();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _tripIdFuture,
          builder: (context, tripSnap) {
            if (tripSnap.connectionState != ConnectionState.done) {
              return const Column(
                children: [
                  DetailHeader(title: 'Group Travel'),
                  Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              );
            }
            if (tripSnap.hasError) {
              return Column(
                children: [
                  const DetailHeader(title: 'Group Travel'),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Sign in to view your group.',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ),
                  ),
                ],
              );
            }
            final tripId = tripSnap.data!;

            return StreamBuilder<List<GroupMember>>(
              stream: _groupService.watchMembers(tripId),
              builder: (context, memberSnap) {
                final members = memberSnap.data ?? const <GroupMember>[];

                return Column(
                  children: [
                    DetailHeader(
                      title: 'Group Travel',
                      subtitle:
                          'Penang Adventure · ${members.length} member${members.length == 1 ? '' : 's'}',
                      trailing: IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => InviteMemberScreen(
                              tripId: tripId,
                              tripName: 'Penang Adventure',
                            ),
                          ),
                        ),
                        icon: Icon(
                          Icons.person_add_alt_1_rounded,
                          color: context.colors.ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [
                          Text(
                            'Members',
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 14),
                          ...members.map(
                            (m) => Container(
                              margin: EdgeInsets.only(bottom: 10),
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: context.colors.card,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.colors.ink.withValues(
                                      alpha: 0.05,
                                    ),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Color(m.avatarColor),
                                    child: Text(
                                      m.displayName[0].toUpperCase(),
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.displayName,
                                          style: TextStyle(
                                            color: context.colors.ink,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        Text(
                                          m.isOrganizer
                                              ? 'Organizer'
                                              : 'Member',
                                          style: TextStyle(
                                            color: context.colors.muted,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: Color(0xFF11998E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: 24),
                          _ActionRow(
                            icon: Icons.chat_bubble_rounded,
                            color: AppColors.accent,
                            title: 'Group Chat',
                            subtitle: 'Chat with your travel group',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupChatScreen(tripId: tripId),
                              ),
                            ),
                          ),
                          _ActionRow(
                            icon: Icons.how_to_vote_rounded,
                            color: Color(0xFFFFB347),
                            title: 'Voting',
                            subtitle: 'Decide together on trip choices',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => VotingScreen(tripId: tripId),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: color, size: 21),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
