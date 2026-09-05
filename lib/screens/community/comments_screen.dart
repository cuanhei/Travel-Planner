import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/post_comment.dart';
import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_ago.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/user_avatar.dart';

/// Live comment thread on a community post, backed by `comments`.
class CommentsScreen extends StatelessWidget {
  const CommentsScreen({super.key, required this.postId, required this.place});

  final String postId;
  final String place;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Comments', subtitle: place),
            Expanded(child: CommentsSection(postId: postId)),
          ],
        ),
      ),
    );
  }
}

/// The comment list + composer for one post — every comment shown here is
/// scoped to [postId] only (`comments.post_id = postId`), so a
/// post's comments never leak into another post's thread. Replies are
/// nested one level under their top-level comment (see
/// [_replyTargetRootId]).
class CommentsSection extends StatefulWidget {
  const CommentsSection({super.key, required this.postId});

  final String postId;

  @override
  State<CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<CommentsSection> {
  final _service = CommunityService();
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  /// Subscribed once for the lifetime of this screen — calling
  /// [CommunityService.watchComments] fresh on every `build()` would tear
  /// down and re-create the Realtime subscription (and its initial fetch)
  /// on every rebuild. [_post] dismisses the keyboard right after posting,
  /// which changes layout and triggers exactly such a rebuild, so a comment
  /// submitted right then could briefly show twice — once from the old
  /// subscription's tail end, once from the new one's fresh fetch.
  late final Stream<List<PostComment>> _commentsStream = _service.watchComments(
    widget.postId,
  );

  /// The comment the composer is currently replying to, or `null` for a
  /// plain top-level comment. Shown as a dismissible chip above the text
  /// field.
  PostComment? _replyTarget;

  /// Root comment ids whose replies are currently expanded — replies are
  /// collapsed by default (just a "View N replies" toggle) and stay
  /// expanded once opened until the traveler taps "Hide replies" again.
  final Set<String> _expandedThreads = {};

  void _toggleThread(String rootId) {
    setState(() {
      if (!_expandedThreads.remove(rootId)) _expandedThreads.add(rootId);
    });
  }

  /// The `parent_comment_id` a submitted reply should carry — always a
  /// top-level comment's own id, never another reply's: replying to a
  /// reply still targets *that reply's* parent, so the whole conversation
  /// flattens into one thread under the original top-level comment rather
  /// than nesting indefinitely.
  String? get _replyTargetRootId {
    final target = _replyTarget;
    if (target == null) return null;
    return target.parentCommentId ?? target.id;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startReply(PostComment comment) {
    // Auto-expands the thread being replied to — tapping "Reply" on a
    // collapsed root comment should let the traveler see the conversation
    // they're joining, not just post blind into a hidden thread.
    final rootId = comment.parentCommentId ?? comment.id;
    setState(() {
      _replyTarget = comment;
      _expandedThreads.add(rootId);
    });
    _focusNode.requestFocus();
  }

  void _cancelReply() => setState(() => _replyTarget = null);

  void _post() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _service.addComment(
      widget.postId,
      text,
      parentCommentId: _replyTargetRootId,
    );
    _controller.clear();
    setState(() => _replyTarget = null);
    FocusScope.of(context).unfocus();
  }

  Future<void> _confirmDeleteComment(PostComment comment) async {
    final isReply = comment.parentCommentId != null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          isReply ? 'Delete reply?' : 'Delete comment?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          isReply
              ? 'This reply will be removed for everyone.'
              : 'This comment and any replies to it will be removed for '
                    'everyone.',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteComment(comment.id);
      if (_replyTarget?.id == comment.id) setState(() => _replyTarget = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not delete comment: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<PostComment>>(
            stream: _commentsStream,
            builder: (context, snapshot) {
              final comments = snapshot.data ?? const <PostComment>[];
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (comments.isEmpty) {
                return Center(
                  child: Text(
                    'No comments yet — say something!',
                    style: TextStyle(color: context.colors.muted),
                  ),
                );
              }
              final roots = comments
                  .where((c) => c.parentCommentId == null)
                  .toList();
              final repliesByRoot = <String, List<PostComment>>{};
              for (final c in comments) {
                final parentId = c.parentCommentId;
                if (parentId != null) {
                  (repliesByRoot[parentId] ??= []).add(c);
                }
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                itemCount: roots.length,
                itemBuilder: (context, index) {
                  final root = roots[index];
                  final replies = repliesByRoot[root.id] ?? const [];
                  final expanded = _expandedThreads.contains(root.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _CommentTile(
                          comment: root,
                          onReply: () => _startReply(root),
                          onDelete: () => _confirmDeleteComment(root),
                        ),
                        if (replies.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 42),
                            child: GestureDetector(
                              onTap: () => _toggleThread(root.id),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    expanded
                                        ? Icons.subdirectory_arrow_left_rounded
                                        : Icons
                                              .subdirectory_arrow_right_rounded,
                                    size: 14,
                                    color: context.colors.muted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    expanded
                                        ? 'Hide replies'
                                        : 'View ${replies.length} '
                                              '${replies.length == 1 ? 'reply' : 'replies'}',
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (expanded)
                            for (final reply in replies)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  left: 32,
                                ),
                                child: _CommentTile(
                                  comment: reply,
                                  onReply: () => _startReply(reply),
                                  onDelete: () => _confirmDeleteComment(reply),
                                ),
                              ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
        if (_replyTarget != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(
              children: [
                Icon(
                  Icons.reply_rounded,
                  size: 15,
                  color: context.colors.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Replying to ${_replyTarget!.authorName}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _cancelReply,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  style: TextStyle(color: context.colors.ink, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: _replyTarget == null
                        ? 'Add a comment…'
                        : 'Write a reply…',
                    hintStyle: TextStyle(color: context.colors.muted),
                    filled: true,
                    fillColor: context.colors.card,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _post(),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: context.colors.ink,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _post,
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One comment or reply bubble — avatar, name, timestamp, body, and a
/// Reply action, plus a Delete action only when [comment.authorId] matches
/// the signed-in user.
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.onReply,
    required this.onDelete,
  });

  final PostComment comment;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isReply = comment.parentCommentId != null;
    final isOwnComment =
        comment.authorId == Supabase.instance.client.auth.currentUser?.id;
    final avatarSize = isReply ? 26.0 : 32.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UserAvatar(
          name: comment.authorName,
          avatarUrl: comment.authorAvatarUrl,
          size: avatarSize,
          borderWidth: 0,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.authorName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (isOwnComment) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F80ED),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      timeAgo(comment.createdAt),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                    if (isOwnComment) ...[
                      const Spacer(),
                      GestureDetector(
                        onTap: onDelete,
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: context.colors.muted,
                          size: 15,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.body,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onReply,
                  child: Text(
                    'Reply',
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
