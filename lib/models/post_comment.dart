/// A single comment on a Community post, joined from `comments` +
/// `profiles`. [parentCommentId] is `null` for a top-level comment, or the
/// id of the comment it's a reply to.
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.authorColor,
    required this.body,
    required this.createdAt,
    this.parentCommentId,
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final int authorColor;
  final String body;
  final DateTime createdAt;
  final String? parentCommentId;

  factory PostComment.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return PostComment(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      authorId: map['author_id'] as String,
      authorName: profile['display_name'] as String,
      authorColor: profile['avatar_color'] as int,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      parentCommentId: map['parent_comment_id'] as String?,
    );
  }
}
