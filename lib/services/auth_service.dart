import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth for the Authentication module screens.
///
/// Callers should catch `AuthException` (thrown by supabase_flutter itself)
/// to show `e.message` to the user, and fall back to a generic message for
/// anything else (network errors, etc).
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Fires on sign in, sign out, token refresh, and password-recovery link
  /// clicks (`AuthChangeEvent.passwordRecovery`).
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  /// Returns the [AuthResponse] so callers can tell whether Supabase
  /// already signed the user in (email confirmation disabled on the
  /// project) or a confirmation code was emailed instead (session is null).
  Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String password,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );
  }

  Future<void> signIn({required String email, required String password}) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  /// Sends a password-reset link. On web the link redirects back into this
  /// same running app, which detects the recovery session from the URL and
  /// (see `main.dart`) pushes the Reset Password screen automatically.
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.toString() : null,
    );
  }

  /// Sets a new password for the currently signed-in user. Only valid once
  /// a recovery session has been established (via the emailed link).
  Future<void> updatePassword(String newPassword) {
    return _auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Confirms the 6-digit code emailed after sign-up and signs the user in.
  Future<void> verifySignupCode({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(type: OtpType.signup, email: email, token: token);
  }

  Future<void> resendSignupCode(String email) {
    return _auth.resend(type: OtpType.signup, email: email);
  }
}
