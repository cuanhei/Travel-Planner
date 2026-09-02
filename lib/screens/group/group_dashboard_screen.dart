import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'group_chat_screen.dart';
import 'invite_member_screen.dart';
import 'voting_screen.dart';

/// Group trip hub: members list and links to shared itinerary, chat,
/// and voting.
class GroupDashboardScreen extends StatelessWidget {
  const GroupDashboardScreen({super.key});

  // A getter, not `static final` — `tr()` must re-evaluate on every build,
  // and a `static final` initializer only runs once per app session.
  List<({String name, Color color, String role})> get _members => [
    (name: 'Alex Tan', color: AppColors.accent, role: tr('group_role_organizer')),
    (name: 'Mei Ling', color: Color(0xFF5C6BC0), role: tr('group_role_member')),
    (name: 'Arif Hakim', color: Color(0xFF11998E), role: tr('group_role_member')),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('group_dashboard_title'),
              subtitle: tr('group_dashboard_subtitle'),
              trailing: IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const InviteMemberScreen(tripName: 'Penang Adventure'),
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
                    tr('group_members_header'),
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 14),
                  ..._members.map(
                    (m) => Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.ink.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: m.color,
                            child: Text(
                              m.name[0],
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.name,
                                  style: TextStyle(
                                    color: context.colors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                Text(
                                  m.role,
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
                  // _ActionRow(
                  //   icon: Icons.map_rounded,
                  //   color: Color(0xFF5C6BC0),
                  //   title: 'Shared Itinerary',
                  //   subtitle: 'Plan together in real time',
                  //   onTap: () => Navigator.of(context).push(
                  //     MaterialPageRoute(
                  //       builder: (_) => SharedItineraryScreen(),
                  //     ),
                  //   ),
                  // ),
                  _ActionRow(
                    icon: Icons.chat_bubble_rounded,
                    color: AppColors.accent,
                    title: tr('group_action_chat_title'),
                    subtitle: tr('group_action_chat_subtitle'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => GroupChatScreen()),
                    ),
                  ),
                  _ActionRow(
                    icon: Icons.how_to_vote_rounded,
                    color: Color(0xFFFFB347),
                    title: tr('group_action_voting_title'),
                    subtitle: tr('group_action_voting_subtitle'),
                    onTap: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => VotingScreen())),
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
