import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  GoTrueClient get _auth => Supabase.instance.client.auth;

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

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.toString() : null,
    );
  }

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
