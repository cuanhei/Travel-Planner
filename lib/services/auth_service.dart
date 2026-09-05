import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  String get currentUserName {
    final metaName = currentUser?.userMetadata?['full_name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) return metaName.trim();
    final email = currentUser?.email;
    if (email != null && email.contains('@')) return email.split('@').first;
    return 'Traveler';
  }

  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  Future<AuthResponse> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _auth.signUp(
      email: email,
      password: password,
      data: {'full_name': name},
    );
    if (response.user != null) {
      unawaited(_sendWelcomeEmail(email: email, name: name));
    }
    return response;
  }

  /// Fires the "You're signed up for TravelPlanner!" welcome email
  /// ([supabase/functions/send-welcome-email]) directly from the client
  /// right after sign-up, rather than via a Database Webhook on
  /// `profiles` inserts — this project's Supabase instance is missing the
  /// internal `supabase_functions` schema Database Webhooks depend on, so
  /// calling the already-deployed function straight from here sidesteps
  /// that. Payload shape matches what the function expects from a
  /// Database Webhook (`{"record": {...}}`) so the function itself didn't
  /// need to change. Best-effort: any failure here (network blip, the
  /// function not yet deployed, etc) is swallowed and never surfaces to
  /// the sign-up flow.
  Future<void> _sendWelcomeEmail({
    required String email,
    required String name,
  }) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'send-welcome-email',
        body: {
          'record': {'email': email, 'display_name': name},
        },
      );
    } catch (e) {
      debugPrint('send-welcome-email invoke failed, skipping: $e');
    }
  }

  Future<void> signIn({required String email, required String password}) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  /// Starts the "Continue with Google" flow. On web this redirects the
  /// whole page to Google's sign-in screen and back to [redirectTo]
  /// (defaulting to this page's own origin, e.g. `http://localhost:8766`,
  /// which must be registered in both the Google Cloud OAuth client and the
  /// Supabase project's Auth > URL Configuration > Redirect URLs) — Supabase
  /// then picks the resulting session up automatically from the URL on the
  /// next app load, the same way `SplashScreen` already checks [isSignedIn].
  ///
  /// Requires the Google provider to be enabled (with a Client ID/Secret)
  /// under Supabase Auth > Providers first; see SUPABASE_SETUP.md.
  Future<bool> signInWithGoogle() {
    return _auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  Future<void> signOut() => _auth.signOut();

  /// Server-side account lockout after repeated failed sign-ins (Sign In
  /// screen) — tracked in `public.login_lockouts` via SECURITY DEFINER
  /// functions (see supabase/migrations/0014_login_lockout.sql), so it
  /// can't be bypassed by clearing local storage or switching devices.
  /// Keyed by email, since a failed attempt happens before Supabase knows
  /// which user it is.
  ///
  /// Returns the lockout end time if [email] is currently locked out, or
  /// null otherwise. Call before [signIn] so a locked-out account never
  /// even reaches Supabase's own rate limiter. Fails open (returns null)
  /// if the check itself errors — e.g. the migration hasn't been applied
  /// yet — so a broken/missing lockout check can never block sign-in.
  Future<DateTime?> checkLoginLockout(String email) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'check_login_lockout',
        params: {'p_email': email},
      );
      return result == null ? null : DateTime.parse(result as String);
    } catch (e) {
      debugPrint('checkLoginLockout failed, skipping: $e');
      return null;
    }
  }

  /// Records a failed sign-in attempt for [email]. Returns the lockout end
  /// time if this attempt just triggered a lockout (5 failures within 15
  /// minutes) — each successive lockout is 5 minutes longer than the last
  /// (5, 10, 15, ...) until a successful sign-in resets it — or null if
  /// [email] isn't locked out yet. Fails open (returns null) on error, same
  /// as [checkLoginLockout].
  Future<DateTime?> recordFailedLogin(String email) async {
    try {
      final result = await Supabase.instance.client.rpc(
        'record_failed_login',
        params: {'p_email': email},
      );
      final rows = result as List;
      if (rows.isEmpty) return null;
      final lockedUntil =
          (rows.first as Map<String, dynamic>)['locked_until'] as String?;
      return lockedUntil == null ? null : DateTime.parse(lockedUntil);
    } catch (e) {
      debugPrint('recordFailedLogin failed, skipping: $e');
      return null;
    }
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

  Future<void> verifySignupCode({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(type: OtpType.signup, email: email, token: token);
  }

  Future<void> resendSignupCode(String email) {
    return _auth.resend(type: OtpType.signup, email: email);
  }

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

  Future<void> deleteAccount() async {
    await Supabase.instance.client.rpc('delete_own_account');
    await _auth.signOut(scope: SignOutScope.local);
  }

  Future<void> reauthenticate(String currentPassword) {
    final email = currentUser?.email;
    if (email == null) {
      throw StateError('reauthenticate called with no signed-in user');
    }
    return signIn(email: email, password: currentPassword);
  }

  bool get emailTwoFactorEnabled =>
      currentUser?.userMetadata?['email_2fa_enabled'] == true;

  Future<void> setEmailTwoFactorEnabled(bool enabled) {
    return _auth.updateUser(
      UserAttributes(data: {'email_2fa_enabled': enabled}),
    );
  }

  Future<void> sendLoginEmailCode(String email) {
    return _auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  Future<void> verifyLoginEmailCode({
    required String email,
    required String token,
  }) {
    return _auth.verifyOTP(type: OtpType.email, email: email, token: token);
  }
}
