import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/login_activity.dart';

/// Records and lists the signed-in user's recent sign-ins (Privacy &
/// Security > Login Activity), so they can spot unrecognized access.
///
/// [record] is called automatically from the global `onAuthStateChange`
/// listener in `main.dart` — not from the sign-in screens directly — so
/// every sign-in path (password, Google OAuth, anything added later) is
/// covered from one place. See
/// supabase/migrations/0015_login_activity.sql for the backing table.
class LoginActivityService {
  LoginActivityService._();

  static final LoginActivityService instance = LoginActivityService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Logs a successful sign-in for the current user, then prunes older
  /// rows beyond the most recent 20. Best-effort: never throws, since a
  /// logging failure shouldn't affect sign-in itself.
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

  /// The signed-in user's most recent sign-ins, newest first.
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

  /// A short device/platform label. On Flutter web, `defaultTargetPlatform`
  /// already reflects the visiting browser's underlying OS (detected from
  /// the user agent by the framework itself), so this needs no raw JS
  /// interop to be meaningfully specific (e.g. "Web · Windows").
  String _deviceInfo() {
    final platform = defaultTargetPlatform.name;
    final label = platform.isEmpty
        ? platform
        : platform[0].toUpperCase() + platform.substring(1);
    return kIsWeb ? 'Web · $label' : label;
  }
}
