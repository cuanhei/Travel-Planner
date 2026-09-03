import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import 'supabase_config.dart';

class ProfileService {
  ProfileService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  /// The signed-in user's own `profiles` row, or null if signed out or the
  /// row hasn't been created yet.
  Future<Profile?> getCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final row = await _client
        .from('profiles')
        .select('display_name, full_name, email, avatar_color')
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Profile.fromMap(row, fallbackEmail: user.email);
  }
}
