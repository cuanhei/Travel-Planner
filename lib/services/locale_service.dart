import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/translations.dart';

const _languageCodeKey = 'app_language_code';

/// The active UI language code (e.g. 'en', 'ko', 'ja'). `MyApp` listens to
/// this and rebuilds the whole tree on change (see `main.dart`), so every
/// `tr('key')` call anywhere in the widget tree picks up the new language
/// automatically — no per-widget listeners needed.
final ValueNotifier<String> currentLanguageCode = ValueNotifier('en');

/// Loads the previously-picked language (if any) on app startup. Call once
/// in `main()` before `runApp`.
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

/// Translates [key] into the active language, falling back to English and
/// then the key itself if a translation is missing.
String tr(String key) {
  final code = currentLanguageCode.value;
  return translations[code]?[key] ?? translations['en']?[key] ?? key;
}
