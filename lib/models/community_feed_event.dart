/// A live change from `CommunityService.watchFeedActivity` — either a
/// signal that new posts exist upstream, or an update to a specific
/// already-loaded post's counts. The feed list itself stays server-paginated
/// (`CommunityService.fetchFeedPage`); these events only ever patch a post
/// already on screen or prompt a manual refresh, never splice/reorder rows
/// on their own (which would shift already-loaded pages' offsets).
sealed class CommunityFeedEvent {
  const CommunityFeedEvent();
}

/// Someone else published a new post. `CommunityTab` surfaces this as a
/// dismiss-by-refresh banner rather than acting on it automatically.
class NewPostAvailable extends CommunityFeedEvent {
  const NewPostAvailable();
}

/// A post's reaction counts changed — mirrors `posts.reaction_counts`/
/// `likes_count`, which a database trigger keeps in sync with `post_likes`.
class PostReactionsChanged extends CommunityFeedEvent {
  const PostReactionsChanged({
    required this.postId,
    required this.reactionCounts,
    required this.likesCount,
  });

  final String postId;
  final Map<String, int> reactionCounts;
  final int likesCount;
}

/// A comment was added to (`delta: 1`) or removed from (`delta: -1`) a post.
class PostCommentCountChanged extends CommunityFeedEvent {
  const PostCommentCountChanged({required this.postId, required this.delta});

  final String postId;
  final int delta;
}
