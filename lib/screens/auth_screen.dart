import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../services/auth_error_messages.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/gradient_button.dart';
import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'verify_email_screen.dart';

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

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

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
    setState(() {
      _isSignIn = signIn;
      _formKey.currentState?.reset();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      if (_isSignIn) {
        await AuthService.instance.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen()),
          (route) => false,
        );
      } else {
        final response = await AuthService.instance.signUp(
          name: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (!mounted) return;
        if (response.session != null) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen()),
            (route) => false,
          );
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

  void _comingSoon(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$provider sign-in coming soon'),
      ),
    );
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
                          Form(
                            key: _formKey,
                            child: AnimatedSwitcher(
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
                                        () =>
                                            _obscureConfirm = !_obscureConfirm,
                                      ),
                                    ),
                            ),
                          ),
                          SizedBox(height: 4),
                          if (_isSignIn)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ForgotPasswordScreen(),
                                  ),
                                ),
                                child: Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          SizedBox(height: 12),
                          GradientButton(
                            label: _isSignIn ? 'Sign In' : 'Create Account',
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
                                  'or continue with',
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
                                onTap: () => _comingSoon('Google'),
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
                                    ? "Don't have an account? "
                                    : 'Already have an account? ',
                                style: TextStyle(color: context.colors.muted),
                              ),
                              GestureDetector(
                                onTap: () => _switchMode(!_isSignIn),
                                child: Text(
                                  _isSignIn ? 'Sign Up' : 'Sign In',
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
                isSignIn ? 'Welcome Back' : 'Join the Journey',
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
                  ? 'Sign in to continue exploring'
                  : 'Create an account to get started',
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
                  label: 'Sign In',
                  active: isSignIn,
                  onTap: () => onChanged(true),
                ),
              ),
              Expanded(
                child: _ToggleLabel(
                  label: 'Sign Up',
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

class _AuthTextField extends StatelessWidget {
  const _AuthTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.onSuffixTap,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? suffixIcon;
  final VoidCallback? onSuffixTap;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        labelText: label,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.redAccent, width: 1.2),
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
          label: 'Email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          validator: Validators.email,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: passwordController,
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscurePassword,
          suffixIcon: obscurePassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          onSuffixTap: onToggleObscure,
          validator: Validators.loginPassword,
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
          label: 'Full Name',
          icon: Icons.person_outline_rounded,
          validator: Validators.name,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: emailController,
          label: 'Email',
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          validator: Validators.email,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: passwordController,
          label: 'Password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscurePassword,
          suffixIcon: obscurePassword
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          onSuffixTap: onTogglePassword,
          validator: Validators.newPassword,
        ),
        SizedBox(height: 16),
        _AuthTextField(
          controller: confirmController,
          label: 'Confirm Password',
          icon: Icons.lock_outline_rounded,
          obscureText: obscureConfirm,
          suffixIcon: obscureConfirm
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          onSuffixTap: onToggleConfirm,
          validator: (v) =>
              Validators.confirmPassword(v, passwordController.text),
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
