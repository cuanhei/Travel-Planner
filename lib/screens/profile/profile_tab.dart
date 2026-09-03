import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/list_tile_card.dart';
import '../saved/saved_places_screen.dart';
import '../saved/saved_trips_screen.dart';
import '../welcome_screen.dart';
import 'achievements_screen.dart';
import 'settings_screen.dart';
import 'travel_history_screen.dart';

/// "Profile" bottom-nav tab: identity header, stats, and a menu into the
/// rest of the profile-related modules. The identity header (name,
/// email, avatar) reads the signed-in user's real `profiles` row; the
/// stats below it are still mock data pending other modules' backends.
class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FutureBuilder<Profile?>(
        future: ProfileService().getCurrentProfile(),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final name = profile?.name ?? 'Traveler';
          final email = profile?.email ?? '';
          final avatarColor = profile?.avatarColor;

          return ListView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: avatarColor == null
                          ? LinearGradient(
                              colors: AppColors.sunset,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: avatarColor == null ? null : Color(avatarColor),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.12),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
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
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => SettingsScreen()),
                    ),
                    icon: Icon(
                      Icons.settings_outlined,
                      color: context.colors.ink,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),
          Row(
            children: [
              _StatTile(label: 'Trips', value: '5'),
              _StatTile(label: 'Countries', value: '3'),
              _StatTile(label: 'Reviews', value: '12'),
              _StatTile(label: 'Badges', value: '6'),
            ],
          ),
          SizedBox(height: 28),
          ListTileCard(
            icon: Icons.history_rounded,
            title: 'Travel History',
            subtitle: 'Past trips and stats',
            iconColor: Color(0xFF5C6BC0),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => TravelHistoryScreen())),
          ),
          ListTileCard(
            icon: Icons.emoji_events_rounded,
            title: 'Achievements',
            subtitle: 'Badges and milestones',
            iconColor: Color(0xFFFFB347),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => AchievementsScreen())),
          ),
          ListTileCard(
            icon: Icons.bookmark_rounded,
            title: 'Saved Places',
            subtitle: 'Your bookmarked spots',
            iconColor: AppColors.accent,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SavedPlacesScreen())),
          ),
          ListTileCard(
            icon: Icons.map_rounded,
            title: 'Saved Trips',
            subtitle: 'Bookmarked itineraries',
            iconColor: Color(0xFF11998E),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SavedTripsScreen())),
          ),
          ListTileCard(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Preferences, notifications, language',
            iconColor: context.colors.ink,
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SettingsScreen())),
          ),
          SizedBox(height: 8),
          ListTileCard(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            iconColor: Colors.redAccent,
            margin: EdgeInsets.zero,
            trailing: SizedBox.shrink(),
            onTap: () async {
              await AuthService.instance.signOut();
              TripService.resetCache();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => WelcomeScreen()),
                (route) => false,
              );
            },
          ),
            ],
          );
        },
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
