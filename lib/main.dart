import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/locale_service.dart';
import 'services/login_activity_service.dart';
import 'services/supabase_config.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadSavedLanguage();

  // Required once at startup before any Video/Player widget is used
  // (chat's voice/video attachments) — sets up media_kit's native libs.
  MediaKit.ensureInitialized();

  // Supabase is configured from `.env` (see SupabaseConfig.load) — the same
  // file also supplies the Transport module's Google Routes API key
  // (route_service.dart), so a missing .env shouldn't block startup.
  try {
    await SupabaseConfig.load();
  } catch (_) {}

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
    // Records login activity and clears any failed-login lockout streak
    // whenever a new sign-in actually completes. `signedIn` is GoTrue's
    // event specifically for that — a page reload that merely restores an
    // already-persisted session fires `initialSession` instead — so this
    // covers every sign-in path (password, Google OAuth, anything added
    // later) from one place without double-counting reloads.
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        LoginActivityService.instance.record();
        final email = state.session?.user.email;
        if (email != null) AuthService.instance.clearLoginLockout(email);
      }
    });
  }

  // Only the web config is filled in (see firebase_options.dart) — this app
  // currently only ships as a web build, and Firebase.initializeApp would
  // throw on a platform with no configured options.
  if (kIsWeb && DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        // Rebuilding the whole tree on a language change means every
        // `tr('key')` call anywhere in the app re-evaluates automatically —
        // no per-widget listeners needed.
        return ValueListenableBuilder<String>(
          valueListenable: currentLanguageCode,
          builder: (context, _, _) {
            return MaterialApp(
              title: 'TravelPlanner',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode,
              // Cupertino delegate is needed for CupertinoDatePicker, used as
              // an embeddable time-of-day wheel in Create Trip's date sheet.
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
