/// A single Community feed post, joined from `posts` + `profiles` (author)
/// and `post_likes` (the current user's own reaction, if any).
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorColor,
    required this.placeName,
    required this.caption,
    required this.category,
    required this.coverGradient,
    this.mediaUrl,
    this.mediaType,
    required this.likesCount,
    required this.reactionCounts,
    required this.commentsCount,
    required this.myReaction,
    required this.createdAt,
    this.ipAddress,
    required this.authorLocationSharingEnabled,
  });

  final String id;
  final String authorId;
  final String authorName;
  final int authorColor;

  /// The `posts.ip_address` column — named for what it held originally,
  /// but resolved to a short area name (e.g. "George Town") from the
  /// poster's real GPS position at post time (`PostLocationService`, via
  /// `CommunityService.addPost`), not a raw IP. `null` if that lookup
  /// failed (no permission, GPS off, etc). Whether `PostCard` actually
  /// shows this or "Unknown" is gated by [authorLocationSharingEnabled],
  /// not by this being null.
  final String? ipAddress;

  /// The author's Settings → Privacy & Security → "Location Sharing"
  /// value *as of when this post was hydrated* — for the current user's
  /// own posts, `PostCard` prefers the live value from
  /// `ProfileService.instance.current` instead, so toggling the setting
  /// updates already-visible posts immediately without needing a fresh
  /// fetch; this hydrated value is what other authors' posts fall back
  /// to.
  final bool authorLocationSharingEnabled;
  final String placeName;
  final String caption;
  final String category;
  final String coverGradient;
  final String? mediaUrl;
  final String? mediaType;

  /// Total reactions across all types (`sum(reactionCounts.values)`).
  final int likesCount;

  /// Per-type breakdown, e.g. `{'like': 3, 'love': 1}` — only types with a
  /// count > 0 are present.
  final Map<String, int> reactionCounts;
  final int commentsCount;

  /// The current user's own reaction on this post ('like'/'love'/'wow'),
  /// or `null` if they haven't reacted.
  final String? myReaction;
  final DateTime createdAt;

  factory CommunityPost.fromMap(
    Map<String, dynamic> map, {
    required String? myReaction,
  }) {
    final profile = map['profiles'] as Map<String, dynamic>;
    final rawCounts =
        map['reaction_counts'] as Map<String, dynamic>? ?? const {};
    return CommunityPost(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorName: profile['display_name'] as String,
      authorColor: profile['avatar_color'] as int,
      placeName: map['place_name'] as String,
      caption: map['caption'] as String,
      category: map['category'] as String,
      coverGradient: map['cover_gradient'] as String,
      mediaUrl: map['media_url'] as String?,
      mediaType: map['media_type'] as String?,
      likesCount: map['likes_count'] as int,
      reactionCounts: rawCounts.map((k, v) => MapEntry(k, v as int)),
      commentsCount: map['comments_count'] as int,
      myReaction: myReaction,
      createdAt: DateTime.parse(map['created_at'] as String),
      ipAddress: map['ip_address'] as String?,
      authorLocationSharingEnabled:
          (profile['location_sharing_enabled'] as bool?) ?? true,
    );
  }
}
