import 'package:flutter/material.dart';

import '../../models/community_post.dart';
import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../explore/explore_tab.dart' show categories;
import 'add_post_screen.dart';
import 'comments_screen.dart';
import 'post_card.dart';
import 'share_post_sheet.dart';

/// "Community" bottom-nav tab: a live travel-experience feed backed by
/// Supabase (`posts`, `post_likes`, `comments`).
class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  final _service = CommunityService();

  /// `null` = "All" — otherwise one of [categories]' labels, the same set
  /// a post is tagged with in [AddPostScreen].
  String? _selectedCategory;

  /// Subscribed once for the lifetime of this screen — calling
  /// [CommunityService.watchFeed] fresh on every `build()` would tear down
  /// and re-create the Realtime subscription (and its initial fetch) on
  /// every rebuild, so a reaction/like written right around a rebuild could
  /// get silently dropped instead of reflected in the UI.
  late final Stream<List<CommunityPost>> _feedStream = _service.watchFeed();

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
        stream: _feedStream,
        builder: (context, snapshot) {
          final posts = snapshot.data ?? const <CommunityPost>[];
          final filtered = _selectedCategory == null
              ? posts
              : posts.where((p) => p.category == _selectedCategory).toList();
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
              const SizedBox(height: 16),
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _CategoryChip(
                      label: 'All',
                      icon: Icons.apps_rounded,
                      selected: _selectedCategory == null,
                      onTap: () => setState(() => _selectedCategory = null),
                    ),
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: _CategoryChip(
                          label: c.label,
                          icon: c.icon,
                          selected: _selectedCategory == c.label,
                          onTap: () => setState(() => _selectedCategory = c.label),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
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
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      _selectedCategory == null
                          ? 'No posts yet — be the first to share a travel moment!'
                          : 'No $_selectedCategory posts yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.muted),
                    ),
                  ),
                )
              else
                ...filtered.map(
                  (p) => PostCard(
                    post: p,
                    onReact: (reactionType) => _service.setReaction(
                      p.id,
                      reactionType: reactionType,
                      currentReaction: p.myReaction,
                    ),
                    onComment: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            CommentsScreen(postId: p.id, place: p.placeName),
                      ),
                    ),
                    onShare: () => showSharePostSheet(context, p),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? context.colors.ink : context.colors.card,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : context.colors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
