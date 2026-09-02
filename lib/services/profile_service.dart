import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/avatar_config.dart';
import '../models/profile_avatar_state.dart';

/// The signed-in user's `public.profiles` row.
@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone,
    this.bio,
    this.avatarUrl,
  });

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? bio;
  final String? avatarUrl;

  factory UserProfile.fromRow(Map<String, dynamic> row) => UserProfile(
    id: row['id'] as String,
    fullName: (row['full_name'] as String?) ?? '',
    email: (row['email'] as String?) ?? '',
    phone: row['phone'] as String?,
    bio: row['bio'] as String?,
    avatarUrl: row['avatar_url'] as String?,
  );
}

/// Loads and edits the signed-in user's profile row, and keeps a live
/// [current] value so Home, Profile, and Edit Profile all reflect an edit
/// immediately without each independently re-fetching from Supabase.
class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;

  final ValueNotifier<UserProfile?> current = ValueNotifier(null);

  /// Fetches the signed-in user's profile row. Safe to call repeatedly
  /// (e.g. on every Home Screen mount) — cheap, and just refreshes
  /// [current].
  Future<void> load() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      current.value = null;
      return;
    }
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();
    current.value = row == null
        ? UserProfile(
            id: user.id,
            fullName: (user.userMetadata?['full_name'] as String?) ?? '',
            email: user.email ?? '',
          )
        : UserProfile.fromRow(row);
  }

  Future<void> updateProfile({
    required String fullName,
    String? phone,
    String? bio,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': _nullIfBlank(phone),
          'bio': _nullIfBlank(bio),
        })
        .eq('id', user.id);
    // Keep the auth user_metadata copy of the name in sync too — screens
    // that haven't loaded a profile yet (e.g. right after sign-up) fall
    // back to reading it from there.
    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );
    await load();
  }

  /// Uploads a new avatar image and points the profile at it. [fileExt]
  /// is a plain extension like `jpg` or `png`.
  Future<void> uploadAvatar(Uint8List bytes, String fileExt) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final path = '${user.id}/avatar.$fileExt';
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: 'image/$fileExt',
          ),
        );
    // The storage path never changes between uploads, so the URL has to be
    // cache-busted or the browser (and Image.network's own cache) will
    // keep showing the old image.
    final url = _client.storage.from('avatars').getPublicUrl(path);
    final bustedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
    final state = ProfileAvatarState.decode(current.value?.avatarUrl).copyWith(
      mode: ProfileAvatarMode.photo,
      photoUrl: bustedUrl,
    );
    await _client
        .from('profiles')
        .update({'avatar_url': state.encode()})
        .eq('id', user.id);
    await load();
  }

  /// Points the profile at a designed avatar instead of an uploaded photo.
  /// Merges into the existing [ProfileAvatarState] rather than overwriting
  /// `avatar_url` outright, so a previously-uploaded photo survives and is
  /// still there if the user switches back to "Photo" mode later.
  Future<void> setAvatarDesign(AvatarConfig config) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final state = ProfileAvatarState.decode(current.value?.avatarUrl).copyWith(
      mode: ProfileAvatarMode.avatarDesign,
      design: config,
    );
    await _client
        .from('profiles')
        .update({'avatar_url': state.encode()})
        .eq('id', user.id);
    await load();
  }

  String? _nullIfBlank(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}
