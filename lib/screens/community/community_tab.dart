import 'package:flutter/material.dart';

import '../../models/community_post.dart';
import '../../services/community_service.dart';
import '../../services/deep_link.dart';
import '../../theme/app_theme.dart';
import 'add_post_screen.dart';
import 'comments_screen.dart';
import 'post_card.dart';

/// "Community" bottom-nav tab: a live travel-experience feed backed by
/// Supabase (`posts`, `post_likes`, `comments`).
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  final _service = CommunityService();

  Future<void> _addPost() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddPostScreen()));
    // The feed stream picks up the new post via Realtime automatically —
    // nothing to do with the result here.
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<CommunityPost>>(
        stream: _service.watchFeed(),
        builder: (context, snapshot) {
          final posts = snapshot.data ?? const <CommunityPost>[];
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Community',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Material(
                    color: context.colors.ink,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _addPost,
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Travel stories from fellow explorers',
                style: TextStyle(color: context.colors.muted, fontSize: 13.5),
              ),
              const SizedBox(height: 20),
              if (snapshot.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Column(
                      children: [
                        Text(
                          'Couldn\'t load the community feed.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.muted),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (!snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'No posts yet — be the first to share a travel moment!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ),
                )
              else
                ...posts.map(
                  (p) => PostCard(
                    post: p,
                    onToggleLike: () => _service.toggleLike(
                      p.id,
                      currentlyLiked: p.likedByMe,
                    ),
                    onComment: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CommentsScreen(postId: p.id, place: p.placeName),
                      ),
                    ),
                    onShare: () => shareCommunityPost(p),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
