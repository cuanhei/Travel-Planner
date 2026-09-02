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

  /// Emails a 6-digit recovery code to [email] (no link — see the
  /// "Reset Password" template note in `SUPABASE_SETUP.md`).
  Future<void> sendPasswordResetCode(String email) {
    return _auth.resetPasswordForEmail(email);
  }

  Future<void> resendPasswordResetCode(String email) =>
      sendPasswordResetCode(email);

  /// Confirms the 6-digit recovery code and establishes a recovery session,
  /// so a subsequent [updatePassword] call is allowed to go through.
  Future<void> verifyRecoveryCode({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(type: OtpType.recovery, email: email, token: token);
  }

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
