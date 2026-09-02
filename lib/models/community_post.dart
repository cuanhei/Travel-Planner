/// A single Community feed post, joined from `posts` + `profiles` (author)
/// and `post_likes` (whether the current user liked it).
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
    required this.likesCount,
    required this.commentsCount,
    required this.likedByMe,
    required this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final int authorColor;
  final String placeName;
  final String caption;
  final String category;
  final String coverGradient;
  final int likesCount;
  final int commentsCount;
  final bool likedByMe;
  final DateTime createdAt;

  factory CommunityPost.fromMap(
    Map<String, dynamic> map, {
    required bool likedByMe,
  }) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return CommunityPost(
      id: map['id'] as String,
      authorId: map['author_id'] as String,
      authorName: profile['display_name'] as String,
      authorColor: profile['avatar_color'] as int,
      placeName: map['place_name'] as String,
      caption: map['caption'] as String,
      category: map['category'] as String,
      coverGradient: map['cover_gradient'] as String,
      likesCount: map['likes_count'] as int,
      commentsCount: map['comments_count'] as int,
      likedByMe: likedByMe,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
