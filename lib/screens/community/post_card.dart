import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/community_post.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_ago.dart';
import '../../widgets/user_avatar.dart';
import 'post_media_view.dart';

/// Cover-gradient key options a post can be tagged with, keyed by the text
/// value stored in `posts.cover_gradient` — no longer rendered anywhere
/// (a post with no photo/video just shows no cover), but the column is
/// still `not null` on `posts`, so [AddPostScreen] still picks one of
/// these keys to submit.
const communityGradients = <String, List<Color>>{
  'horizon': AppColors.horizon,
  'dusk': AppColors.dusk,
  'sunset': AppColors.sunset,
  'lagoon': AppColors.lagoon,
};

/// Reaction types a post can carry, keyed to the emoji shown for each —
/// matches the `reaction_type` check constraint on `post_likes`. Order here
/// is the order they appear in both the picker and the summary chips.
const _reactionEmojis = <String, String>{
  'like': '👍',
  'love': '❤️',
  'wow': '😮',
};

/// Explicit color-emoji styling for the reaction emoji above:
/// - `fontFamilyFallback` forces a real color-emoji font — without it,
///   some renderers (seen on both Flutter web and Android) fall back to a
///   plain monochrome glyph for characters like ❤️ (which has both a
///   text-style and an emoji-style form) instead of its full-color form.
/// - `color: Colors.black` pins full opacity. Text without an explicit
///   color inherits the ambient `DefaultTextStyle`, and in [_openPicker]
///   that ancestor is a `PopupMenuItem` deliberately marked
///   `enabled: false` (so it doesn't itself intercept taps meant for the
///   emoji buttons inside it) — Flutter renders disabled menu items with
///   a dimmed, translucent text style, which otherwise washes out even a
///   correctly-colored emoji glyph. The color's RGB is irrelevant to a
///   true color-glyph emoji (that comes from the font), only its opacity
///   matters here.
const _emojiTextStyle = TextStyle(
  color: Colors.black,
  fontFamilyFallback: ['Noto Color Emoji', 'Apple Color Emoji', 'Segoe UI Emoji'],
);

/// One Community post card — author, place, caption, cover, reactions, and
/// the comment/share action row. Used by the feed (`CommunityTab`) and by
/// `PostDetailScreen` (the landing screen for a shared post link).
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onReact,
    required this.onComment,
    required this.onShare,
    this.onEdit,
  });

  final CommunityPost post;

  /// Called with the reaction type to set ('like'/'love'/'wow'), or `null`
  /// to clear the current user's reaction.
  final ValueChanged<String?> onReact;
  final VoidCallback onComment;
  final VoidCallback onShare;

  /// Opens the post for editing. Only ever passed by callers that also
  /// checked `post.authorId` against the signed-in user — this widget does
  /// the same check itself below to decide whether to show the edit icon
  /// at all, so a `null` [onEdit] on someone else's post never matters.
  final VoidCallback? onEdit;

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
                    Text(
                      post.authorName,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
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
                  ],
                ),
              ),
              if (isOwnPost && onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child: Icon(
                    Icons.edit_outlined,
                    color: context.colors.muted,
                    size: 18,
                  ),
                ),
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
          if (post.mediaUrl != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: PostMediaView(url: post.mediaUrl!, mediaType: post.mediaType!),
            ),
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
              const Spacer(),
              GestureDetector(
                onTap: onShare,
                child: Icon(
                  Icons.share_outlined,
                  color: context.colors.muted,
                  size: 19,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small read-only "👍 3 ❤️ 1" row summarizing every reaction type that has
/// at least one count, in [_reactionEmojis] order.
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
                  Text(entry.value, style: _emojiTextStyle.copyWith(fontSize: 13)),
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

/// The tappable reaction control: shows the user's current reaction (emoji
/// + name) or a neutral "React" prompt when they haven't reacted. A plain
/// tap toggles the default 👍 on/off; a long-press opens a small emoji
/// picker (like/love/wow) at the touch point to pick — or switch to — a
/// specific reaction.
///
/// Tracks its own display locally and updates it the instant you tap,
/// rather than waiting for [myReaction] to round-trip back through the
/// feed/post stream — Realtime propagation for `post_likes` changes isn't
/// reliable enough yet to drive this from props alone (see
/// CommunityService.setReaction). [didUpdateWidget] still adopts a fresh
/// [myReaction] if one arrives (e.g. once Realtime is fixed, or the
/// reaction was changed from another device).
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
      // A plain tap is a simple on/off toggle: react 👍 if you haven't,
      // clear whatever reaction you have if you already did. Picking a
      // *different* reaction type is what long-press is for (below) — that
      // already sets it directly in one tap, no need to clear first.
      onTap: () => _react(active ? null : 'like'),
      onLongPressStart: (details) => _openPicker(context, details.globalPosition),
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
  const _PostAction({required this.icon, required this.label, required this.onTap});

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
