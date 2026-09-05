import 'dart:convert';

import 'avatar_config.dart';

enum ProfileAvatarMode { photo, avatarDesign }

/// The full state behind the profile's avatar picker. A saved photo and a
/// saved avatar design are kept side by side — switching "Photo" vs
/// "Avatar" mode only changes which one is active, it never throws the
/// other away, so neither has to be re-uploaded or redesigned after a
/// switch. Encodes to one string so it still fits the existing
/// `profiles.avatar_url` column without a schema change.
class ProfileAvatarState {
  const ProfileAvatarState({
    this.mode = ProfileAvatarMode.photo,
    this.photoUrl,
    this.design,
  });

  final ProfileAvatarMode mode;
  final String? photoUrl;
  final AvatarConfig? design;

  ProfileAvatarState copyWith({
    ProfileAvatarMode? mode,
    String? photoUrl,
    AvatarConfig? design,
  }) {
    return ProfileAvatarState(
      mode: mode ?? this.mode,
      photoUrl: photoUrl ?? this.photoUrl,
      design: design ?? this.design,
    );
  }

  static const _prefix = 'avatar-profile:v1:';

  String encode() {
    final json = {
      'mode': mode.name,
      'photoUrl': photoUrl,
      'design': design?.toJson(),
    };
    return '$_prefix${base64Url.encode(utf8.encode(jsonEncode(json)))}';
  }

  /// Also understands the two formats that predate this envelope: a plain
  /// photo URL, and the very first avatar creator's design-only encoding
  /// (see [AvatarConfig.encode]) — both decode into an equivalent state so
  /// nothing saved before this envelope existed gets lost.
  static ProfileAvatarState decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ProfileAvatarState();
    if (raw.startsWith(_prefix)) {
      try {
        final json = jsonDecode(
          utf8.decode(base64Url.decode(raw.substring(_prefix.length))),
        ) as Map<String, dynamic>;
        return ProfileAvatarState(
          mode: ProfileAvatarMode.values.firstWhere(
            (m) => m.name == json['mode'],
            orElse: () => ProfileAvatarMode.photo,
          ),
          photoUrl: json['photoUrl'] as String?,
          design: json['design'] != null
              ? AvatarConfig.fromJson(json['design'] as Map<String, dynamic>)
              : null,
        );
      } catch (_) {
        return const ProfileAvatarState();
      }
    }
    final legacyDesign = AvatarConfig.tryDecode(raw);
    if (legacyDesign != null) {
      return ProfileAvatarState(mode: ProfileAvatarMode.avatarDesign, design: legacyDesign);
    }
    return ProfileAvatarState(mode: ProfileAvatarMode.photo, photoUrl: raw);
  }
}
