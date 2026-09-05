/// One photo/video attached to a post — [url] its Storage URL, [type]
/// either 'image' or 'video'.
typedef PostMedia = ({String url, String type});

/// A single Community feed post, joined from `posts` + `profiles` (author)
/// and `post_likes` (the current user's own reaction, if any).
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorColor,
    this.authorAvatarUrl,
    required this.placeName,
    required this.caption,
    required this.category,
    required this.coverGradient,
    this.media = const [],
    required this.likesCount,
    required this.reactionCounts,
    required this.commentsCount,
    required this.myReaction,
    required this.createdAt,
    this.ipAddress,
    required this.authorLocationSharingEnabled,
    required this.updatedAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final int authorColor;
  final String? authorAvatarUrl;

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

  /// Up to 3 photos/videos, in the order they were attached.
  final List<PostMedia> media;

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
  final DateTime updatedAt;

  /// Whether the post's own author has changed it since posting — driven by
  /// `posts.updated_at`, which only moves on a content edit (place/caption/
  /// category/media), never on a reaction or comment. A tolerance guards
  /// against `created_at`/`updated_at` differing by a few stray
  /// microseconds from being computed as two separate `now()` calls on
  /// insert, which would otherwise show a brand-new post as "Edited".
  bool get isEdited =>
      updatedAt.difference(createdAt) > const Duration(seconds: 2);

  /// Used for optimistic/live local updates (a reaction tap, or a
  /// `CommunityFeedEvent` patching in a change from elsewhere) instead of
  /// re-fetching the post from the paginated feed.
  ///
  /// [myReaction] needs to distinguish "leave it alone" from "set it to
  /// null" (clearing your own reaction is a real, common case) — a plain
  /// nullable parameter can't tell those apart, so omitting it keeps the
  /// current value and [clearMyReaction] is how a caller explicitly nulls
  /// it out.
  CommunityPost copyWith({
    int? likesCount,
    Map<String, int>? reactionCounts,
    int? commentsCount,
    String? myReaction,
    bool clearMyReaction = false,
  }) {
    return CommunityPost(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorColor: authorColor,
      authorAvatarUrl: authorAvatarUrl,
      placeName: placeName,
      caption: caption,
      category: category,
      coverGradient: coverGradient,
      media: media,
      likesCount: likesCount ?? this.likesCount,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      commentsCount: commentsCount ?? this.commentsCount,
      myReaction: clearMyReaction ? null : (myReaction ?? this.myReaction),
      createdAt: createdAt,
      ipAddress: ipAddress,
      authorLocationSharingEnabled: authorLocationSharingEnabled,
      updatedAt: updatedAt,
    );
  }

  factory CommunityPost.fromMap(
    Map<String, dynamic> map, {
    required String? myReaction,
  }) {
    final profile = map['profiles'] as Map<String, dynamic>;
    final rawCounts = map['reaction_counts'] as Map<String, dynamic>? ?? const {};
    final mediaUrls = (map['media_urls'] as List<dynamic>?)?.cast<String>();
    final mediaTypes = (map['media_types'] as List<dynamic>?)?.cast<String>();
    // Falls back to the legacy single media_url/media_type columns for a
    // row that predates the media_urls/media_types arrays and was never
    // backfilled (see migration 0027_post_multi_media.sql).
    final legacyUrl = map['media_url'] as String?;
    final media = mediaUrls != null
        ? [
            for (var i = 0; i < mediaUrls.length; i++)
              (
                url: mediaUrls[i],
                type: i < (mediaTypes?.length ?? 0) ? mediaTypes![i] : 'image',
              ),
          ]
        : legacyUrl != null
        ? [(url: legacyUrl, type: map['media_type'] as String? ?? 'image')]
        : const <PostMedia>[];
    return CommunityPost(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorName: profile['display_name'] as String,
      authorColor: profile['avatar_color'] as int,
      authorAvatarUrl: profile['avatar_url'] as String?,
      placeName: map['place_name'] as String,
      caption: map['caption'] as String,
      category: map['category'] as String,
      coverGradient: map['cover_gradient'] as String,
      media: media,
      likesCount: map['likes_count'] as int,
      reactionCounts: rawCounts.map((k, v) => MapEntry(k, v as int)),
      commentsCount: map['comments_count'] as int,
      myReaction: myReaction,
      createdAt: DateTime.parse(map['created_at'] as String),
      ipAddress: map['ip_address'] as String?,
      authorLocationSharingEnabled:
          (profile['location_sharing_enabled'] as bool?) ?? true,
      updatedAt: DateTime.parse(
        map['updated_at'] as String? ?? map['created_at'] as String,
      ),
    );
  }
}
