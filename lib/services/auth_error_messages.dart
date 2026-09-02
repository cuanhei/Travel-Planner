import 'package:supabase_flutter/supabase_flutter.dart';

/// Maps a raw Supabase [AuthException] to a short, user-facing message.
///
/// Supabase's `message` strings are written for developers (e.g. "Invalid
/// login credentials"), and its `code` field (documented at
/// https://supabase.com/docs/guides/auth/debugging/error-codes) is stable
/// across message wording changes, so switch on that first and fall back to
/// pattern-matching the message, then the raw message itself.
String friendlyAuthError(AuthException e) {
  switch (e.code) {
    case 'user_already_exists':
    case 'email_exists':
      return 'An account with this email already exists. Try signing in instead.';
    case 'weak_password':
      return 'That password is too weak. Use at least 8 characters with a mix of letters and numbers.';
    case 'invalid_credentials':
      return 'Incorrect email or password.';
    case 'email_not_confirmed':
      return 'Please verify your email before signing in.';
    case 'user_not_found':
      return 'No account found with this email.';
    case 'same_password':
      return 'Your new password must be different from your current one.';
    case 'session_expired':
    case 'session_not_found':
    case 'flow_state_expired':
    case 'flow_state_not_found':
      return 'This link has expired. Please request a new one.';
    case 'over_email_send_rate_limit':
    case 'over_request_rate_limit':
      return 'Too many attempts. Please wait a moment and try again.';
    case 'otp_expired':
      return 'This code is invalid or has expired. Request a new one.';
    case 'signup_disabled':
    case 'email_provider_disabled':
      return 'Sign ups are currently disabled for this app.';
    case 'validation_failed':
    case 'bad_json':
      return 'Please check your details and try again.';
    case 'mfa_verification_failed':
      return 'That code is incorrect. Please try again.';
    case 'mfa_factor_not_found':
      return 'That verification method is no longer available.';
    case 'insufficient_aal':
      return 'Please sign out and sign in again to confirm this change.';
  }

  final message = e.message.toLowerCase();
  if (message.contains('invalid login credentials')) {
    return 'Incorrect email or password.';
  }
  if (message.contains('already registered') ||
      message.contains('already exists')) {
    return 'An account with this email already exists. Try signing in instead.';
  }
  if (message.contains('token has expired') ||
      (message.contains('invalid') && message.contains('otp'))) {
    return 'That code is invalid or has expired. Request a new one.';
  }
  if (message.contains('email address') && message.contains('invalid')) {
    return 'Enter a valid email address.';
  }

  return e.message;
}

/// True for a wrong-password/wrong-credentials error, regardless of the
/// exact message wording (which changes across Supabase versions — the
/// `code` field doesn't).
bool isInvalidCredentials(AuthException e) =>
    e.code == 'invalid_credentials' ||
    e.message.toLowerCase().contains('invalid login credentials');
