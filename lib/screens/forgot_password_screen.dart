import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/gradient_button.dart';

/// Requests a Supabase password-reset email, then shows a confirmation
/// state. Tapping the link in that email lands back in the app and (see
/// `main.dart`) opens the Reset Password screen automatically.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _linkSent = false;
  bool _loading = false;
  int _cooldown = 0;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendLink() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      await AuthService.instance.sendPasswordResetEmail(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _linkSent = true);
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
      await AuthService.instance.sendPasswordResetEmail(
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
          _Header(isSent: _linkSent),
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
                        child: _linkSent
                            ? _SentView(
                                key: ValueKey('sent'),
                                email: _emailController.text.trim(),
                                cooldown: _cooldown,
                                loading: _loading,
                                onResend: _cooldown == 0 ? _resend : null,
                              )
                            : _RequestView(
                                key: ValueKey('request'),
                                formKey: _formKey,
                                emailController: _emailController,
                                loading: _loading,
                                onSubmit: _sendLink,
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
  const _Header({required this.isSent});

  final bool isSent;

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
                isSent
                    ? Icons.mark_email_read_rounded
                    : Icons.lock_reset_rounded,
                color: Colors.white,
                size: 36,
              ),
            ),
            SizedBox(height: 16),
            Text(
              isSent ? 'Check Your Email' : 'Forgot Password?',
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
                isSent
                    ? 'We sent a password reset link to your inbox'
                    : "No worries, we'll send you reset instructions",
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
            label: 'Send Reset Link',
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

class _SentView extends StatelessWidget {
  const _SentView({
    super.key,
    required this.email,
    required this.cooldown,
    required this.loading,
    required this.onResend,
  });

  final String email;
  final int cooldown;
  final bool loading;
  final VoidCallback? onResend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(color: context.colors.muted, height: 1.5),
            children: [
              TextSpan(text: "Didn't get the email? Check your spam "),
              TextSpan(text: 'folder, or resend it to '),
              TextSpan(
                text: email.isEmpty ? 'your email address' : email,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(text: '.'),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 28),
        SizedBox(
          height: 48,
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                )
              : TextButton(
                  onPressed: onResend,
                  child: Text(
                    onResend == null
                        ? 'Resend in ${cooldown}s'
                        : 'Resend Email',
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
