import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'locale_service.dart';
import 'profile_service.dart';
import 'supabase_config.dart';

/// The signed-in user's real activity counts, used to decide which
/// Achievements badges are earned — computed from actual Trip/Budget/
/// Community data (`trip_members`, `trips`, `expenses`, `posts`), never
/// hardcoded.
class AchievementStats {
  const AchievementStats({
    required this.tripCount,
    required this.distinctDestinations,
    required this.totalSpent,
    required this.maxGroupSize,
    required this.organizedTripCount,
    required this.maxTripDurationDays,
    required this.maxPlanningLeadDays,
    required this.postCount,
    required this.maxPostReactions,
    required this.maxPostComments,
    required this.mediaPostCount,
    required this.foodPostCount,
    required this.distinctPostCategories,
  });

  final int tripCount;
  final int distinctDestinations;

  /// Sum of `expenses.amount` across every expense the user has logged
  /// (any trip, any category) — what the Budget badges below track,
  /// rather than how many separate expense rows exist.
  final double totalSpent;
  final int maxGroupSize;
  final int organizedTripCount;
  final int maxTripDurationDays;
  final int maxPlanningLeadDays;
  final int postCount;
  final int maxPostReactions;
  final int maxPostComments;
  final int mediaPostCount;
  final int foodPostCount;
  final int distinctPostCategories;

  static const zero = AchievementStats(
    tripCount: 0,
    distinctDestinations: 0,
    totalSpent: 0,
    maxGroupSize: 1,
    organizedTripCount: 0,
    maxTripDurationDays: 0,
    maxPlanningLeadDays: 0,
    postCount: 0,
    maxPostReactions: 0,
    maxPostComments: 0,
    mediaPostCount: 0,
    foodPostCount: 0,
    distinctPostCategories: 0,
  );
}

/// Formats an RM amount the same way Budget does (`budget_planner_screen
/// .dart`'s `formatAmount`) — duplicated rather than imported, since a
/// service reaching into a screen file for a formatter would be a
/// backwards dependency. Shows decimals only when the amount actually
/// has cents.
String _formatAmount(double amount) {
  final rounded = double.parse(amount.toStringAsFixed(2));
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(2);
}

/// One entry on the Achievements grid. [id] is a stable key (never
/// translated, never renamed) used to persist "already notified about
/// this one" locally and to group badges into [category] — 'trip',
/// 'budget', or 'community' — for the category-completion title (see
/// [earnedCategoryKeys]). [description] is the static "what this badge
/// is for" text shown in the tap-to-view detail sheet; [progress] is the
/// live "here's what's left" hint shown both in the grid (while locked)
/// and in that same detail sheet.
class AchievementBadge {
  const AchievementBadge({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.category,
    this.isEarned,
    this.progress,
  });

  final String id;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final String category;
  final bool Function(AchievementStats stats)? isEarned;
  final String Function(AchievementStats stats)? progress;
}

List<AchievementBadge> achievementBadges() => [
  AchievementBadge(
    id: 'first_trip',
    label: tr('auth_badge_first_trip'),
    description: tr('auth_desc_first_trip'),
    icon: Icons.flight_takeoff_rounded,
    color: const Color(0xFFFF7A59),
    category: 'trip',
    isEarned: (s) => s.tripCount >= 1,
    progress: (s) => tr('auth_progress_create_first_trip'),
  ),
  AchievementBadge(
    id: 'planner_pro',
    label: tr('auth_badge_planner_pro'),
    description: tr('auth_desc_planner_pro'),
    icon: Icons.event_available_rounded,
    color: const Color(0xFF8E63CE),
    category: 'trip',
    isEarned: (s) => s.tripCount >= 3,
    progress: (s) =>
        '${s.tripCount.clamp(0, 3)}/3 ${tr('auth_trips_planned_suffix')}',
  ),
  AchievementBadge(
    id: '10_trips',
    label: tr('auth_badge_10_trips'),
    description: tr('auth_desc_10_trips'),
    icon: Icons.military_tech_rounded,
    color: const Color(0xFFFFB347),
    category: 'trip',
    isEarned: (s) => s.tripCount >= 10,
    progress: (s) =>
        '${s.tripCount.clamp(0, 10)}/10 ${tr('auth_trips_planned_suffix')}',
  ),
  AchievementBadge(
    id: 'globe_trotter',
    label: tr('auth_badge_globe_trotter'),
    description: tr('auth_desc_globe_trotter'),
    icon: Icons.public_rounded,
    color: const Color(0xFF5C6BC0),
    category: 'trip',
    isEarned: (s) => s.distinctDestinations >= 10,
    progress: (s) =>
        '${s.distinctDestinations.clamp(0, 10)}/10 ${tr('auth_destinations_suffix')}',
  ),
  AchievementBadge(
    id: 'group_leader',
    label: tr('auth_badge_group_leader'),
    description: tr('auth_desc_group_leader'),
    icon: Icons.emoji_events_rounded,
    color: const Color(0xFF8E63CE),
    category: 'trip',
    isEarned: (s) => s.organizedTripCount >= 3,
    progress: (s) =>
        '${s.organizedTripCount.clamp(0, 3)}/3 ${tr('auth_trips_organized_suffix')}',
  ),
  AchievementBadge(
    id: 'marathon_traveler',
    label: tr('auth_badge_marathon_traveler'),
    description: tr('auth_desc_marathon_traveler'),
    icon: Icons.timelapse_rounded,
    color: const Color(0xFFFF7A59),
    category: 'trip',
    isEarned: (s) => s.maxTripDurationDays >= 14,
    progress: (s) =>
        '${s.maxTripDurationDays.clamp(0, 14)}/14 ${tr('auth_days_suffix')}',
  ),
  AchievementBadge(
    id: 'early_bird',
    label: tr('auth_badge_early_bird'),
    description: tr('auth_desc_early_bird'),
    icon: Icons.alarm_rounded,
    color: const Color(0xFF5C6BC0),
    category: 'trip',
    isEarned: (s) => s.maxPlanningLeadDays >= 30,
    progress: (s) =>
        '${s.maxPlanningLeadDays.clamp(0, 30)}/30 ${tr('auth_days_ahead_suffix')}',
  ),
  AchievementBadge(
    id: 'first_expense',
    label: tr('auth_badge_first_expense'),
    description: tr('auth_desc_first_expense'),
    icon: Icons.receipt_long_rounded,
    color: const Color(0xFF11998E),
    category: 'budget',
    isEarned: (s) => s.totalSpent > 0,
    progress: (s) => tr('auth_progress_first_expense'),
  ),
  AchievementBadge(
    id: 'budget_master',
    label: tr('auth_badge_budget_master'),
    description: tr('auth_desc_budget_master'),
    icon: Icons.savings_rounded,
    color: const Color(0xFF11998E),
    category: 'budget',
    isEarned: (s) => s.totalSpent >= 1000,
    progress: (s) =>
        'RM ${_formatAmount(s.totalSpent.clamp(0, 1000))}/RM 1,000 ${tr('auth_spent_suffix')}',
  ),
  AchievementBadge(
    id: 'social_butterfly',
    label: tr('auth_badge_social_butterfly'),
    description: tr('auth_desc_social_butterfly'),
    icon: Icons.groups_rounded,
    color: const Color(0xFF38EF7D),
    category: 'trip',
    isEarned: (s) => s.maxGroupSize >= 2,
    progress: (s) => tr('auth_progress_group_2plus'),
  ),
  AchievementBadge(
    id: 'first_post',
    label: tr('auth_badge_first_post'),
    description: tr('auth_desc_first_post'),
    icon: Icons.edit_note_rounded,
    color: const Color(0xFF5C6BC0),
    category: 'community',
    isEarned: (s) => s.postCount >= 1,
    progress: (s) => tr('auth_progress_first_post'),
  ),
  AchievementBadge(
    id: 'storyteller',
    label: tr('auth_badge_storyteller'),
    description: tr('auth_desc_storyteller'),
    icon: Icons.auto_stories_rounded,
    color: const Color(0xFF8E63CE),
    category: 'community',
    isEarned: (s) => s.postCount >= 10,
    progress: (s) =>
        '${s.postCount.clamp(0, 10)}/10 ${tr('auth_posts_published_suffix')}',
  ),
  AchievementBadge(
    id: 'first_reaction',
    label: tr('auth_badge_first_reaction'),
    description: tr('auth_desc_first_reaction'),
    icon: Icons.favorite_rounded,
    color: const Color(0xFFFF7A59),
    category: 'community',
    isEarned: (s) => s.maxPostReactions >= 1,
    progress: (s) => tr('auth_progress_first_reaction'),
  ),
  AchievementBadge(
    id: 'crowd_favorite',
    label: tr('auth_badge_crowd_favorite'),
    description: tr('auth_desc_crowd_favorite'),
    icon: Icons.local_fire_department_rounded,
    color: const Color(0xFFFFB347),
    category: 'community',
    isEarned: (s) => s.maxPostReactions >= 20,
    progress: (s) =>
        '${s.maxPostReactions.clamp(0, 20)}/20 ${tr('auth_reactions_on_post_suffix')}',
  ),
  AchievementBadge(
    id: 'conversation_starter',
    label: tr('auth_badge_conversation_starter'),
    description: tr('auth_desc_conversation_starter'),
    icon: Icons.forum_rounded,
    color: const Color(0xFF38EF7D),
    category: 'community',
    isEarned: (s) => s.maxPostComments >= 10,
    progress: (s) =>
        '${s.maxPostComments.clamp(0, 10)}/10 ${tr('auth_comments_on_post_suffix')}',
  ),
  AchievementBadge(
    id: 'shutterbug',
    label: tr('auth_badge_shutterbug'),
    description: tr('auth_desc_shutterbug'),
    icon: Icons.photo_camera_rounded,
    color: const Color(0xFFFFB347),
    category: 'community',
    isEarned: (s) => s.mediaPostCount >= 5,
    progress: (s) =>
        '${s.mediaPostCount.clamp(0, 5)}/5 ${tr('auth_media_posts_suffix')}',
  ),
  AchievementBadge(
    id: 'explorer',
    label: tr('auth_badge_explorer'),
    description: tr('auth_desc_explorer'),
    icon: Icons.explore_rounded,
    color: const Color(0xFF5C6BC0),
    category: 'community',
    isEarned: (s) => s.distinctPostCategories >= 4,
    progress: (s) =>
        '${s.distinctPostCategories.clamp(0, 4)}/4 ${tr('auth_categories_explored_suffix')}',
  ),
  AchievementBadge(
    id: 'foodie',
    label: tr('auth_badge_foodie'),
    description: tr('auth_desc_foodie'),
    icon: Icons.restaurant_rounded,
    color: const Color(0xFF11998E),
    category: 'community',
    isEarned: (s) => s.foodPostCount >= 3,
    progress: (s) =>
        '${s.foodPostCount.clamp(0, 3)}/3 ${tr('auth_food_posts_suffix')}',
  ),
];

int earnedBadgeCount(AchievementStats stats) =>
    achievementBadges().where((b) => b.isEarned?.call(stats) ?? false).length;

/// The three achievement categories a user can 100%-complete, and the
/// title/icon/color shown for each once they have — see
/// [earnedCategoryKeys] and `AchievementService.syncCategoryBadges`.
class CategoryBadgeInfo {
  const CategoryBadgeInfo({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;
}

CategoryBadgeInfo categoryBadgeInfo(String category) => switch (category) {
  'trip' => CategoryBadgeInfo(
    title: tr('auth_category_title_trip'),
    icon: Icons.flight_rounded,
    color: const Color(0xFFFF7A59),
  ),
  'budget' => CategoryBadgeInfo(
    title: tr('auth_category_title_budget'),
    icon: Icons.savings_rounded,
    color: const Color(0xFF11998E),
  ),
  'community' => CategoryBadgeInfo(
    title: tr('auth_category_title_community'),
    icon: Icons.groups_rounded,
    color: const Color(0xFF8E63CE),
  ),
  _ => CategoryBadgeInfo(
    title: category,
    icon: Icons.star_rounded,
    color: Colors.grey,
  ),
};

/// Which categories ('trip', 'budget', 'community') [stats] has *every*
/// badge earned in — the set `AchievementService.syncCategoryBadges`
/// persists to `profiles.earned_category_badges`.
List<String> earnedCategoryKeys(AchievementStats stats) {
  final byCategory = <String, List<AchievementBadge>>{};
  for (final b in achievementBadges()) {
    byCategory.putIfAbsent(b.category, () => []).add(b);
  }
  return byCategory.entries
      .where((e) => e.value.every((b) => b.isEarned?.call(stats) ?? false))
      .map((e) => e.key)
      .toList();
}

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
        .select('trip_id, role')
        .eq('user_id', uid);
    final tripIds = (memberRows as List)
        .map((r) => r['trip_id'] as String)
        .toSet()
        .toList();
    final organizedTripCount = memberRows
        .where((r) => r['role'] == 'organizer')
        .length;

    var distinctDestinations = 0;
    var maxGroupSize = 1;
    var maxTripDurationDays = 0;
    var maxPlanningLeadDays = 0;

    // Trip-derived stats only make sense with at least one trip — skip the
    // three trip/member queries entirely rather than filtering on an empty
    // id list.
    if (tripIds.isNotEmpty) {
      final tripRows = await _client
          .from('trips')
          .select('destination, start_date, end_date, created_at')
          .inFilter('id', tripIds);
      final destinations = <String>{};
      for (final row in tripRows as List) {
        final destination = ((row['destination'] as String?) ?? '').trim();
        if (destination.isNotEmpty) destinations.add(destination);

        final startDate = row['start_date'] as String?;
        final endDate = row['end_date'] as String?;
        if (startDate == null || endDate == null) continue;
        final start = DateTime.parse(startDate);

        final duration = DateTime.parse(endDate).difference(start).inDays;
        if (duration > maxTripDurationDays) maxTripDurationDays = duration;

        final createdAt = DateTime.parse(row['created_at'] as String);
        final leadDays = start.difference(createdAt).inDays;
        if (leadDays > maxPlanningLeadDays) maxPlanningLeadDays = leadDays;
      }
      distinctDestinations = destinations.length;

      final memberCountRows = await _client
          .from('trip_members')
          .select('trip_id')
          .inFilter('trip_id', tripIds);
      final countByTrip = <String, int>{};
      for (final row in memberCountRows as List) {
        final id = row['trip_id'] as String;
        countByTrip[id] = (countByTrip[id] ?? 0) + 1;
      }
      if (countByTrip.values.isNotEmpty) {
        maxGroupSize = countByTrip.values.reduce((a, b) => a > b ? a : b);
      }
    }

    final expenseRows =
        await _client.from('expenses').select('amount').eq('user_id', uid)
            as List;
    final totalSpent = expenseRows.fold<double>(
      0,
      (sum, r) => sum + (r['amount'] as num).toDouble(),
    );

    final postRows =
        await _client
                .from('posts')
                .select('category, likes_count, comments_count, media_url')
                .eq('author_id', uid)
            as List;
    final foodPostCount = postRows.where((r) => r['category'] == 'Food').length;
    final mediaPostCount = postRows
        .where((r) => (r['media_url'] as String?)?.isNotEmpty ?? false)
        .length;
    final distinctPostCategories = postRows
        .map((r) => (r['category'] as String?) ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .length;
    final maxPostReactions = postRows.isEmpty
        ? 0
        : postRows
              .map((r) => (r['likes_count'] as int?) ?? 0)
              .reduce((a, b) => a > b ? a : b);
    final maxPostComments = postRows.isEmpty
        ? 0
        : postRows
              .map((r) => (r['comments_count'] as int?) ?? 0)
              .reduce((a, b) => a > b ? a : b);

    return AchievementStats(
      tripCount: tripIds.length,
      distinctDestinations: distinctDestinations,
      totalSpent: totalSpent,
      maxGroupSize: maxGroupSize,
      organizedTripCount: organizedTripCount,
      maxTripDurationDays: maxTripDurationDays,
      maxPlanningLeadDays: maxPlanningLeadDays,
      postCount: postRows.length,
      maxPostReactions: maxPostReactions,
      maxPostComments: maxPostComments,
      mediaPostCount: mediaPostCount,
      foodPostCount: foodPostCount,
      distinctPostCategories: distinctPostCategories,
    );
  }

  /// Writes [stats]'s fully-completed categories to the signed-in user's
  /// profile row (skipping the write if nothing changed since the last
  /// sync), so other viewers — who can't compute this themselves; see
  /// `0031_add_earned_category_badges.sql` — see it too.
  Future<void> syncCategoryBadges(AchievementStats stats) async {
    if (_client.auth.currentUser == null) return;
    final earned = earnedCategoryKeys(stats);
    final stored =
        ProfileService.instance.current.value?.earnedCategoryBadges ??
        const <String>[];
    if (earned.toSet().length == stored.toSet().length &&
        earned.toSet().containsAll(stored)) {
      return;
    }
    await ProfileService.instance.setEarnedCategoryBadges(earned);
  }

  /// Compares [stats]'s currently-earned badges against what this device
  /// last saw (in `SharedPreferences`, keyed by user id) and returns the
  /// ones newly earned since then — for `AchievementsScreen`/`ProfileTab`
  /// to pop a SnackBar for. Always updates the stored set as a side
  /// effect. The very first time this runs for an account, everything
  /// already earned is recorded as a baseline *without* being reported as
  /// "newly" earned — otherwise a long-time user's first load after this
  /// feature ships would get flooded with unlock toasts for things they
  /// achieved months ago.
  Future<List<AchievementBadge>> checkNewlyEarnedBadges(
    AchievementStats stats,
  ) async {
    final user = _client.auth.currentUser;
    if (user == null) return const [];

    final badges = achievementBadges();
    final earnedIds = badges
        .where((b) => b.isEarned?.call(stats) ?? false)
        .map((b) => b.id)
        .toSet();

    final prefs = await SharedPreferences.getInstance();
    final prefsKey = 'achievements_seen_${user.id}';
    final storedRaw = prefs.getStringList(prefsKey);

    if (storedRaw == null) {
      await prefs.setStringList(prefsKey, earnedIds.toList());
      return const [];
    }

    final stored = storedRaw.toSet();
    final newlyEarned = badges
        .where((b) => earnedIds.contains(b.id) && !stored.contains(b.id))
        .toList();
    if (newlyEarned.isNotEmpty) {
      await prefs.setStringList(prefsKey, earnedIds.toList());
    }
    return newlyEarned;
  }
}
