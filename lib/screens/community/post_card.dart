import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/community_post.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_ago.dart';
import '../../widgets/user_avatar.dart';
import 'post_media_view.dart';

const communityGradients = <String, List<Color>>{
  'horizon': AppColors.horizon,
  'dusk': AppColors.dusk,
  'sunset': AppColors.sunset,
  'lagoon': AppColors.lagoon,
};

const _reactionEmojis = <String, String>{
  'like': '👍',
  'love': '❤️',
  'wow': '😮',
};

const _emojiTextStyle = TextStyle(
  color: Colors.black,
  fontFamilyFallback: [
    'Noto Color Emoji',
    'Apple Color Emoji',
    'Segoe UI Emoji',
  ],
);

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onReact,
    required this.onComment,
    this.onEdit,
    this.onDelete,
  });

  final CommunityPost post;

  final ValueChanged<String?> onReact;
  final VoidCallback onComment;

  final VoidCallback? onEdit;

  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final hasReactions = post.reactionCounts.values.any((c) => c > 0);
    final isOwnPost =
        post.authorId == Supabase.instance.client.auth.currentUser?.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(
                name: post.authorName,
                avatarUrl: post.authorAvatarUrl,
                size: 36,
                borderWidth: 0,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            post.authorName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        if (isOwnPost) ...[
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
                      ],
                    ),
                    Text(
                      '${post.placeName} · ${post.category} · '
                      '${timeAgo(post.createdAt)}'
                      '${post.isEdited ? ' · Edited' : ''}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    _PostIpLine(post: post),
                  ],
                ),
              ),
              if (isOwnPost && onEdit != null) ...[
                GestureDetector(
                  onTap: onEdit,
                  child: Icon(
                    Icons.edit_outlined,
                    color: context.colors.muted,
                    size: 18,
                  ),
                ),
                if (onDelete != null) ...[
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: context.colors.muted,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            post.caption,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          if (post.media.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PostMediaGallery(media: post.media),
          ],
          if (hasReactions) ...[
            const SizedBox(height: 10),
            _ReactionSummary(counts: post.reactionCounts),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _ReactionButton(myReaction: post.myReaction, onReact: onReact),
              const SizedBox(width: 18),
              _PostAction(
                icon: Icons.mode_comment_outlined,
                label: '${post.commentsCount}',
                onTap: onComment,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The post's "IP: George Town" / "IP: Unknown" line (Settings →
/// Privacy & Security → "Location Sharing") — [CommunityPost.ipAddress]
/// is a real-GPS-resolved area name despite the field/column name, not
/// a literal IP (see `PostLocationService`). For the signed-in user's
/// own posts, this reads the live [ProfileService.instance.current]
/// value instead of [CommunityPost.authorLocationSharingEnabled] — the
/// value hydrated when the feed was fetched — so flipping the setting
/// updates every already-visible post of theirs immediately, with no
/// refetch or page reload. Someone else's posts fall back to that
/// hydrated value, since there's no live channel to a stranger's
/// settings here.
class _PostIpLine extends StatelessWidget {
  const _PostIpLine({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final isOwnPost = post.authorId == AuthService.instance.currentUser?.id;
    if (!isOwnPost) {
      return _buildText(context, post.authorLocationSharingEnabled);
    }
    return ValueListenableBuilder<UserProfile?>(
      valueListenable: ProfileService.instance.current,
      builder: (context, profile, _) => _buildText(
        context,
        profile?.locationSharingEnabled ?? post.authorLocationSharingEnabled,
      ),
    );
  }

  Widget _buildText(BuildContext context, bool locationSharingEnabled) {
    final value = locationSharingEnabled
        ? (post.ipAddress ?? tr('community_ip_unknown'))
        : tr('community_ip_unknown');
    return Text(
      '${tr('community_ip_prefix')} $value',
      style: TextStyle(color: context.colors.muted, fontSize: 10.5),
    );
  }
}

/// A post's attached photos/videos — [media] itself is capped at
/// [CommunityService.maxPostMedia] by [AddPostScreen]. A single attachment
/// renders exactly as before (its own aspect ratio, scaled to the card's
/// width); two or three become a swipeable, equally-sized-tile carousel
/// with a dot indicator, since a `PageView` needs one fixed height for
/// every page regardless of each attachment's own aspect ratio.
class _PostMediaGallery extends StatefulWidget {
  const _PostMediaGallery({required this.media});

  final List<PostMedia> media;

  @override
  State<_PostMediaGallery> createState() => _PostMediaGalleryState();
}

class _PostMediaGalleryState extends State<_PostMediaGallery> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    if (media.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: PostMediaView(url: media.first.url, mediaType: media.first.type),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 1,

            child: LayoutBuilder(
              builder: (context, constraints) => PageView.builder(
                controller: _pageController,
                itemCount: media.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => PostMediaView(
                  url: media[i].url,
                  mediaType: media[i].type,
                  boxSize: constraints.maxWidth,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < media.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _page
                      ? context.colors.ink
                      : context.colors.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ReactionSummary extends StatelessWidget {
  const _ReactionSummary({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in _reactionEmojis.entries)
          if ((counts[entry.key] ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.value,
                    style: _emojiTextStyle.copyWith(fontSize: 13),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${counts[entry.key]}',
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _ReactionButton extends StatefulWidget {
  const _ReactionButton({required this.myReaction, required this.onReact});

  final String? myReaction;
  final ValueChanged<String?> onReact;

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton> {
  String? _myReaction;

  @override
  void initState() {
    super.initState();
    _myReaction = widget.myReaction;
  }

  @override
  void didUpdateWidget(covariant _ReactionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.myReaction != oldWidget.myReaction) {
      _myReaction = widget.myReaction;
    }
  }

  void _react(String? reactionType) {
    setState(() => _myReaction = reactionType);
    widget.onReact(reactionType);
  }

  Future<void> _openPicker(BuildContext context, Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromCenter(center: globalPosition, width: 0, height: 0),
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      color: context.colors.card,
      items: [
        PopupMenuItem<String>(
          padding: EdgeInsets.zero,
          enabled: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in _reactionEmojis.entries)
                InkResponse(
                  onTap: () => Navigator.of(context).pop(entry.key),
                  radius: 26,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Text(
                      entry.value,
                      style: _emojiTextStyle.copyWith(fontSize: 26),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    if (selected != null) _react(selected);
  }

  @override
  Widget build(BuildContext context) {
    final active = _myReaction != null;
    final emoji = active ? _reactionEmojis[_myReaction] : null;
    final label = active
        ? '${_myReaction![0].toUpperCase()}${_myReaction!.substring(1)}'
        : 'React';

    return GestureDetector(
      onTap: () => _react(active ? null : 'like'),
      onLongPressStart: (details) =>
          _openPicker(context, details.globalPosition),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          emoji != null
              ? Text(emoji, style: _emojiTextStyle.copyWith(fontSize: 16))
              : Icon(
                  Icons.thumb_up_outlined,
                  color: context.colors.muted,
                  size: 18,
                ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: active ? context.colors.ink : context.colors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostAction extends StatelessWidget {
  const _PostAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: context.colors.muted, size: 19),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
