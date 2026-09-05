import 'package:flutter/material.dart';

import '../../services/achievement_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  late Future<AchievementStats> _stats;

  @override
  void initState() {
    super.initState();
    _stats = AchievementService().loadStats();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            FutureBuilder<AchievementStats>(
              future: _stats,
              builder: (context, snapshot) {
                final stats = snapshot.data ?? AchievementStats.zero;
                final earnedCount = earnedBadgeCount(stats);
                return DetailHeader(
                  title: tr('auth_achievements'),
                  subtitle:
                      '$earnedCount ${tr('auth_of_word')} ${achievementBadges().length} ${tr('auth_badges_earned_suffix')}',
                );
              },
            ),
            Expanded(
              child: FutureBuilder<AchievementStats>(
                future: _stats,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final stats = snapshot.data ?? AchievementStats.zero;
                  final badges = achievementBadges();
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: badges.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.78,
                    ),
                    itemBuilder: (context, index) {
                      final b = badges[index];
                      final earned = b.isEarned?.call(stats) ?? false;
                      final hint = earned
                          ? null
                          : (b.progress?.call(stats) ??
                                tr('common_coming_soon'));
                      return _BadgeTile(badge: b, earned: earned, hint: hint);
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

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({required this.badge, required this.earned, this.hint});

  final AchievementBadge badge;
  final bool earned;
  final String? hint;

  @override
  Widget build(BuildContext context) {
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
              color: (earned ? badge.color : context.colors.muted).withValues(
                alpha: earned ? 0.15 : 0.08,
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              earned ? badge.icon : Icons.lock_outline_rounded,
              color: earned ? badge.color : context.colors.muted,
              size: 22,
            ),
          ),
          SizedBox(height: 10),
          Text(
            badge.label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: earned ? context.colors.ink : context.colors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
          if (hint != null) ...[
            SizedBox(height: 3),
            Text(
              hint!,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.muted.withValues(alpha: 0.8),
                fontSize: 9,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
