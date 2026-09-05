sealed class CommunityFeedEvent {
  const CommunityFeedEvent();
}

class NewPostAvailable extends CommunityFeedEvent {
  const NewPostAvailable();
}

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

class PostCommentCountChanged extends CommunityFeedEvent {
  const PostCommentCountChanged({required this.postId, required this.delta});

  final String postId;
  final int delta;
}
