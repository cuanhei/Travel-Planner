import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_button.dart';
import 'home_screen.dart';

/// 6-digit email-verification screen reached after sign up. Confirms the
/// code with Supabase, which also signs the user in.
class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  final String? email;

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static final _digits = 6;
  final _controllers = List.generate(_digits, (_) => TextEditingController());
  final _focusNodes = List.generate(_digits, (_) => FocusNode());
  bool _verified = false;
  bool _hasError = false;
  bool _loading = false;
  int _cooldown = 30;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
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

  String get _code => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    setState(() => _hasError = false);
    if (value.isNotEmpty && index < _digits - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    if (_code.length == _digits) {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _verify() async {
    if (_code.length < _digits) {
      setState(() => _hasError = true);
      return;
    }
    if (widget.email == null) return;

    setState(() {
      _hasError = false;
      _loading = true;
    });
    try {
      await AuthService.instance.verifySignupCode(
        email: widget.email!,
        token: _code,
      );
      if (!mounted) return;
      setState(() => _verified = true);
    } on AuthException catch (e) {
      setState(() => _hasError = true);
      _showError(friendlyAuthError(e));
    } catch (_) {
      setState(() => _hasError = true);
      _showError('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (widget.email == null) return;
    try {
      await AuthService.instance.resendSignupCode(widget.email!);
      _startCooldown();
    } on AuthException catch (e) {
      _showError(friendlyAuthError(e));
    } catch (_) {
      _showError('Something went wrong. Please try again.');
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
          _Header(verified: _verified),
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
                        child: _verified
                            ? _VerifiedView(key: ValueKey('verified'))
                            : _CodeView(
                                key: ValueKey('code'),
                                email: widget.email,
                                controllers: _controllers,
                                focusNodes: _focusNodes,
                                hasError: _hasError,
                                loading: _loading,
                                cooldown: _cooldown,
                                onChanged: _onChanged,
                                onVerify: _verify,
                                onResend: _cooldown == 0 ? _resend : null,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_verified)
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
  const _Header({required this.verified});

  final bool verified;

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
                verified ? Icons.check_rounded : Icons.mark_email_read_outlined,
                color: Colors.white,
                size: 36,
              ),
            ),
            SizedBox(height: 16),
            Text(
              verified ? 'Email Verified!' : 'Verify Your Email',
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
                verified
                    ? "You're all set to start exploring"
                    : "We've sent a 6-digit code to your email",
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

  final String? email;
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
        if (email != null)
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
          label: 'Verify Email',
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
      ],
    );
  }
}

class _VerifiedView extends StatelessWidget {
  const _VerifiedView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: 12),
        Text(
          'Your email address has been confirmed.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.colors.muted, height: 1.5),
        ),
        SizedBox(height: 28),
        GradientButton(
          label: 'Continue',
          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen()),
            (route) => false,
          ),
        ),
      ],
    );
  }
}
