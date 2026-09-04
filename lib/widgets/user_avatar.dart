import 'package:flutter/material.dart';

import '../models/profile_avatar_state.dart';
import '../theme/app_theme.dart';
import 'avatar_preview.dart';

/// Circular avatar: the user's uploaded photo when [avatarUrl] is set,
/// otherwise a gradient circle with their name's first initial.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.size,
    this.borderWidth = 2,
  });

  final String name;
  final String? avatarUrl;
  final double size;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final state = ProfileAvatarState.decode(avatarUrl);
    if (state.mode == ProfileAvatarMode.avatarDesign && state.design != null) {
      return Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: context.colors.surface,
          border: Border.all(color: Colors.white, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: context.colors.ink.withValues(alpha: 0.12),
              blurRadius: size * 0.2,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.bottomCenter,
          child: AvatarPreview(config: state.design!, width: 190, height: 240),
        ),
      );
    }

    final photoUrl = state.mode == ProfileAvatarMode.photo ? state.photoUrl : null;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hasImage = photoUrl != null && photoUrl.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasImage
            ? null
            : LinearGradient(
                colors: AppColors.sunset,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        border: Border.all(color: Colors.white, width: borderWidth),
        image: hasImage
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.12),
            blurRadius: size * 0.2,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: hasImage
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: size * 0.38,
              ),
            ),
    );
  }
}
