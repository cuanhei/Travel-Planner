import '../data/countries.dart';

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

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    return null;
  }

  static final RegExp _specialCharPattern = RegExp(
    r'''[!@#$%^&*(),.?":{}|<>_\-\[\]/\\+=~`]''',
  );

  static bool hasMinLength(String v) => v.length >= 8;
  static bool hasUppercase(String v) => RegExp(r'[A-Z]').hasMatch(v);
  static bool hasLowercase(String v) => RegExp(r'[a-z]').hasMatch(v);
  static bool hasNumber(String v) => RegExp(r'[0-9]').hasMatch(v);
  static bool hasSpecialChar(String v) => _specialCharPattern.hasMatch(v);

  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Enter a password';
    if (!hasMinLength(v)) return 'Use at least 8 characters';
    if (!hasUppercase(v)) return 'Include at least one uppercase letter';
    if (!hasLowercase(v)) return 'Include at least one lowercase letter';
    if (!hasNumber(v)) return 'Include at least one number';
    if (!hasSpecialChar(v)) {
      return 'Include at least one special character';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'Passwords do not match';
    return null;
  }

  static final RegExp _digitsOnlyPattern = RegExp(r'^\d+$');

  static String? phone(String? value, Country country) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter a phone number';
    if (!_digitsOnlyPattern.hasMatch(v)) {
      return 'Phone number can only contain digits';
    }
    final min = country.minPhoneDigits;
    final max = country.maxPhoneDigits;
    if (v.length < min || v.length > max) {
      return min == max
          ? 'Enter exactly $min digits for ${country.name}'
          : 'Enter $min–$max digits for ${country.name}';
    }
    return null;
  }
}
