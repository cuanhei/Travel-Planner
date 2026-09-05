import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';

const _languageCodeKey = 'app_language_code';

final ValueNotifier<String> currentLanguageCode = ValueNotifier('en');

Future<void> loadSavedLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_languageCodeKey);
  if (saved != null) currentLanguageCode.value = saved;
}

Future<void> setAppLanguage(String code) async {
  currentLanguageCode.value = code;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_languageCodeKey, code);
}

String tr(String key) {
  final code = currentLanguageCode.value;
  return translations[code]?[key] ?? translations['en']?[key] ?? key;
}
