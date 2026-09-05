import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/community_feed_event.dart';
import '../../models/community_post.dart';
import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../explore/explore_tab.dart' show categories;
import 'add_post_screen.dart';
import 'comments_screen.dart';
import 'post_card.dart';

class CommunityTab extends StatefulWidget {
  const CommunityTab({super.key});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  static const _pageSize = 10;

  final _service = CommunityService();
  final _scrollController = ScrollController();

  String? _selectedCategory;

  final List<CommunityPost> _posts = [];
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  bool _hasNewPosts = false;

  StreamSubscription<CommunityFeedEvent>? _activitySub;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
    _activitySub = _service.watchFeedActivity().listen(_onFeedEvent);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _activitySub?.cancel();
    super.dispose();
  }

  void _onFeedEvent(CommunityFeedEvent event) {
    switch (event) {
      case NewPostAvailable():
        if (!mounted || _initialLoading) return;
        setState(() => _hasNewPosts = true);
      case PostReactionsChanged(
        :final postId,
        :final reactionCounts,
        :final likesCount,
      ):
        final index = _posts.indexWhere((p) => p.id == postId);
        if (!mounted || index == -1) return;
        setState(() {
          _posts[index] = _posts[index].copyWith(
            reactionCounts: reactionCounts,
            likesCount: likesCount,
          );
        });
      case PostCommentCountChanged(:final postId, :final delta):
        final index = _posts.indexWhere((p) => p.id == postId);
        if (!mounted || index == -1) return;
        setState(() {
          final current = _posts[index];
          _posts[index] = current.copyWith(
            commentsCount: (current.commentsCount + delta).clamp(0, 1 << 30),
          );
        });
    }
  }

  Future<void> _refreshFromBanner() async {
    setState(() => _hasNewPosts = false);
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    await _loadInitial();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _initialLoading) return;
    final position = _scrollController.position;
    if (position.pixels > position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _initialLoading = true;
      _error = null;
    });
    try {
      final page = await _service.fetchFeedPage(
        category: _selectedCategory,
        offset: 0,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(page);
        _hasMore = page.length == _pageSize;
        _initialLoading = false;
        _hasNewPosts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _initialLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchFeedPage(
        category: _selectedCategory,
        offset: _posts.length,
        limit: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _loadingMore = false);
    }
  }

  void _selectCategory(String? category) {
    if (category == _selectedCategory) return;
    setState(() => _selectedCategory = category);
    _loadInitial();
  }

  Future<void> _addPost() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddPostScreen()));
    _loadInitial();
  }

  Future<void> _editPost(CommunityPost post) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddPostScreen(existingPost: post)),
    );
    _loadInitial();
  }

  Future<void> _confirmDeletePost(CommunityPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete post?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This post, along with its likes and comments, will be removed '
          'for everyone.',
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
      await _service.deletePost(post.id);
      if (mounted) setState(() => _posts.removeWhere((p) => p.id == post.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not delete post: $e'),
          ),
        );
      }
    }
  }

  Future<void> _react(CommunityPost post, String? reactionType) async {
    if (reactionType == post.myReaction) return;
    final counts = Map<String, int>.from(post.reactionCounts);
    final previous = post.myReaction;
    if (previous != null) {
      final left = (counts[previous] ?? 1) - 1;
      if (left <= 0) {
        counts.remove(previous);
      } else {
        counts[previous] = left;
      }
    }
    if (reactionType != null) {
      counts[reactionType] = (counts[reactionType] ?? 0) + 1;
    }
    final updated = post.copyWith(
      myReaction: reactionType,
      clearMyReaction: reactionType == null,
      reactionCounts: counts,
      likesCount: counts.values.fold<int>(0, (a, b) => a + b),
    );
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index != -1) setState(() => _posts[index] = updated);

    await _service.setReaction(
      post.id,
      reactionType: reactionType,
      currentReaction: previous,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadInitial,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
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
                    onTap: () => _selectCategory(null),
                  ),
                  for (final c in categories)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _CategoryChip(
                        label: c.label,
                        icon: c.icon,
                        selected: _selectedCategory == c.label,
                        onTap: () => _selectCategory(c.label),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_hasNewPosts)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _refreshFromBanner,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: context.colors.ink,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(
                            Icons.arrow_upward_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'New posts — tap to refresh',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        "Couldn't load the community feed.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.muted),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _loadInitial,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_initialLoading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_posts.isEmpty)
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
            else ...[
              ..._posts.map(
                (p) => PostCard(
                  post: p,
                  onReact: (reactionType) => _react(p, reactionType),
                  onComment: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          CommentsScreen(postId: p.id, place: p.placeName),
                    ),
                  ),
                  onEdit: () => _editPost(p),
                  onDelete: () => _confirmDeletePost(p),
                ),
              ),
              if (_loadingMore)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ],
        ),
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
