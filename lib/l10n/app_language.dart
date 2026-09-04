/// A language selectable on the Language screen. [flag] is a
/// representative country flag for that language, not a claim the
/// language belongs to only that country.
class AppLanguage {
  const AppLanguage({
    required this.code,
    required this.englishName,
    required this.nativeName,
    required this.flag,
  });

  final String code;
  final String englishName;
  final String nativeName;
  final String flag;
}

/// Languages with real translated strings (see `lib/l10n/strings/`).
const List<AppLanguage> supportedLanguages = [
  AppLanguage(code: 'en', englishName: 'English', nativeName: 'English', flag: '🇬🇧'),
  AppLanguage(code: 'ms', englishName: 'Malay', nativeName: 'Bahasa Melayu', flag: '🇲🇾'),
  AppLanguage(code: 'zh', englishName: 'Chinese (Simplified)', nativeName: '简体中文', flag: '🇨🇳'),
  AppLanguage(code: 'ja', englishName: 'Japanese', nativeName: '日本語', flag: '🇯🇵'),
  AppLanguage(code: 'ko', englishName: 'Korean', nativeName: '한국어', flag: '🇰🇷'),
  AppLanguage(code: 'th', englishName: 'Thai', nativeName: 'ไทย', flag: '🇹🇭'),
  AppLanguage(code: 'vi', englishName: 'Vietnamese', nativeName: 'Tiếng Việt', flag: '🇻🇳'),
  AppLanguage(code: 'id', englishName: 'Indonesian', nativeName: 'Bahasa Indonesia', flag: '🇮🇩'),
  AppLanguage(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी', flag: '🇮🇳'),
  AppLanguage(code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்', flag: '🇮🇳'),
  AppLanguage(code: 'ar', englishName: 'Arabic', nativeName: 'العربية', flag: '🇸🇦'),
  AppLanguage(code: 'es', englishName: 'Spanish', nativeName: 'Español', flag: '🇪🇸'),
  AppLanguage(code: 'fr', englishName: 'French', nativeName: 'Français', flag: '🇫🇷'),
  AppLanguage(code: 'de', englishName: 'German', nativeName: 'Deutsch', flag: '🇩🇪'),
  AppLanguage(code: 'pt', englishName: 'Portuguese', nativeName: 'Português', flag: '🇵🇹'),
  AppLanguage(code: 'ru', englishName: 'Russian', nativeName: 'Русский', flag: '🇷🇺'),
];

AppLanguage languageByCode(String code) =>
    supportedLanguages.firstWhere(
      (l) => l.code == code,
      orElse: () => supportedLanguages.first,
    );
