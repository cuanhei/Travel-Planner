import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/code_expiry_timer.dart';
import '../widgets/gradient_button.dart';
import 'auth_screen.dart';
import 'home_screen.dart';

class EmailTwoFactorScreen extends StatefulWidget {
  const EmailTwoFactorScreen({super.key, required this.email});

  final String email;

  @override
  State<EmailTwoFactorScreen> createState() => _EmailTwoFactorScreenState();
}

class _EmailTwoFactorScreenState extends State<EmailTwoFactorScreen> {
  static final _digits = 6;
  final _controllers = List.generate(_digits, (_) => TextEditingController());
  final _focusNodes = List.generate(_digits, (_) => FocusNode());
  bool _hasError = false;
  bool _loading = false;
  bool _resending = false;
  bool _codeExpired = false;
  int _codeRequestId = 0;

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
    if (_codeExpired) {
      _showError(tr('auth_code_expired_error'));
      return;
    }
    if (_code.length < _digits) {
      setState(() => _hasError = true);
      return;
    }

    setState(() {
      _hasError = false;
      _loading = true;
    });
    try {
      await AuthService.instance.verifyLoginEmailCode(
        email: widget.email,
        token: _code,
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomeScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      setState(() => _hasError = true);
      _showError(friendlyAuthError(e));
    } catch (_) {
      setState(() => _hasError = true);
      _showError(tr('auth_something_went_wrong_retry'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _resending = true);
    try {
      await AuthService.instance.sendLoginEmailCode(widget.email);
      if (!mounted) return;
      setState(() {
        _codeExpired = false;
        _codeRequestId++;
      });
      _showError('${tr('auth_new_code_sent_to_prefix')} ${widget.email}');
    } on AuthException catch (e) {
      _showError(friendlyAuthError(e));
    } catch (_) {
      _showError(tr('auth_something_went_wrong_retry'));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _useDifferentAccount() async {
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => AuthScreen()),
      (route) => false,
    );
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
          _Header(email: widget.email),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(_controllers.length, (
                              index,
                            ) {
                              return SizedBox(
                                width: 46,
                                height: 56,
                                child: TextField(
                                  controller: _controllers[index],
                                  focusNode: _focusNodes[index],
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  maxLength: 1,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
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
                                      borderSide: _hasError
                                          ? BorderSide(
                                              color: Colors.redAccent,
                                              width: 1.2,
                                            )
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
                                  onChanged: (value) =>
                                      _onChanged(index, value),
                                ),
                              );
                            }),
                          ),
                          if (_hasError)
                            Padding(
                              padding: EdgeInsets.only(top: 10),
                              child: Text(
                                tr('auth_enter_full_code'),
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          SizedBox(height: 14),
                          CodeExpiryTimer(
                            resetKey: _codeRequestId,
                            onExpired: () =>
                                setState(() => _codeExpired = true),
                          ),
                          SizedBox(height: 14),
                          GradientButton(
                            label: tr('auth_verify_button'),
                            onPressed: _verify,
                            loading: _loading,
                          ),
                          SizedBox(height: 12),
                          SizedBox(
                            height: 44,
                            child: TextButton(
                              onPressed: _resending ? null : _resendCode,
                              child: Text(
                                _resending
                                    ? tr('auth_sending_ellipsis')
                                    : tr('auth_resend_code'),
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 44,
                            child: TextButton(
                              onPressed: _useDifferentAccount,
                              child: Text(
                                tr('auth_use_different_account'),
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.email});

  final String email;

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
                Icons.verified_user_outlined,
                color: Colors.white,
                size: 36,
              ),
            ),
            SizedBox(height: 16),
            Text(
              tr('auth_two_factor_title'),
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
                '${tr('auth_enter_code_sent_to_prefix')} $email',
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
