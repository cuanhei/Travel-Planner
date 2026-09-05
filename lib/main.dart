import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
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

  MediaKit.ensureInitialized();

  usePathUrlStrategy();

  try {
    await SupabaseConfig.load();
  } catch (_) {}

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );

    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        LoginActivityService.instance.record();
        final email = state.session?.user.email;
        if (email != null) AuthService.instance.clearLoginLockout(email);
      }
    });
  }

  if (kIsWeb && DefaultFirebaseOptions.isConfigured) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.web);
  }

  runApp(const MyApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return ValueListenableBuilder<String>(
          valueListenable: currentLanguageCode,
          builder: (context, _, _) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'TravelPlanner',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: mode,

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
