import 'package:flutter/material.dart';

import '../../services/achievement_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Badges and milestones — all locked by default, unlocked live from the
/// signed-in user's real Trip/Budget/Group/Community activity (see
/// `achievement_service.dart`).
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
    _stats.then(_onStatsLoaded);
  }

  /// Same unlock bookkeeping as `ProfileTab._onStatsLoaded` — duplicated
  /// (rather than only living on the Profile tab) so opening this screen
  /// directly still surfaces an unlock, and so whichever screen the user
  /// visits first is the one that gets to show it (the other's
  /// `checkNewlyEarnedBadges` call sees it's already been recorded and
  /// stays quiet).
  Future<void> _onStatsLoaded(AchievementStats stats) async {
    final service = AchievementService();
    await service.syncCategoryBadges(stats);
    final newlyEarned = await service.checkNewlyEarnedBadges(stats);
    if (!mounted || newlyEarned.isEmpty) return;
    for (final badge in newlyEarned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${tr('auth_achievement_unlocked_prefix')} ${badge.label}',
          ),
        ),
      );
    }
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
                      return _BadgeTile(
                        badge: b,
                        earned: earned,
                        hint: hint,
                        onTap: () => _showBadgeDetail(context, b, earned, hint),
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

  void _showBadgeDetail(
    BuildContext context,
    AchievementBadge badge,
    bool earned,
    String? hint,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color:
                            (earned ? badge.color : sheetContext.colors.muted)
                                .withValues(alpha: earned ? 0.15 : 0.08),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        earned ? badge.icon : Icons.lock_outline_rounded,
                        color: earned ? badge.color : sheetContext.colors.muted,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            badge.label,
                            style: TextStyle(
                              color: sheetContext.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr(
                              earned
                                  ? 'auth_badge_earned_label'
                                  : 'auth_badge_locked_label',
                            ),
                            style: TextStyle(
                              color: earned
                                  ? badge.color
                                  : sheetContext.colors.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  badge.description,
                  style: TextStyle(
                    color: sheetContext.colors.ink.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                if (!earned && hint != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    tr('auth_badge_to_unlock_label'),
                    style: TextStyle(
                      color: sheetContext.colors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    style: TextStyle(
                      color: sheetContext.colors.ink.withValues(alpha: 0.85),
                      fontSize: 14,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BadgeTile extends StatelessWidget {
  const _BadgeTile({
    required this.badge,
    required this.earned,
    required this.onTap,
    this.hint,
  });

  final AchievementBadge badge;
  final bool earned;
  final String? hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
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
                  color: (earned ? badge.color : context.colors.muted)
                      .withValues(alpha: earned ? 0.15 : 0.08),
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
        ),
      ),
    );
  }
}
