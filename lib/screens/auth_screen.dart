import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/remember_me_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/gradient_button.dart';
import 'email_two_factor_screen.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'profile/privacy_policy_screen.dart';
import 'profile/terms_of_service_screen.dart';
import 'verify_email_screen.dart';

/// Combined sign in / sign up screen reached from the welcome carousel.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isSignIn = true;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;
  bool _rememberMe = true;
  bool _agreedToTerms = false;

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    final remembered = await RememberMeService.isRemembered();
    final email = await RememberMeService.savedEmail();
    if (!mounted) return;
    setState(() {
      _rememberMe = remembered;
      if (email != null) _emailController.text = email;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _switchMode(bool signIn) {
    if (signIn == _isSignIn) return;
    setState(() => _isSignIn = signIn);
  }

  /// Client-side checks, run before ever touching the network. Returns the
  /// first failing field's message, or null if everything looks valid.
  ///
  /// All errors — this pre-check and anything Supabase itself rejects — are
  /// surfaced as a single snackbar at the bottom of the page rather than
  /// inline under each field, so sign-in and sign-up show errors the same
  /// way.
  String? _validate() {
    if (_isSignIn) {
      return Validators.email(_emailController.text) ??
          Validators.loginPassword(_passwordController.text);
    }
    return Validators.name(_nameController.text) ??
        Validators.email(_emailController.text) ??
        Validators.newPassword(_passwordController.text) ??
        Validators.confirmPassword(
          _confirmController.text,
          _passwordController.text,
        ) ??
        (_agreedToTerms ? null : tr('auth_must_agree_terms'));
  }

  Future<void> _submit() async {
    final validationError = _validate();
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    setState(() => _loading = true);
    try {
      if (_isSignIn) {
        final email = _emailController.text.trim();
        final lockedUntil = await AuthService.instance.checkLoginLockout(
          email,
        );
        if (lockedUntil != null) {
          if (!mounted) return;
          _showError(_lockoutMessage(lockedUntil));
          return;
        }
        await AuthService.instance.signIn(
          email: email,
          password: _passwordController.text,
        );
        await RememberMeService.save(remember: _rememberMe, email: email);
        if (!mounted) return;
        if (AuthService.instance.emailTwoFactorEnabled) {
          await AuthService.instance.sendLoginEmailCode(email);
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => EmailTwoFactorScreen(email: email),
            ),
            (route) => false,
          );
          return;
        }
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen()),
          (route) => false,
        );
      } else {
        final email = _emailController.text.trim();
        if (await AuthService.instance.emailExists(email)) {
          if (!mounted) return;
          _showError(_emailAlreadyExistsMessage);
          return;
        }
        final response = await AuthService.instance.signUp(
          name: _nameController.text.trim(),
          email: email,
          password: _passwordController.text,
        );
        if (!mounted) return;
        if (response.session != null) {
          // Email confirmation is disabled on this project — Supabase
          // already signed the user in, so there's no code to verify.
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen()),
            (route) => false,
          );
        } else if (response.user?.identities?.isEmpty ?? false) {
          // Supabase deliberately can't tell a real signup from a repeat of
          // an already-registered (and confirmed) email via an error — it
          // returns this same "success" shape either way, distinguishable
          // only by an empty `identities` list, to prevent account
          // enumeration. The `emailExists` pre-check above normally catches
          // this first; this is a fallback for when that RPC is unavailable.
          _showError(_emailAlreadyExistsMessage);
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  VerifyEmailScreen(email: _emailController.text.trim()),
            ),
          );
        }
      }
    } on AuthException catch (e) {
      if (_isSignIn && isInvalidCredentials(e)) {
        final email = _emailController.text.trim();
        final lockedUntil = await AuthService.instance.recordFailedLogin(
          email,
        );
        if (!mounted) return;
        if (lockedUntil != null) {
          _showError(_lockoutMessage(lockedUntil));
          return;
        }
        final registered = await AuthService.instance.emailExists(email);
        if (!mounted) return;
        _showError(
          registered
              ? tr('auth_incorrect_credentials')
              : tr('auth_no_account_found'),
        );
      } else if (!_isSignIn && _isEmailAlreadyExists(e)) {
        _showError(_emailAlreadyExistsMessage);
      } else {
        _showError(friendlyAuthError(e));
      }
    } catch (e, st) {
      debugPrint('AuthScreen._submit unexpected error: $e\n$st');
      _showError(tr('common_error_generic'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _emailAlreadyExistsMessage => tr('auth_email_already_exists');

  /// "Too many attempts. Try again in N min." — N rounded up so a lockout
  /// that has, say, 40 seconds left still reads "1 min" rather than "0
  /// min".
  String _lockoutMessage(DateTime lockedUntil) {
    final remaining = lockedUntil.difference(DateTime.now());
    final minutes = remaining.inSeconds <= 0
        ? 1
        : (remaining.inSeconds / 60).ceil();
    return '${tr('auth_too_many_attempts_prefix')} $minutes ${tr('auth_min_suffix')}';
  }

  bool _isEmailAlreadyExists(AuthException e) =>
      e.code == 'user_already_exists' ||
      e.code == 'email_exists' ||
      e.message.toLowerCase().contains('already registered') ||
      e.message.toLowerCase().contains('already exists');

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  void _comingSoon(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$provider ${tr('common_coming_soon').toLowerCase()}'),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      // Redirects the whole page to Google, so nothing after this line
      // normally runs — the app reloads at redirectTo once the user
      // finishes on Google's side, and SplashScreen picks up the resulting
      // session from there.
      await AuthService.instance.signInWithGoogle();
    } on AuthException catch (e) {
      if (!mounted) return;
      _showError(friendlyAuthError(e));
    } catch (e, st) {
      debugPrint('AuthScreen._signInWithGoogle unexpected error: $e\n$st');
      if (!mounted) return;
      _showError(tr('common_error_generic'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _Header(isSignIn: _isSignIn),
          SafeArea(
            child: Column(
              children: [
                SizedBox(height: 190),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(24, 28, 24, 16),
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
                          _ModeToggle(
                            isSignIn: _isSignIn,
                            onChanged: _switchMode,
                          ),
                          SizedBox(height: 28),
                          AnimatedSwitcher(
                            duration: Duration(milliseconds: 350),
                            transitionBuilder: (child, animation) {
                              final offset = Tween<Offset>(
                                begin: Offset(_isSignIn ? -0.08 : 0.08, 0),
                                end: Offset.zero,
                              ).animate(animation);
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: offset,
                                  child: child,
                                ),
                              );
                            },
                            child: _isSignIn
                                ? _SignInFields(
                                    key: ValueKey('signin'),
                                    emailController: _emailController,
                                    passwordController: _passwordController,
                                    obscurePassword: _obscurePassword,
                                    onToggleObscure: () => setState(
                                      () => _obscurePassword =
                                          !_obscurePassword,
                                    ),
                                  )
                                : _SignUpFields(
                                    key: ValueKey('signup'),
                                    nameController: _nameController,
                                    emailController: _emailController,
                                    passwordController: _passwordController,
                                    confirmController: _confirmController,
                                    obscurePassword: _obscurePassword,
                                    obscureConfirm: _obscureConfirm,
                                    onTogglePassword: () => setState(
                                      () => _obscurePassword =
                                          !_obscurePassword,
                                    ),
                                    onToggleConfirm: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm,
                                    ),
                                  ),
                          ),
                          SizedBox(height: 4),
                          if (_isSignIn)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _RememberMeCheckbox(
                                  value: _rememberMe,
                                  onChanged: (v) =>
                                      setState(() => _rememberMe = v),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ForgotPasswordScreen(),
                                    ),
                                  ),
                                  child: Text(
                                    tr('auth_forgot_password'),
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            _TermsCheckbox(
                              value: _agreedToTerms,
                              onChanged: (v) =>
                                  setState(() => _agreedToTerms = v),
                            ),
                          SizedBox(height: 12),
                          GradientButton(
                            label: _isSignIn
                                ? tr('auth_sign_in')
                                : tr('auth_create_account'),
                            onPressed: _submit,
                            loading: _loading,
                          ),
                          SizedBox(height: 28),
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: context.colors.muted.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 12),
                                child: Text(
                                  tr('auth_or_continue_with'),
                                  style: TextStyle(
                                    color: context.colors.muted.withValues(
                                      alpha: 0.8,
                                    ),
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: context.colors.muted.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _SocialButton(
                                label: 'G',
                                onTap: _signInWithGoogle,
                              ),
                              SizedBox(width: 16),
                              _SocialButton(
                                icon: Icons.apple_rounded,
                                onTap: () => _comingSoon('Apple'),
                              ),
                              SizedBox(width: 16),
                              _SocialButton(
                                icon: Icons.facebook_rounded,
                                onTap: () => _comingSoon('Facebook'),
                              ),
                            ],
                          ),
                          SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _isSignIn
                                    ? tr('auth_no_account')
                                    : tr('auth_have_account'),
                                style: TextStyle(color: context.colors.muted),
                              ),
                              GestureDetector(
                                onTap: () => _switchMode(!_isSignIn),
                                child: Text(
                                  _isSignIn
                                      ? tr('auth_sign_up')
                                      : tr('auth_sign_in'),
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
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
  const _Header({required this.isSignIn});

  final bool isSignIn;

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
            Hero(
              tag: 'app-logo',
              child: Container(
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
                  Icons.travel_explore_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
            SizedBox(height: 16),
            AnimatedSwitcher(
              duration: Duration(milliseconds: 300),
              child: Text(
                isSignIn ? tr('auth_welcome_back') : tr('auth_join_journey'),
                key: ValueKey(isSignIn),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            SizedBox(height: 6),
            Text(
              isSignIn
                  ? tr('auth_signin_subtitle')
                  : tr('auth_signup_subtitle'),
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.isSignIn, required this.onChanged});

  final bool isSignIn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: isSignIn ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: context.colors.ink,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.ink.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _ToggleLabel(
                  label: tr('auth_sign_in'),
                  active: isSignIn,
                  onTap: () => onChanged(true),
                ),
              ),
              Expanded(
                child: _ToggleLabel(
                  label: tr('auth_sign_up'),
                  active: !isSignIn,
                  onTap: () => onChanged(false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleLabel extends StatelessWidget {
  const _ToggleLabel({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: Duration(milliseconds: 300),
          style: TextStyle(
            color: active ? Colors.white : context.colors.muted,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class _RememberMeCheckbox extends StatelessWidget {
  const _RememberMeCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: context.colors.ink,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            SizedBox(width: 8),
            Text(
              tr('auth_remember_me'),
              style: TextStyle(
                color: context.colors.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Required-before-sign-up checkbox linking out to the Terms of Service and
/// Privacy Policy screens (also reachable from Settings > About).
class _TermsCheckbox extends StatelessWidget {
  const _TermsCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final linkStyle = TextStyle(
      color: AppColors.accent,
      fontWeight: FontWeight.w700,
      fontSize: 12.5,
    );
    final textStyle = TextStyle(
      color: context.colors.muted,
      fontWeight: FontWeight.w600,
      fontSize: 12.5,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: value,
            onChanged: (v) => onChanged(v ?? false),
            activeColor: context.colors.ink,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(tr('auth_agree_terms_prefix'), style: textStyle),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TermsOfServiceScreen()),
                  ),
                  child: Text(tr('auth_terms_of_service'), style: linkStyle),
                ),
                Text(tr('auth_agree_terms_and'), style: textStyle),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PrivacyPolicyScreen()),
                  ),
                  child: Text(tr('auth_privacy_policy'), style: linkStyle),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.onSuffixTap,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        labelText: label,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: hint,
        hintStyle: TextStyle(
          color: context.colors.muted.withValues(alpha: 0.6),
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: context.colors.muted, size: 20),
        suffixIcon: suffixIcon != null
            ? IconButton(
                icon: Icon(suffixIcon, color: context.colors.muted, size: 20),
                onPressed: onSuffixTap,
              )
            : null,
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
        contentPadding: EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }
}

class _SignInFields extends StatelessWidget {
  const _SignInFields({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AuthTextField(
          controller: emailController,
          label: tr('auth_email'),
          hint: 'you@example.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: passwordController,
          label: tr('auth_password'),
          hint: 'Enter your password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscurePassword,
          suffixIcon: obscurePassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          onSuffixTap: onToggleObscure,
        ),
      ],
    );
  }
}

class _SignUpFields extends StatelessWidget {
  const _SignUpFields({
    super.key,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmController,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.onTogglePassword,
    required this.onToggleConfirm,
  });

  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final bool obscurePassword;
  final bool obscureConfirm;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _AuthTextField(
          controller: nameController,
          label: tr('auth_full_name'),
          hint: 'e.g. John Tan',
          icon: Icons.person_outline_rounded,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: emailController,
          label: tr('auth_email'),
          hint: 'you@example.com',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: passwordController,
          label: tr('auth_password'),
          hint: 'At least 8 characters',
          icon: Icons.lock_outline_rounded,
          obscureText: obscurePassword,
          suffixIcon: obscurePassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          onSuffixTap: onTogglePassword,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: confirmController,
          label: tr('auth_confirm_password'),
          hint: 'Re-enter your password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscureConfirm,
          suffixIcon: obscureConfirm
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          onSuffixTap: onToggleConfirm,
        ),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({this.icon, this.label, required this.onTap});

  final IconData? icon;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      shape: CircleBorder(),
      child: InkWell(
        customBorder: CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: context.colors.muted.withValues(alpha: 0.2),
            ),
          ),
          child: icon != null
              ? Icon(icon, color: context.colors.ink)
              : Text(
                  label!,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: context.colors.ink,
                    fontSize: 18,
                  ),
                ),
        ),
      ),
    );
  }
}
