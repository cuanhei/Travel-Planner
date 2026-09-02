import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/gradient_button.dart';
import '../widgets/password_strength.dart';
import 'auth_screen.dart';

/// "Set a new password" screen, reached once a recovery session has been
/// established by entering the 6-digit code from `forgot_password_screen.dart`.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _done = false;
  bool _loading = false;
  PasswordStrength _strength = PasswordStrength.weak;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onPasswordChanged(String value) {
    setState(() => _strength = calculatePasswordStrength(value));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      await AuthService.instance.updatePassword(_passwordController.text);
      // Verifying the recovery code left the user signed in under a
      // short-lived recovery session — sign out so "Back to Sign In"
      // requires actually typing the new password, confirming it was set
      // correctly.
      await AuthService.instance.signOut();
      if (!mounted) return;
      setState(() => _done = true);
    } on AuthException catch (e) {
      _showError(friendlyAuthError(e));
    } catch (_) {
      _showError(tr('common_error_generic'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _Header(done: _done),
          SafeArea(
            child: Column(
              children: [
                SizedBox(height: 190),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(24, 32, 24, 16),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration: Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                        ),
                        child: _done
                            ? _DoneView(key: ValueKey('done'))
                            : _FormView(
                                key: ValueKey('form'),
                                formKey: _formKey,
                                passwordController: _passwordController,
                                confirmController: _confirmController,
                                obscurePassword: _obscurePassword,
                                obscureConfirm: _obscureConfirm,
                                strength: _strength,
                                loading: _loading,
                                onPasswordChanged: _onPasswordChanged,
                                onTogglePassword: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                onToggleConfirm: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                                onSubmit: _submit,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_done)
            Positioned(
              top: 8,
              left: 4,
              child: SafeArea(
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_ios_new_rounded),
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.horizon,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.15),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(
                done ? Icons.check_rounded : Icons.lock_outline_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            SizedBox(height: 16),
            Text(
              done ? tr('auth_password_reset_done_title') : tr('auth_reset_password_title'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                done
                    ? tr('auth_password_reset_done_subtitle')
                    : tr('auth_reset_password_subtitle'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView({
    super.key,
    required this.formKey,
    required this.passwordController,
    required this.confirmController,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.strength,
    required this.loading,
    required this.onPasswordChanged,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool obscurePassword;
  final bool obscureConfirm;
  final PasswordStrength strength;
  final bool loading;
  final ValueChanged<String> onPasswordChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: passwordController,
            obscureText: obscurePassword,
            onChanged: onPasswordChanged,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.colors.ink,
            ),
            validator: Validators.newPassword,
            decoration: InputDecoration(
              labelText: tr('auth_new_password'),
              prefixIcon: Icon(
                Icons.lock_outline_rounded,
                color: context.colors.muted,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: context.colors.muted,
                  size: 20,
                ),
                onPressed: onTogglePassword,
              ),
              filled: true,
              fillColor: context.colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.colors.ink, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.redAccent, width: 1.2),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          SizedBox(height: 10),
          PasswordStrengthMeter(strength: strength),
          SizedBox(height: 12),
          PasswordRequirementsList(password: passwordController.text),
          SizedBox(height: 16),
          TextFormField(
            controller: confirmController,
            obscureText: obscureConfirm,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.colors.ink,
            ),
            validator: (v) =>
                Validators.confirmPassword(v, passwordController.text),
            decoration: InputDecoration(
              labelText: tr('auth_confirm_password'),
              prefixIcon: Icon(
                Icons.lock_outline_rounded,
                color: context.colors.muted,
                size: 20,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  obscureConfirm
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: context.colors.muted,
                  size: 20,
                ),
                onPressed: onToggleConfirm,
              ),
              filled: true,
              fillColor: context.colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.colors.ink, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.redAccent, width: 1.2),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          SizedBox(height: 28),
          GradientButton(
            label: tr('auth_reset_password_title'),
            onPressed: onSubmit,
            loading: loading,
          ),
        ],
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 12),
        Text(
          tr('auth_can_sign_in_now'),
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.muted, height: 1.5),
        ),
        SizedBox(height: 28),
        GradientButton(
          label: tr('auth_back_to_sign_in'),
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => AuthScreen()),
            (route) => false,
          ),
        ),
      ],
    );
  }
}
