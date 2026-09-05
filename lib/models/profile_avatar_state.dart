import 'dart:convert';

import 'avatar_config.dart';

enum ProfileAvatarMode { photo, avatarDesign }

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

  static ProfileAvatarState decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ProfileAvatarState();
    if (raw.startsWith(_prefix)) {
      try {
        final json =
            jsonDecode(
                  utf8.decode(base64Url.decode(raw.substring(_prefix.length))),
                )
                as Map<String, dynamic>;
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
      return ProfileAvatarState(
        mode: ProfileAvatarMode.avatarDesign,
        design: legacyDesign,
      );
    }
    return ProfileAvatarState(mode: ProfileAvatarMode.photo, photoUrl: raw);
  }
}
