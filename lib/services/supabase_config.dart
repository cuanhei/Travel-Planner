import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase project credentials.
///
/// Both values are safe to ship in a client app (the anon key is
/// rate-limited and constrained by Row Level Security), but they're read
/// from `--dart-define` so the same code works for every teammate's
/// project without editing source.
///
/// Run with your own project's values, e.g.:
///   flutter run -d chrome \
///     --dart-define=SUPABASE_URL=https://xxxxx.supabase.co \
///     --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  /// The `sb_publishable_...` key (or, on older projects, the legacy `anon`
  /// JWT key — either works here).
  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static bool get isConfigured => url.isNotEmpty && publishableKey.isNotEmpty;

  static SupabaseClient get client => Supabase.instance.client;
}

/// Retries [action] when it fails with Postgrest's `PGRST303` ("JWT
/// issued at future") — a transient false rejection that can happen for
/// a moment right after Supabase auto-refreshes the access token, if the
/// request lands on a backend node whose clock hasn't caught up to the
/// new token's `iat` yet. A short retry almost always succeeds; any
/// other error is rethrown immediately since it's a real failure.
Future<T> retryOnJwtClockSkew<T>(Future<T> Function() action) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await action();
    } on PostgrestException catch (e) {
      if (e.code != 'PGRST303' || attempt >= 2) rethrow;
      await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }
}
