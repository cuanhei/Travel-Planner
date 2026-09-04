import 'package:shared_preferences/shared_preferences.dart';

/// Persists the "Remember Me" choice from the Sign In screen — whether the
/// session should survive closing the browser/app, and (if so) the email to
/// prefill next time.
///
/// Supabase itself always persists a session locally regardless of this
/// choice, so "not remembered" is enforced separately: `main.dart`/
/// `splash_screen.dart` checks [isRemembered] on cold start and signs the
/// user back out if it's false, rather than trying to stop Supabase from
/// persisting the session in the first place.
class RememberMeService {
  RememberMeService._();

  static const _rememberedKey = 'remember_me';
  static const _emailKey = 'remember_me_email';

  /// Called right after a successful sign-in.
  static Future<void> save({
    required bool remember,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberedKey, remember);
    if (remember) {
      await prefs.setString(_emailKey, email);
    } else {
      await prefs.remove(_emailKey);
    }
  }

  /// True unless the user explicitly unchecked "Remember Me" at their last
  /// sign-in. Defaults to true so someone who has never touched the
  /// checkbox (e.g. just signed up) isn't unexpectedly signed out.
  static Future<bool> isRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberedKey) ?? true;
  }

  static Future<String?> savedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }
}
