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
    this.dateOfBirth,
    this.gender,
    this.nationality,
    this.address,
    this.isPublic = true,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final String? bio;
  final String? avatarUrl;
  final DateTime? dateOfBirth;
  final String? gender;
  final String? nationality;
  final String? address;

  /// When this account was registered — the `profiles` row's `created_at`,
  /// set once at sign-up by the `handle_new_user` DB trigger (see
  /// `supabase/schema.sql`) and never updated afterwards.
  final DateTime? createdAt;

  /// Instagram-style public/private switch (Settings → Privacy &
  /// Security → "Public Profile"). Public: another viewer sees
  /// everything on [ViewProfileScreen]. Private: only [fullName],
  /// [avatarUrl], and [bio] — see `view_profile_screen.dart`.
  final bool isPublic;

  factory UserProfile.fromRow(Map<String, dynamic> row) => UserProfile(
    id: row['id'] as String,
    fullName: (row['full_name'] as String?) ?? '',
    email: (row['email'] as String?) ?? '',
    phone: row['phone'] as String?,
    bio: row['bio'] as String?,
    avatarUrl: row['avatar_url'] as String?,
    dateOfBirth: row['date_of_birth'] == null
        ? null
        : DateTime.parse(row['date_of_birth'] as String),
    gender: row['gender'] as String?,
    nationality: row['nationality'] as String?,
    address: row['address'] as String?,
    isPublic: (row['is_public'] as bool?) ?? true,
    createdAt: row['created_at'] == null
        ? null
        : DateTime.parse(row['created_at'] as String),
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
            createdAt: DateTime.tryParse(user.createdAt),
          )
        : UserProfile.fromRow(row);
  }

  Future<void> updateProfile({
    required String fullName,
    String? phone,
    String? bio,
    DateTime? dateOfBirth,
    String? gender,
    String? nationality,
    String? address,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': _nullIfBlank(phone),
          'bio': _nullIfBlank(bio),
          'date_of_birth': dateOfBirth == null
              ? null
              : '${dateOfBirth.year.toString().padLeft(4, '0')}-'
                    '${dateOfBirth.month.toString().padLeft(2, '0')}-'
                    '${dateOfBirth.day.toString().padLeft(2, '0')}',
          'gender': _nullIfBlank(gender),
          'nationality': _nullIfBlank(nationality),
          'address': _nullIfBlank(address),
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

  /// Turns the Instagram-style public/private switch on/off for the
  /// signed-in user's own profile.
  Future<void> setPublicProfile(bool isPublic) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({'is_public': isPublic})
        .eq('id', user.id);
    await load();
  }

  /// Fetches any user's profile row by id, for [ViewProfileScreen]. Every
  /// signed-in user can read any profile row (needed to render trip-mates'
  /// names elsewhere in the app — see `schema.sql`'s
  /// `profiles_select_authenticated` policy), so [isPublic] is enforced
  /// by the viewing screen deciding what to *show*, not by the database
  /// deciding what it will *return*.
  Future<UserProfile?> getById(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : UserProfile.fromRow(row);
  }

  /// Matches each of [phones] against a signed-up TravelPlanner account's
  /// phone number (via the `find_profiles_by_phone` DB function — see
  /// `supabase/migrations/0013_find_profiles_by_phone.sql`, which
  /// normalizes both sides to digits-only before comparing), for Emergency
  /// Contact's "this contact is also a TravelPlanner user" linking.
  ///
  /// Returns a map keyed by the exact string from [phones] that matched
  /// (so a caller can look up `contact.phone` directly), to that user's
  /// full profile. A phone with no matching account is simply absent from
  /// the result — callers should treat that as "not a signed-up user".
  Future<Map<String, UserProfile>> findByPhones(List<String> phones) async {
    final distinctPhones = phones.toSet().toList();
    if (distinctPhones.isEmpty) return {};
    final matches = await _client.rpc(
      'find_profiles_by_phone',
      params: {'p_phones': distinctPhones},
    ) as List;
    if (matches.isEmpty) return {};

    final phoneById = <String, String>{};
    for (final row in matches) {
      phoneById[row['id'] as String] = row['matched_phone'] as String;
    }
    final profileRows = await _client
        .from('profiles')
        .select()
        .inFilter('id', phoneById.keys.toList());

    final result = <String, UserProfile>{};
    for (final row in profileRows) {
      final profile = UserProfile.fromRow(row);
      final phone = phoneById[profile.id];
      if (phone != null) result[phone] = profile;
    }
    return result;
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

  /// Switches which already-saved avatar (photo or design) is active,
  /// without changing either one's content — e.g. the Edit Profile screen's
  /// Photo/Avatar tab toggle only takes effect (persists) once this is
  /// called, which happens when the user taps "Save Changes".
  Future<void> setActiveAvatarMode(ProfileAvatarMode mode) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final state = ProfileAvatarState.decode(current.value?.avatarUrl);
    if (state.mode == mode) return;
    await _client
        .from('profiles')
        .update({'avatar_url': state.copyWith(mode: mode).encode()})
        .eq('id', user.id);
    await load();
  }

  String? _nullIfBlank(String? value) {
    final v = value?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }
}
