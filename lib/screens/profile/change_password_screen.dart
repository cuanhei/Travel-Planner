import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../services/auth_error_messages.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/password_strength.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  PasswordStrength _strength = PasswordStrength.weak;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onNewPasswordChanged(String value) {
    setState(() => _strength = calculatePasswordStrength(value));
  }

  Future<void> _submit() async {
    final currentPassword = _currentController.text;
    if (currentPassword.isEmpty) {
      _showMessage(tr('auth_enter_current_password'));
      return;
    }
    final newPasswordError = Validators.newPassword(_newController.text);
    if (newPasswordError != null) {
      _showMessage(newPasswordError);
      return;
    }
    final confirmError = Validators.confirmPassword(
      _confirmController.text,
      _newController.text,
    );
    if (confirmError != null) {
      _showMessage(confirmError);
      return;
    }
    if (_newController.text == currentPassword) {
      _showMessage(tr('auth_new_password_must_differ'));
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.instance.reauthenticate(currentPassword);
      await AuthService.instance.updatePassword(_newController.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.ink,
          content: Text(tr('auth_password_changed')),
        ),
      );
    } on AuthException catch (e) {
      if (isInvalidCredentials(e)) {
        _showMessage(tr('auth_current_password_incorrect'));
      } else {
        _showMessage(friendlyAuthError(e));
      }
    } catch (_) {
      _showMessage(tr('common_error_generic'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_change_password_title'),
              subtitle: tr('auth_change_password_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _FieldLabel(tr('auth_current_password')),
                  _PasswordBox(
                    controller: _currentController,
                    obscure: _obscureCurrent,
                    onToggle: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_new_password')),
                  _PasswordBox(
                    controller: _newController,
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    onChanged: _onNewPasswordChanged,
                  ),
                  const SizedBox(height: 10),
                  PasswordStrengthMeter(strength: _strength),
                  const SizedBox(height: 12),
                  PasswordRequirementsList(password: _newController.text),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_confirm_new_password')),
                  _PasswordBox(
                    controller: _confirmController,
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: tr('auth_update_password'),
                    icon: Icons.check_rounded,
                    onPressed: _submit,
                    loading: _loading,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class _PasswordBox extends StatelessWidget {
  const _PasswordBox({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    this.onChanged,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          color: context.colors.muted,
          size: 20,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: context.colors.muted,
            size: 20,
          ),
        ),
        filled: true,
        fillColor: context.colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.colors.ink, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }
}
