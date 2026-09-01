import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase project credentials, loaded from `.env` (gitignored — copy
/// `.env.example` and fill in your project's URL/anon key). Call [load]
/// once, before `runApp`; [isConfigured] lets callers skip
/// `Supabase.initialize` gracefully if a teammate hasn't set up their
/// `.env` yet, instead of crashing on startup.
class SupabaseConfig {
  SupabaseConfig._();

  static String? _url;
  static String? _publishableKey;

  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
    _url = dotenv.maybeGet('SUPABASE_URL');
    _publishableKey = dotenv.maybeGet('SUPABASE_ANON_KEY');
  }

  static String get url => _url ?? '';

  /// The `sb_publishable_...` key (or, on older projects, the legacy
  /// `anon` JWT key — either works here).
  static String get publishableKey => _publishableKey ?? '';

  static bool get isConfigured =>
      url.isNotEmpty &&
      url != 'https://your-project-ref.supabase.co' &&
      publishableKey.isNotEmpty &&
      publishableKey != 'your-anon-public-key';

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
