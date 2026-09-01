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
}
