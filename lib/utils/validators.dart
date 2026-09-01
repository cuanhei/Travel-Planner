/// Client-side form validators for the Authentication module.
///
/// These catch obviously-bad input before it ever reaches Supabase, so the
/// user sees an inline field error instead of waiting on a network round
/// trip. Supabase still re-validates everything server-side (e.g. it will
/// reject a weak password even if a bug here let it through) — see
/// `auth_error_messages.dart` for how those server errors get surfaced.
class Validators {
  const Validators._();

  static final RegExp _emailPattern = RegExp(
    r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$',
  );

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email';
    if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your name';
    if (v.length < 2) return 'Name is too short';
    return null;
  }

  /// Sign-in only needs "something was typed" — strength is enforced at
  /// sign-up/reset time, not re-checked against an existing account.
  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    return null;
  }

  static final RegExp _specialCharPattern = RegExp(
    r'''[!@#$%^&*(),.?":{}|<>_\-\[\]/\\+=~`]''',
  );

  /// Sign-up / reset password: enforce a real strength floor. Checked in
  /// order so the field shows one specific, actionable error at a time
  /// rather than a single wall-of-text requirement list.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) {
      return 'Include at least one uppercase letter';
    }
    if (!RegExp(r'[a-z]').hasMatch(v)) {
      return 'Include at least one lowercase letter';
    }
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Include at least one number';
    if (!_specialCharPattern.hasMatch(v)) {
      return 'Include at least one special character';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'Passwords do not match';
    return null;
  }
}
