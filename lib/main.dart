import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/reset_password_screen.dart';
import 'screens/splash_screen.dart';
import 'services/supabase_config.dart';
import 'theme/app_theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );

    // Clicking the reset-password email link (as opposed to typing the
    // 6-digit code on `forgot_password_screen.dart`) lands back in this app
    // with a recovery session already attached; jump straight to the reset
    // form in that case too.
    //
    // On a cold start (the usual case for this event — the app was just
    // opened from the email link) this fires before `runApp` has produced a
    // first frame, so `navigatorKey.currentState` can still be null. Retry
    // on the next frame until the navigator exists instead of silently
    // dropping the navigation.
    Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        _pushResetPassword();
      }
    });
  }

  runApp(const MyApp());
}

bool _resetPasswordPushed = false;

/// Called by `forgot_password_screen.dart` right before it navigates to the
/// Reset Password screen itself (after a successful code verification), so
/// the global recovery-event listener above doesn't also try to push it a
/// second time if that same event arrives from `verifyOTP`.
void markResetPasswordShown() => _resetPasswordPushed = true;

void _pushResetPassword() {
  if (_resetPasswordPushed) return;
  final state = navigatorKey.currentState;
  if (state == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _pushResetPassword());
    return;
  }
  _resetPasswordPushed = true;
  state.push(MaterialPageRoute(builder: (_) => ResetPasswordScreen()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'TravelPlanner',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: const SplashScreen(),
        );
      },
    );
  }
}
