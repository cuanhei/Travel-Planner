import 'package:flutter/material.dart';

import '../../services/achievement_service.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/category_badge_chip.dart';
import '../../widgets/list_tile_card.dart';
import '../../widgets/user_avatar.dart';
import '../saved/saved_places_screen.dart';
import '../welcome_screen.dart';
import 'achievements_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'travel_history_screen.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  late Future<AchievementStats> _stats;

  @override
  void initState() {
    super.initState();
    _stats = AchievementService().loadStats();
    _stats.then(_onStatsLoaded);
  }

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
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
        children: [
          ValueListenableBuilder<UserProfile?>(
            valueListenable: ProfileService.instance.current,
            builder: (context, profile, _) {
              final name = profile?.fullName.isNotEmpty ?? false
                  ? profile!.fullName
                  : AuthService.instance.currentUserName;
              final email = profile?.email.isNotEmpty ?? false
                  ? profile!.email
                  : (AuthService.instance.currentUser?.email ?? '');
              return Row(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      ),
                      child: UserAvatar(
                        name: name,
                        avatarUrl: profile?.avatarUrl,
                        size: 64,
                        borderWidth: 3,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              name,
                              style: TextStyle(
                                color: context.colors.ink,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            CategoryBadgeRow(
                              categories:
                                  profile?.earnedCategoryBadges ?? const [],
                            ),
                          ],
                        ),
                        SizedBox(height: 3),
                        Text(
                          email,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute(builder: (_) => SettingsScreen())),
                    icon: Icon(
                      Icons.settings_outlined,
                      color: context.colors.ink,
                    ),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: 24),
          FutureBuilder<AchievementStats>(
            future: _stats,
            builder: (context, snapshot) {
              final stats = snapshot.data ?? AchievementStats.zero;
              return Row(
                children: [
                  _StatTile(
                    label: tr('auth_trips'),
                    value: '${stats.tripCount}',
                  ),
                  _StatTile(label: tr('auth_reviews'), value: '0'),
                  _StatTile(
                    label: tr('auth_badges'),
                    value: '${earnedBadgeCount(stats)}',
                  ),
                ],
              );
            },
          ),
          SizedBox(height: 28),
          ListTileCard(
            icon: Icons.history_rounded,
            title: tr('auth_travel_history'),
            subtitle: 'Past trips and stats',
            iconColor: Color(0xFF5C6BC0),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => TravelHistoryScreen())),
          ),
          ListTileCard(
            icon: Icons.emoji_events_rounded,
            title: tr('auth_achievements'),
            subtitle: 'Badges and milestones',
            iconColor: Color(0xFFFFB347),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => AchievementsScreen())),
          ),
          ListTileCard(
            icon: Icons.bookmark_rounded,
            title: tr('auth_saved_places'),
            subtitle: 'Your bookmarked spots',
            iconColor: AppColors.accent,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SavedPlacesScreen())),
          ),
          ListTileCard(
            icon: Icons.settings_outlined,
            title: tr('auth_settings_title'),
            subtitle: 'Preferences, notifications, language',
            iconColor: context.colors.ink,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SettingsScreen())),
          ),
          SizedBox(height: 8),
          ListTileCard(
            icon: Icons.logout_rounded,
            title: tr('auth_sign_out'),
            iconColor: Colors.redAccent,
            margin: EdgeInsets.zero,
            trailing: SizedBox.shrink(),
            onTap: () async {
              await AuthService.instance.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => WelcomeScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: EdgeInsets.only(right: 10),
        padding: EdgeInsets.symmetric(vertical: 14),
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
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: context.colors.muted, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}
