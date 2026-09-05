import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/login_activity.dart';

class LoginActivityService {
  LoginActivityService._();

  static final LoginActivityService instance = LoginActivityService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> record() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _client.from('login_activity').insert({
        'user_id': user.id,
        'device_info': _deviceInfo(),
      });
      await _client.rpc('prune_login_activity', params: {'p_keep': 20});
    } catch (e) {
      debugPrint('LoginActivityService.record failed, skipping: $e');
    }
  }

  Future<List<LoginActivityEntry>> list() async {
    final user = _client.auth.currentUser;
    if (user == null) return [];
    final rows = await _client
        .from('login_activity')
        .select()
        .order('signed_in_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map((r) => LoginActivityEntry.fromRow(r as Map<String, dynamic>))
        .toList();
  }

  String _deviceInfo() {
    final platform = defaultTargetPlatform.name;
    final label = platform.isEmpty
        ? platform
        : platform[0].toUpperCase() + platform.substring(1);
    return kIsWeb ? 'Web · $label' : label;
  }
}
