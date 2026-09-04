import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';

/// Shared by every "set/change a password" screen (Reset Password, Change
/// Password, ...) so the strength meter and requirements checklist always
/// look and behave the same.
enum PasswordStrength { weak, fair, strong }

PasswordStrength calculatePasswordStrength(String value) {
  if (Validators.newPassword(value) == null) return PasswordStrength.strong;
  if (Validators.hasMinLength(value) &&
      (Validators.hasUppercase(value) || Validators.hasLowercase(value)) &&
      Validators.hasNumber(value)) {
    return PasswordStrength.fair;
  }
  return PasswordStrength.weak;
}

/// The Weak / Fair / Strong segmented bar.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    final level = PasswordStrength.values.indexOf(strength);
    final color = switch (strength) {
      PasswordStrength.weak => Colors.redAccent,
      PasswordStrength.fair => Colors.orangeAccent,
      PasswordStrength.strong => Color(0xFF11998E),
    };
    final label = switch (strength) {
      PasswordStrength.weak => tr('auth_strength_weak'),
      PasswordStrength.fair => tr('auth_strength_fair'),
      PasswordStrength.strong => tr('auth_strength_strong'),
    };

    return Row(
      children: [
        Expanded(
          child: Row(
            children: List.generate(3, (i) {
              final filled = i <= level;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: filled
                        ? color
                        : context.colors.muted.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
        SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Live checklist of each strength requirement — red X by default, flips
/// to a green check the moment [password] satisfies it.
class PasswordRequirementsList extends StatelessWidget {
  const PasswordRequirementsList({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final requirements = [
      (label: tr('auth_password_req_min_length'), met: Validators.hasMinLength(password)),
      (
        label: tr('auth_password_req_uppercase'),
        met: Validators.hasUppercase(password),
      ),
      (
        label: tr('auth_password_req_lowercase'),
        met: Validators.hasLowercase(password),
      ),
      (label: tr('auth_password_req_number'), met: Validators.hasNumber(password)),
      (
        label: tr('auth_password_req_special'),
        met: Validators.hasSpecialChar(password),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: requirements.map((r) {
        final color = r.met ? Color(0xFF11998E) : Colors.redAccent;
        return Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(
                r.met ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 14,
                color: color,
              ),
              SizedBox(width: 6),
              Text(
                r.label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: r.met ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
