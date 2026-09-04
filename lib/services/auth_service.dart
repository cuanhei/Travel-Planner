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

  /// Clears any failed-login streak for [email] — called automatically
  /// after a successful sign-in (see the `onAuthStateChange` listener in
  /// `main.dart`). Fails open (silently) if the underlying migration isn't
  /// applied yet.
  Future<void> clearLoginLockout(String email) async {
    try {
      await Supabase.instance.client.rpc(
        'clear_login_lockout',
        params: {'p_email': email},
      );
    } catch (e) {
      debugPrint('clearLoginLockout failed, skipping: $e');
    }
  }

  /// Permanently deletes the signed-in user's account (Privacy & Security >
  /// Delete Account) via the `delete_own_account` SECURITY DEFINER DB
  /// function (see supabase/migrations/0012_delete_own_account.sql), which
  /// removes the row from `auth.users` and cascades through profiles,
  /// trips, and everything else owned by this user.
  ///
  /// Only clears the *local* session afterwards — the account (and its
  /// refresh token) is already gone server-side by that point, so a normal
  /// server-side sign-out call would just fail.
  Future<void> deleteAccount() async {
    await Supabase.instance.client.rpc('delete_own_account');
    await _auth.signOut(scope: SignOutScope.local);
  }

  /// Re-verifies the signed-in user's current password (e.g. before letting
  /// them change it) by attempting a fresh sign-in with it. Throws an
  /// [AuthException] with code `invalid_credentials` if it's wrong.
  Future<void> reauthenticate(String currentPassword) {
    final email = currentUser?.email;
    if (email == null) {
      throw StateError('reauthenticate called with no signed-in user');
    }
    return signIn(email: email, password: currentPassword);
  }

  /// True if this account has email-based two-factor authentication turned
  /// on (see [setEmailTwoFactorEnabled]). Read from the signed-in user's
  /// metadata, so it reflects whichever device last changed the setting as
  /// soon as that device is signed back in.
  bool get emailTwoFactorEnabled =>
      currentUser?.userMetadata?['email_2fa_enabled'] == true;

  /// Turns email-based two-factor authentication on/off for this account.
  Future<void> setEmailTwoFactorEnabled(bool enabled) {
    return _auth.updateUser(
      UserAttributes(data: {'email_2fa_enabled': enabled}),
    );
  }

  /// Emails a 6-digit sign-in code to [email] — sent right after a correct
  /// password when the account has email 2FA on, so it needs both the
  /// password and this code before the sign-in completes.
  ///
  /// `shouldCreateUser: false` makes this a no-op (throws) for an email with
  /// no account, rather than the passwordless sign-up Supabase's OTP
  /// endpoint otherwise supports.
  Future<void> sendLoginEmailCode(String email) {
    return _auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  /// Confirms the 6-digit code from [sendLoginEmailCode] and completes the
  /// sign-in.
  Future<void> verifyLoginEmailCode({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(type: OtpType.email, email: email, token: token);
  }
}
