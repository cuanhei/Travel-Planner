import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'locale_service.dart';
import 'supabase_config.dart';

/// The signed-in user's real activity counts, used to decide which
/// Achievements badges are earned — computed from actual Trip/Budget/
/// Group data (`trip_members`, `trips`, `expenses`), never hardcoded.
class AchievementStats {
  const AchievementStats({
    required this.tripCount,
    required this.distinctDestinations,
    required this.expenseCount,
    required this.maxGroupSize,
  });

  final int tripCount;
  final int distinctDestinations;
  final int expenseCount;
  final int maxGroupSize;

  static const zero = AchievementStats(
    tripCount: 0,
    distinctDestinations: 0,
    expenseCount: 0,
    maxGroupSize: 1,
  );
}

/// One entry on the Achievements grid. A null [isEarned] means there's no
/// backing data anywhere in the app to track it yet, so it always shows
/// locked (see `achievements_screen.dart`).
class AchievementBadge {
  const AchievementBadge({
    required this.label,
    required this.icon,
    required this.color,
    this.isEarned,
    this.progress,
  });

  final String label;
  final IconData icon;
  final Color color;
  final bool Function(AchievementStats stats)? isEarned;
  final String Function(AchievementStats stats)? progress;
}

/// Every badge shown on the Achievements screen and counted in the
/// Profile tab's "badges" stat — the single source of truth for both.
List<AchievementBadge> achievementBadges() => [
  AchievementBadge(
    label: tr('auth_badge_first_trip'),
    icon: Icons.flight_takeoff_rounded,
    color: const Color(0xFFFF7A59),
    isEarned: (s) => s.tripCount >= 1,
    progress: (s) => tr('auth_progress_create_first_trip'),
  ),
  AchievementBadge(
    label: tr('auth_badge_planner_pro'),
    icon: Icons.event_available_rounded,
    color: const Color(0xFF8E63CE),
    isEarned: (s) => s.tripCount >= 3,
    progress: (s) => '${s.tripCount.clamp(0, 3)}/3 ${tr('auth_trips_planned_suffix')}',
  ),
  AchievementBadge(
    label: tr('auth_badge_10_trips'),
    icon: Icons.military_tech_rounded,
    color: const Color(0xFFFFB347),
    isEarned: (s) => s.tripCount >= 10,
    progress: (s) => '${s.tripCount.clamp(0, 10)}/10 ${tr('auth_trips_planned_suffix')}',
  ),
  AchievementBadge(
    label: tr('auth_badge_globe_trotter'),
    icon: Icons.public_rounded,
    color: const Color(0xFF5C6BC0),
    isEarned: (s) => s.distinctDestinations >= 3,
    progress: (s) => '${s.distinctDestinations.clamp(0, 3)}/3 ${tr('auth_destinations_suffix')}',
  ),
  AchievementBadge(
    label: tr('auth_badge_budget_master'),
    icon: Icons.savings_rounded,
    color: const Color(0xFF11998E),
    isEarned: (s) => s.expenseCount >= 5,
    progress: (s) => '${s.expenseCount.clamp(0, 5)}/5 ${tr('auth_expenses_logged_suffix')}',
  ),
  AchievementBadge(
    label: tr('auth_badge_social_butterfly'),
    icon: Icons.groups_rounded,
    color: const Color(0xFF38EF7D),
    isEarned: (s) => s.maxGroupSize >= 2,
    progress: (s) => tr('auth_progress_group_2plus'),
  ),
  AchievementBadge(
    label: tr('auth_badge_explorer'),
    icon: Icons.explore_rounded,
    color: const Color(0xFF5C6BC0),
  ),
  AchievementBadge(
    label: tr('auth_badge_foodie'),
    icon: Icons.restaurant_rounded,
    color: const Color(0xFF11998E),
  ),
  AchievementBadge(
    label: tr('auth_badge_reviewer'),
    icon: Icons.rate_review_rounded,
    color: const Color(0xFFFFB347),
  ),
];

int earnedBadgeCount(AchievementStats stats) =>
    achievementBadges().where((b) => b.isEarned?.call(stats) ?? false).length;

class AchievementService {
  AchievementService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Future<AchievementStats> loadStats() async {
    final user = _client.auth.currentUser;
    if (user == null) return AchievementStats.zero;
    final uid = user.id;

    final memberRows = await _client
        .from('trip_members')
        .select('trip_id')
        .eq('user_id', uid);
    final tripIds = (memberRows as List)
        .map((r) => r['trip_id'] as String)
        .toSet()
        .toList();

    if (tripIds.isEmpty) return AchievementStats.zero;

    final tripRows = await _client
        .from('trips')
        .select('destination')
        .inFilter('id', tripIds);
    final destinations = (tripRows as List)
        .map((r) => ((r['destination'] as String?) ?? '').trim())
        .where((d) => d.isNotEmpty)
        .toSet();

    final memberCountRows = await _client
        .from('trip_members')
        .select('trip_id')
        .inFilter('trip_id', tripIds);
    final countByTrip = <String, int>{};
    for (final row in memberCountRows as List) {
      final id = row['trip_id'] as String;
      countByTrip[id] = (countByTrip[id] ?? 0) + 1;
    }
    final maxGroupSize = countByTrip.values.isEmpty
        ? 1
        : countByTrip.values.reduce((a, b) => a > b ? a : b);

    final expenseRows = await _client
        .from('expenses')
        .select('id')
        .eq('user_id', uid);

    return AchievementStats(
      tripCount: tripIds.length,
      distinctDestinations: destinations.length,
      expenseCount: (expenseRows as List).length,
      maxGroupSize: maxGroupSize,
    );
  }
}
