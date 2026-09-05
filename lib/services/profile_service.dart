import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/avatar_config.dart';
import '../models/profile_avatar_state.dart';

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

  final DateTime? createdAt;

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

class ProfileService {
  ProfileService._();

  static final ProfileService instance = ProfileService._();

  SupabaseClient get _client => Supabase.instance.client;

  final ValueNotifier<UserProfile?> current = ValueNotifier(null);

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

    await _client.auth.updateUser(
      UserAttributes(data: {'full_name': fullName}),
    );
    await load();
  }

  Future<void> setPublicProfile(bool isPublic) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    await _client
        .from('profiles')
        .update({'is_public': isPublic})
        .eq('id', user.id);
    await load();
  }

  Future<UserProfile?> getById(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return row == null ? null : UserProfile.fromRow(row);
  }

  Future<Map<String, UserProfile>> findByPhones(List<String> phones) async {
    final distinctPhones = phones.toSet().toList();
    if (distinctPhones.isEmpty) return {};
    final matches =
        await _client.rpc(
              'find_profiles_by_phone',
              params: {'p_phones': distinctPhones},
            )
            as List;
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

  Future<void> uploadAvatar(Uint8List bytes, String fileExt) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final path = '${user.id}/avatar.$fileExt';
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: 'image/$fileExt'),
        );

    final url = _client.storage.from('avatars').getPublicUrl(path);
    final bustedUrl = '$url?t=${DateTime.now().millisecondsSinceEpoch}';
    final state = ProfileAvatarState.decode(
      current.value?.avatarUrl,
    ).copyWith(mode: ProfileAvatarMode.photo, photoUrl: bustedUrl);
    await _client
        .from('profiles')
        .update({'avatar_url': state.encode()})
        .eq('id', user.id);
    await load();
  }

  Future<void> setAvatarDesign(AvatarConfig config) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final state = ProfileAvatarState.decode(
      current.value?.avatarUrl,
    ).copyWith(mode: ProfileAvatarMode.avatarDesign, design: config);
    await _client
        .from('profiles')
        .update({'avatar_url': state.encode()})
        .eq('id', user.id);
    await load();
  }

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
