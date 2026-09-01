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

  /// True if a *confirmed* account already exists for [email]. Used to show
  /// an immediate "already exists" error on the Sign Up screen — Supabase's
  /// `signUp()` deliberately can't tell you this itself (it returns an
  /// indistinguishable fake success instead, to prevent account
  /// enumeration), so this calls a `SECURITY DEFINER` DB function that only
  /// ever reveals a yes/no.
  ///
  /// Fails open (returns false) if the check itself errors — e.g. the
  /// `email_exists` migration hasn't been applied yet — so a broken/missing
  /// pre-check can never block sign-up itself, only skip the nicer inline
  /// error.
  Future<bool> emailExists(String email) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'email_exists',
        params: {'check_email': email},
      );
      return result as bool;
    } catch (e) {
      debugPrint('email_exists check failed, skipping: $e');
      return false;
    }
  }

  User? get currentUser => _auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Display name for the signed-in user — the `full_name` captured at
  /// sign-up (`AuthService.signUp`'s `data`), falling back to the email's
  /// local part, then a generic label if neither is available.
  String get currentUserName {
    final metaName = currentUser?.userMetadata?['full_name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) return metaName.trim();
    final email = currentUser?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'Traveler';
  }

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

  /// Emails a 6-digit recovery code and a recovery link to [email]. On web
  /// the link redirects back into this same running app, which (see
  /// `main.dart`) detects the recovery session and pushes the Reset
  /// Password screen automatically.
  Future<void> sendPasswordResetEmail(String email) {
    return _auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.toString() : null,
    );
  }

  /// Confirms the 6-digit recovery code and establishes a recovery session,
  /// so a subsequent [updatePassword] call is allowed to go through.
  Future<void> verifyRecoveryCode({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(
      type: OtpType.recovery,
      email: email,
      token: token,
    );
  }

  Future<void> resendPasswordResetCode(String email) => sendPasswordResetEmail(email);

  /// Sets a new password for the currently signed-in user. Only valid once
  /// a recovery session has been established (via [verifyRecoveryCode]).
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
