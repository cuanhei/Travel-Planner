import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/gradient_button.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _Strength { weak, fair, strong }

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _done = false;
  bool _loading = false;
  _Strength _strength = _Strength.weak;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onPasswordChanged(String value) {
    setState(() {
      if (Validators.newPassword(value) == null) {
        _strength = _Strength.strong;
      } else if (value.length >= 8 &&
          RegExp(r'[A-Za-z]').hasMatch(value) &&
          RegExp(r'[0-9]').hasMatch(value)) {
        _strength = _Strength.fair;
      } else {
        _strength = _Strength.weak;
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      await AuthService.instance.updatePassword(_passwordController.text);
      if (!mounted) return;
      setState(() => _done = true);
    } on AuthException catch (e) {
      _showError(friendlyAuthError(e));
    } catch (_) {
      _showError('Something went wrong. Please try again.');
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
              done ? 'Password Reset!' : 'Reset Password',
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
                    ? 'Your password has been changed successfully'
                    : 'Create a new password for your account',
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
  final _Strength strength;
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
              labelText: 'New Password',
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
          _StrengthMeter(strength: strength),
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
              labelText: 'Confirm Password',
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
            label: 'Reset Password',
            onPressed: onSubmit,
            loading: loading,
          ),
        ],
      ),
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final _Strength strength;

  @override
  Widget build(BuildContext context) {
    final level = _Strength.values.indexOf(strength);
    final color = switch (strength) {
      _Strength.weak => Colors.redAccent,
      _Strength.fair => Colors.orangeAccent,
      _Strength.strong => Color(0xFF11998E),
    };
    final label = switch (strength) {
      _Strength.weak => 'Weak',
      _Strength.fair => 'Fair',
      _Strength.strong => 'Strong',
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

class _DoneView extends StatelessWidget {
  const _DoneView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 12),
        Text(
          'You can now sign in with your new password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.muted, height: 1.5),
        ),
        SizedBox(height: 28),
        GradientButton(
          label: 'Back to Sign In',
          onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        ),
      ],
    );
  }
}
