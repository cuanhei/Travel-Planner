import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Badges and milestones grid, some earned and some still locked.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key});

  static List<({String label, IconData icon, bool earned, Color color})>
  _badges(BuildContext context) => [
    (
      label: 'First Trip',
      icon: Icons.flight_takeoff_rounded,
      earned: true,
      color: Color(0xFFFF7A59),
    ),
    (
      label: 'Explorer',
      icon: Icons.explore_rounded,
      earned: true,
      color: Color(0xFF5C6BC0),
    ),
    (
      label: 'Foodie',
      icon: Icons.restaurant_rounded,
      earned: true,
      color: Color(0xFF11998E),
    ),
    (
      label: 'Reviewer',
      icon: Icons.rate_review_rounded,
      earned: true,
      color: Color(0xFFFFB347),
    ),
    (
      label: 'Planner Pro',
      icon: Icons.event_available_rounded,
      earned: true,
      color: Color(0xFF8E63CE),
    ),
    (
      label: 'Social Butterfly',
      icon: Icons.groups_rounded,
      earned: true,
      color: Color(0xFF38EF7D),
    ),
    (
      label: 'Globe Trotter',
      icon: Icons.public_rounded,
      earned: false,
      color: context.colors.muted,
    ),
    (
      label: 'Budget Master',
      icon: Icons.savings_rounded,
      earned: false,
      color: context.colors.muted,
    ),
    (
      label: '10 Trips',
      icon: Icons.military_tech_rounded,
      earned: false,
      color: context.colors.muted,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final badges = _badges(context);
    final earnedCount = badges.where((b) => b.earned).length;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Achievements',
              subtitle: '$earnedCount of ${badges.length} badges earned',
            ),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                itemCount: badges.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.85,
                ),
                itemBuilder: (context, index) {
                  final b = badges[index];
                  return Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: b.color.withValues(
                              alpha: b.earned ? 0.15 : 0.08,
                            ),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            b.earned ? b.icon : Icons.lock_outline_rounded,
                            color: b.earned ? b.color : context.colors.muted,
                            size: 22,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          b.label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: b.earned
                                ? context.colors.ink
                                : context.colors.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
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
