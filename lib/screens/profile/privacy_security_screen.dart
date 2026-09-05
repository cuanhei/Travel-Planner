import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../services/auth_error_messages.dart';
import '../../services/auth_service.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../widgets/detail_header.dart';
import '../../theme/app_theme.dart';
import '../../widgets/list_tile_card.dart';
import '../auth_screen.dart';
import 'login_activity_screen.dart';
import 'view_profile_screen.dart';

/// Privacy preferences are UI-only; Two-Factor Authentication is wired to
/// real Supabase email-OTP 2FA (see `AuthService`'s `emailTwoFactorEnabled`/
/// `setEmailTwoFactorEnabled`/`*LoginEmailCode*` methods and
/// `EmailTwoFactorScreen`) — a 6-digit code is emailed at sign-in whenever
/// the user has turned this on.
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _publicProfile = true;
  bool _publicProfileBusy = false;
  bool _shareActivityWithFriends = true;
  bool _locationSharing = true;

  bool _twoFactorEnabled = false;
  bool _twoFactorBusy = false;

  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _twoFactorEnabled = AuthService.instance.emailTwoFactorEnabled;
    _publicProfile = ProfileService.instance.current.value?.isPublic ?? true;
  }

  Future<void> _onPublicProfileChanged(bool isPublic) async {
    if (_publicProfileBusy) return;
    setState(() => _publicProfileBusy = true);
    try {
      await ProfileService.instance.setPublicProfile(isPublic);
      if (!mounted) return;
      setState(() => _publicProfile = isPublic);
      _showSnack(
        isPublic
            ? tr('auth_profile_now_public')
            : tr('auth_profile_now_private'),
      );
    } catch (e) {
      debugPrint('setPublicProfile failed: $e');
      _showSnack(tr('common_error_generic'), error: true);
    } finally {
      if (mounted) setState(() => _publicProfileBusy = false);
    }
  }

  Future<void> _onTwoFactorChanged(bool enable) async {
    if (_twoFactorBusy) return;
    setState(() => _twoFactorBusy = true);
    try {
      await AuthService.instance.setEmailTwoFactorEnabled(enable);
      if (!mounted) return;
      setState(() => _twoFactorEnabled = enable);
      _showSnack(
        enable
            ? tr('auth_2fa_now_on')
            : tr('auth_2fa_now_off'),
      );
    } on AuthException catch (e) {
      _showSnack(friendlyAuthError(e), error: true);
    } catch (_) {
      _showSnack(tr('common_error_generic'), error: true);
    } finally {
      if (mounted) setState(() => _twoFactorBusy = false);
    }
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.redAccent : context.colors.ink,
        content: Text(message),
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    if (_deletingAccount) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('auth_delete_account_confirm_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          tr('auth_delete_account_confirm_body'),
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(tr('common_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await AuthService.instance.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AuthScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      _showSnack(friendlyAuthError(e), error: true);
    } catch (e) {
      debugPrint('deleteAccount failed: $e');
      _showSnack(tr('common_error_generic'), error: true);
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_privacy_security'),
              subtitle: tr('auth_privacy_security_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _SectionLabel(tr('auth_visibility_section')),
                  _SwitchCard(
                    icon: Icons.public_rounded,
                    title: tr('auth_public_profile'),
                    subtitle: _publicProfile
                        ? tr('auth_public_profile_on_desc')
                        : tr('auth_public_profile_off_desc'),
                    value: _publicProfile,
                    busy: _publicProfileBusy,
                    onChanged: _onPublicProfileChanged,
                  ),
                  ListTileCard(
                    icon: Icons.visibility_outlined,
                    title: tr('auth_preview_my_profile'),
                    subtitle: tr('auth_preview_my_profile_desc'),
                    onTap: () {
                      final uid = AuthService.instance.currentUser?.id;
                      if (uid == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ViewProfileScreen(userId: uid),
                        ),
                      );
                    },
                  ),
                  _SwitchCard(
                    icon: Icons.group_rounded,
                    title: tr('auth_share_activity_friends'),
                    subtitle: tr('auth_share_activity_friends_desc'),
                    value: _shareActivityWithFriends,
                    onChanged: (v) =>
                        setState(() => _shareActivityWithFriends = v),
                  ),
                  _SwitchCard(
                    icon: Icons.location_on_outlined,
                    title: tr('auth_location_sharing'),
                    subtitle: tr('auth_location_sharing_desc'),
                    value: _locationSharing,
                    onChanged: (v) => setState(() => _locationSharing = v),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(tr('auth_security_section')),
                  _SwitchCard(
                    icon: Icons.verified_user_outlined,
                    title: tr('auth_two_factor_title'),
                    subtitle: _twoFactorEnabled
                        ? tr('auth_two_factor_enabled_desc')
                        : tr('auth_two_factor_disabled_desc'),
                    value: _twoFactorEnabled,
                    busy: _twoFactorBusy,
                    onChanged: _onTwoFactorChanged,
                  ),
                  ListTileCard(
                    icon: Icons.history_rounded,
                    title: tr('auth_login_activity_title'),
                    subtitle: tr('auth_login_activity_subtitle'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => LoginActivityScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(tr('auth_your_data_section')),
                  ListTileCard(
                    icon: Icons.delete_outline_rounded,
                    title: tr('auth_delete_account'),
                    iconColor: Colors.redAccent,
                    trailing: _deletingAccount
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: context.colors.muted,
                            ),
                          )
                        : null,
                    onTap: _deletingAccount ? null : _confirmDeleteAccount,
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

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _SwitchCard extends StatelessWidget {
  const _SwitchCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: context.colors.ink.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: context.colors.ink, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: context.colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (busy)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: context.colors.muted,
                ),
              ),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Colors.white,
              activeTrackColor: context.colors.ink,
            ),
        ],
      ),
    );
  }
}
