import 'package:flutter/material.dart';

import '../../models/community_post.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_ago.dart';
import '../explore/explore_tab.dart' show categories;

/// Cover-gradient options a post can be tagged with, keyed by the text
/// value stored in `posts.cover_gradient`. Shared by the feed,
/// [AddPostScreen]'s picker, and [PostCard].
const communityGradients = <String, List<Color>>{
  'horizon': AppColors.horizon,
  'dusk': AppColors.dusk,
  'sunset': AppColors.sunset,
  'lagoon': AppColors.lagoon,
};

List<Color> gradientFor(String key) =>
    communityGradients[key] ?? communityGradients['horizon']!;

IconData iconForCategory(String label) {
  for (final c in categories) {
    if (c.label == label) return c.icon;
  }
  return categories.first.icon;
}

/// One Community post card — author, place, caption, cover, and the
/// like/comment/share action row. Used by the feed (`CommunityTab`) and by
/// `PostDetailScreen` (the landing screen for a shared post link).
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onToggleLike,
    required this.onComment,
    required this.onShare,
  });

  final CommunityPost post;
  final VoidCallback onToggleLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final gradient = gradientFor(post.coverGradient);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Color(post.authorColor),
                child: Text(
                  post.authorName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.authorName,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      '${post.placeName} · ${timeAgo(post.createdAt)}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            post.caption,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: gradient),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Icon(
              iconForCategory(post.category),
              color: Colors.white.withValues(alpha: 0.9),
              size: 40,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _PostAction(
                icon: post.likedByMe
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                iconColor: post.likedByMe ? const Color(0xFFFF7A59) : null,
                label: '${post.likesCount}',
                onTap: onToggleLike,
              ),
              const SizedBox(width: 18),
              _PostAction(
                icon: Icons.mode_comment_outlined,
                label: '${post.commentsCount}',
                onTap: onComment,
              ),
              const Spacer(),
              GestureDetector(
                onTap: onShare,
                child: Icon(
                  Icons.share_outlined,
                  color: context.colors.muted,
                  size: 19,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: iconColor ?? context.colors.muted, size: 19),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
