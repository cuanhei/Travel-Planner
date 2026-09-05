import 'package:shared_preferences/shared_preferences.dart';

class RememberMeService {
  RememberMeService._();

  static const _rememberedKey = 'remember_me';
  static const _emailKey = 'remember_me_email';

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

  static Future<bool> isRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_rememberedKey) ?? true;
  }

  static Future<String?> savedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }
}
