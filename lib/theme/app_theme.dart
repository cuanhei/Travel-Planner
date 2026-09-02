import 'package:flutter/material.dart';

/// Global switch for the app's theme mode. Settings toggles this; every
/// screen picks it up automatically because `MaterialApp` listens to it
/// and rebuilds with the matching `ThemeData`, and every color lookup in
/// the app goes through `Theme.of(context)` (see [AppColorsContext]),
/// which propagates correctly even to offstage tabs and backgrounded
/// routes.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(
  ThemeMode.light,
);

/// Palette that varies between light and dark mode. Brand/gradient
/// colors (below, as static consts) stay constant across both.
@immutable
class AppColors {
  const AppColors._({
    required this.ink,
    required this.muted,
    required this.surface,
    required this.card,
  });

  final Color ink;
  final Color muted;
  final Color surface;
  final Color card;

  static const Color accent = Color(0xFFFF7A59);

  static const List<Color> horizon = [Color(0xFF10244A), Color(0xFF23417A)];
  static const List<Color> dusk = [Color(0xFF2B3A67), Color(0xFF5C6BC0)];
  static const List<Color> sunset = [Color(0xFFFF7A59), Color(0xFFFFB347)];
  static const List<Color> lagoon = [Color(0xFF11998E), Color(0xFF38EF7D)];

  static const AppColors light = AppColors._(
    ink: Color(0xFF0B1D3A),
    muted: Color(0xFF6E7A93),
    surface: Color(0xFFF6F7FB),
    card: Color(0xFFFFFFFF),
  );

  static const AppColors dark = AppColors._(
    ink: Color(0xFFF1F4FA),
    muted: Color(0xFF97A2B8),
    surface: Color(0xFF0B0F1A),
    card: Color(0xFF171C2B),
  );
}

/// `context.colors.ink` etc. — resolves to the light or dark palette
/// based on the active `Theme`, so it stays correct across the whole
/// navigation stack (unlike a plain global variable, this is backed by
/// `Theme`'s `InheritedWidget`, so every dependent widget is notified
/// and rebuilds when the theme changes, even if it isn't currently
/// being rebuilt by its parent).
extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).brightness == Brightness.dark
      ? AppColors.dark
      : AppColors.light;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: colors.surface,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        brightness: brightness,
        primary: colors.ink,
        secondary: AppColors.accent,
        surface: colors.surface,
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w800,
          color: colors.ink,
          height: 1.15,
        ),
        bodyLarge: TextStyle(color: colors.muted, height: 1.4),
      ),
    );
  }
}
