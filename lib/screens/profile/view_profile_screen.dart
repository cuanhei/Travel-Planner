import 'package:flutter/material.dart';

import '../../models/profile_avatar_state.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/gender_options.dart';
import '../../widgets/avatar_viewer.dart';
import '../../widgets/category_badge_chip.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/user_avatar.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime d) =>
    '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

/// Read-only view of a user's profile — the "other side" of the
/// Instagram-style public/private switch in Settings → Privacy &
/// Security. A public profile shows everything; a private one is
/// limited to name, photo, and bio, with a "This account is private"
/// notice instead of the rest — unless [userId] is the signed-in user's
/// own id, in which case everything always shows regardless of that
/// switch, since the restriction is about hiding details from others.
///
/// Reachable via Settings → Privacy & Security → "Preview My Profile"
/// (always the signed-in user's own [userId]) and by tapping a post
/// author's avatar in the Community feed (`PostCard`) — either the
/// signed-in user's own posts or someone else's, since [ProfileService.
/// getById] just returns whichever profile row [userId] points at.
class ViewProfileScreen extends StatefulWidget {
  const ViewProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  State<ViewProfileScreen> createState() => _ViewProfileScreenState();
}

class _ViewProfileScreenState extends State<ViewProfileScreen> {
  late Future<UserProfile?> _profile;

  @override
  void initState() {
    super.initState();
    _profile = ProfileService.instance.getById(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: tr('auth_profile_title')),
            Expanded(
              child: FutureBuilder<UserProfile?>(
                future: _profile,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final profile = snapshot.data;
                  if (profile == null) {
                    return Center(
                      child: Text(
                        tr('auth_profile_not_found'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  // The private-profile restriction is about hiding your
                  // details from *other* people — viewing your own profile
                  // (e.g. tapping your own avatar on a Community post)
                  // always shows everything, same as Edit Profile would.
                  final isOwnProfile =
                      profile.id == AuthService.instance.currentUser?.id;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: [
                      _ProfileHeader(
                        profile: profile,
                        isOwnProfile: isOwnProfile,
                      ),
                      const SizedBox(height: 28),
                      if (profile.isPublic || isOwnProfile)
                        _PublicDetails(profile: profile)
                      else
                        const _PrivateNotice(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile, required this.isOwnProfile});

  final UserProfile profile;

  /// Whether the signed-in viewer is looking at their own profile — the
  /// private-account lock icon is about warning a *viewer* that they're
  /// only seeing a limited view of someone else, so it stays hidden here
  /// even when [profile.isPublic] is off, since the full details below
  /// are already showing regardless (see [ViewProfileScreen]).
  final bool isOwnProfile;

  @override
  Widget build(BuildContext context) {
    final state = ProfileAvatarState.decode(profile.avatarUrl);
    final isAvatarDesign =
        state.mode == ProfileAvatarMode.avatarDesign && state.design != null;
    final photoUrl = state.mode == ProfileAvatarMode.photo
        ? state.photoUrl
        : null;
    final canZoom = isAvatarDesign || (photoUrl?.isNotEmpty ?? false);
    return Column(
      children: [
        MouseRegion(
          cursor: canZoom ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: !canZoom
                ? null
                : isAvatarDesign
                ? () => showAvatarDesignViewer(context, state.design!)
                : () => showAvatarViewer(context, photoUrl!),
            child: UserAvatar(
              name: profile.fullName,
              avatarUrl: profile.avatarUrl,
              size: 96,
              borderWidth: 3,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  profile.fullName.isEmpty
                      ? tr('auth_traveler_default')
                      : profile.fullName,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (!profile.isPublic && !isOwnProfile) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: context.colors.muted,
                  ),
                ],
              ],
            ),
            CategoryBadgeRow(categories: profile.earnedCategoryBadges),
          ],
        ),
        if (profile.bio?.isNotEmpty ?? false) ...[
          const SizedBox(height: 8),
          Text(
            profile.bio!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 13.5),
          ),
        ],
      ],
    );
  }
}

class _PrivateNotice extends StatelessWidget {
  const _PrivateNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: context.colors.muted.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.lock_rounded,
              size: 26,
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('auth_private_account_title'),
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr('auth_private_account_desc'),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _PublicDetails extends StatelessWidget {
  const _PublicDetails({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[
      (Icons.email_outlined, tr('auth_email'), profile.email),
      if (profile.phone?.isNotEmpty ?? false)
        (Icons.phone_outlined, tr('auth_phone'), profile.phone!),
      if (profile.dateOfBirth != null)
        (
          Icons.cake_outlined,
          tr('auth_date_of_birth'),
          _formatDate(profile.dateOfBirth!),
        ),
      if (profile.gender?.isNotEmpty ?? false)
        (
          Icons.person_outline_rounded,
          tr('auth_gender'),
          genderLabel(profile.gender!),
        ),
      if (profile.nationality?.isNotEmpty ?? false)
        (Icons.flag_outlined, tr('auth_nationality'), profile.nationality!),
      if (profile.address?.isNotEmpty ?? false)
        (Icons.home_outlined, tr('auth_address'), profile.address!),
      if (profile.createdAt != null)
        (
          Icons.event_available_outlined,
          tr('auth_date_registered'),
          _formatDate(profile.createdAt!.toLocal()),
        ),
    ];
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _InfoRow(
              icon: rows[i].$1,
              label: rows[i].$2,
              value: rows[i].$3,
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.showDivider,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: context.colors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: context.colors.muted, fontSize: 12.5),
                ),
              ),
              Flexible(
                flex: 2,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 42,
            color: context.colors.muted.withValues(alpha: 0.12),
          ),
      ],
    );
  }
}
