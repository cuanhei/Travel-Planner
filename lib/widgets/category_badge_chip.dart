import 'package:flutter/material.dart';

import '../services/achievement_service.dart';

/// One small colored pill for a fully-completed Achievement category
/// (e.g. "Trailblazer" for 100% of the Trip badges) — see
/// `AchievementService.syncCategoryBadges` for how a profile earns these
/// and [CategoryBadgeRow] for the usual way to render a whole set.
class CategoryBadgeChip extends StatelessWidget {
  const CategoryBadgeChip({super.key, required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    final info = categoryBadgeInfo(category);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: info.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(info.icon, size: 11, color: info.color),
          const SizedBox(width: 4),
          Text(
            info.title,
            style: TextStyle(
              color: info.color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a [CategoryBadgeChip] for each category in [categories] — the
/// usual way [UserProfile.earnedCategoryBadges] gets shown beside a
/// name. Renders nothing (not even a `SizedBox`) when [categories] is
/// empty, so callers can drop this in unconditionally.
class CategoryBadgeRow extends StatelessWidget {
  const CategoryBadgeRow({super.key, required this.categories});

  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final category in categories)
          CategoryBadgeChip(category: category),
      ],
    );
  }
}
