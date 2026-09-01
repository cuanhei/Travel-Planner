import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../main.dart' show markResetPasswordShown;
import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/gradient_button.dart';
import 'reset_password_screen.dart';

/// Requests a Supabase password-reset code, then lets the user enter the
/// 6-digit code emailed to them. Verifying it establishes a recovery
/// session and opens the Reset Password screen.
///
/// Deliberately code-based rather than link-based: a single-click email
/// link can get silently consumed by mail-provider link-prescanning (the
/// same issue that affects sign-up confirmation links) before the user
/// ever opens it, and it also depends on the click landing in the same
/// browser profile that requested it. A manually-typed code sidesteps both.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { request, code }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static final _digits = 6;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeControllers = List.generate(_digits, (_) => TextEditingController());
  final _codeFocusNodes = List.generate(_digits, (_) => FocusNode());

  _Step _step = _Step.request;
  bool _loading = false;
  bool _codeError = false;
  int _cooldown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    for (final c in _codeControllers) {
      c.dispose();
    }
    for (final f in _codeFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _code => _codeControllers.map((c) => c.text).join();

  Future<void> _sendCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      await AuthService.instance.sendPasswordResetEmail(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _step = _Step.code);
      _startCooldown();
    } on AuthException catch (e) {
      _showError(friendlyAuthError(e));
    } catch (_) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      await AuthService.instance.resendPasswordResetCode(
        _emailController.text.trim(),
      );
      _startCooldown();
    } on AuthException catch (e) {
      _showError(friendlyAuthError(e));
    } catch (_) {
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    if (_code.length < _digits) {
      setState(() => _codeError = true);
      return;
    }

    setState(() {
      _codeError = false;
      _loading = true;
    });
    try {
      await AuthService.instance.verifyRecoveryCode(
        email: _emailController.text.trim(),
        token: _code,
      );
      if (!mounted) return;
      markResetPasswordShown();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen()),
      );
    } on AuthException catch (e) {
      setState(() => _codeError = true);
      _showError(friendlyAuthError(e));
    } catch (_) {
      setState(() => _codeError = true);
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCodeChanged(int index, String value) {
    setState(() => _codeError = false);
    if (value.isNotEmpty && index < _digits - 1) {
      _codeFocusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _codeFocusNodes[index - 1].requestFocus();
    }
    if (_code.length == _digits) {
      FocusScope.of(context).unfocus();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  void _startCooldown() {
    setState(() => _cooldown = 30);
    Future.doWhile(() async {
      await Future.delayed(Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldown -= 1);
      return _cooldown > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _Header(step: _step),
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
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: Offset(0, 0.06),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _step == _Step.code
                            ? _CodeView(
                                key: ValueKey('code'),
                                email: _emailController.text.trim(),
                                controllers: _codeControllers,
                                focusNodes: _codeFocusNodes,
                                hasError: _codeError,
                                loading: _loading,
                                cooldown: _cooldown,
                                onChanged: _onCodeChanged,
                                onVerify: _verifyCode,
                                onResend: _cooldown == 0 ? _resend : null,
                              )
                            : _RequestView(
                                key: ValueKey('request'),
                                formKey: _formKey,
                                emailController: _emailController,
                                loading: _loading,
                                onSubmit: _sendCode,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
  const _Header({required this.step});

  final _Step step;

  @override
  Widget build(BuildContext context) {
    final isCode = step == _Step.code;
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
                isCode
                    ? Icons.mark_email_read_rounded
                    : Icons.lock_reset_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            SizedBox(height: 16),
            Text(
              isCode ? 'Enter Reset Code' : 'Forgot Password?',
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
                isCode
                    ? "We've sent a 6-digit code to your email"
                    : "No worries, we'll send you a reset code",
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

class _RequestView extends StatelessWidget {
  const _RequestView({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.loading,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.colors.ink,
            ),
            validator: Validators.email,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(
                Icons.mail_outline_rounded,
                color: context.colors.muted,
                size: 20,
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
            label: 'Send Reset Code',
            onPressed: onSubmit,
            loading: loading,
          ),
          SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: context.colors.muted,
              ),
              SizedBox(width: 6),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Text(
                  'Back to Sign In',
                  style: TextStyle(
                    color: context.colors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CodeView extends StatelessWidget {
  const _CodeView({
    super.key,
    required this.email,
    required this.controllers,
    required this.focusNodes,
    required this.hasError,
    required this.loading,
    required this.cooldown,
    required this.onChanged,
    required this.onVerify,
    required this.onResend,
  });

  final String email;
  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final bool hasError;
  final bool loading;
  final int cooldown;
  final void Function(int, String) onChanged;
  final VoidCallback onVerify;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (email.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: Text.rich(
              TextSpan(
                style: TextStyle(color: context.colors.muted, height: 1.5),
                children: [
                  TextSpan(text: 'Code sent to '),
                  TextSpan(
                    text: email,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(controllers.length, (index) {
            return SizedBox(
              width: 46,
              height: 56,
              child: TextField(
                controller: controllers[index],
                focusNode: focusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.colors.ink,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: hasError
                        ? BorderSide(color: Colors.redAccent, width: 1.2)
                        : BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.colors.ink,
                      width: 1.5,
                    ),
                  ),
                ),
                onChanged: (value) => onChanged(index, value),
              ),
            );
          }),
        ),
        if (hasError)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Enter the full 6-digit code',
              style: TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        SizedBox(height: 28),
        GradientButton(
          label: 'Verify Code',
          onPressed: onVerify,
          loading: loading,
        ),
        SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: TextButton(
            onPressed: onResend,
            child: Text(
              onResend == null ? 'Resend code in ${cooldown}s' : 'Resend Code',
              style: TextStyle(
                color: onResend == null
                    ? context.colors.muted
                    : AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.arrow_back_rounded,
              size: 16,
              color: context.colors.muted,
            ),
            SizedBox(width: 6),
            GestureDetector(
              onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
              child: Text(
                'Back to Sign In',
                style: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
