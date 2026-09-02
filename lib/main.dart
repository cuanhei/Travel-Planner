import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/locale_service.dart';
import 'services/supabase_config.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await loadSavedLanguage();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
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
              home: const SplashScreen(),
            );
          },
        );
      },
    );
  }
}
