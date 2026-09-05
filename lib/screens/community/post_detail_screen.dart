import 'package:flutter/material.dart';

import '../../models/community_post.dart';
import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'comments_screen.dart';
import 'post_card.dart';
import 'share_post_sheet.dart';

/// Landing screen for a shared post link (`/post/<id>` — see
/// [parseSharedPostId] and `SplashScreen`). Shows the post itself plus its
/// full, live comment thread, scoped to this post only.
class PostDetailScreen extends StatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _service = CommunityService();

  /// Subscribed once for the lifetime of this screen — see the matching
  /// comment on `_feedStream` in `community_tab.dart` for why calling
  /// [CommunityService.watchPost] fresh on every `build()` would silently
  /// drop reaction updates written around a rebuild.
  late final Stream<CommunityPost?> _postStream = _service.watchPost(
    widget.postId,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: StreamBuilder<CommunityPost?>(
          stream: _postStream,
          builder: (context, snapshot) {
            final post = snapshot.data;
            return Column(
              children: [
                const DetailHeader(title: 'Post', subtitle: 'Shared moment'),
                if (!snapshot.hasData)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (post == null)
                  Expanded(
                    child: Center(
                      child: Text(
                        'This post is no longer available.',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                    child: PostCard(
                      post: post,
                      onReact: (reactionType) => _service.setReaction(
                        post.id,
                        reactionType: reactionType,
                        currentReaction: post.myReaction,
                      ),
                      onComment: () {},
                      onShare: () => showSharePostSheet(context, post),
                    ),
                  ),
                  Expanded(child: CommentsSection(postId: post.id)),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
