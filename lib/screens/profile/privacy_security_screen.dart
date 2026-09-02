import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../services/auth_error_messages.dart';
import '../../services/auth_service.dart';
import '../../widgets/detail_header.dart';
import '../../theme/app_theme.dart';
import '../../widgets/list_tile_card.dart';

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
  bool _publicProfile = false;
  bool _shareActivityWithFriends = true;
  bool _locationSharing = true;

  bool _twoFactorEnabled = false;
  bool _twoFactorBusy = false;

  @override
  void initState() {
    super.initState();
    _twoFactorEnabled = AuthService.instance.emailTwoFactorEnabled;
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
            ? 'Two-factor authentication is now on'
            : 'Two-factor authentication is now off',
      );
    } on AuthException catch (e) {
      _showSnack(friendlyAuthError(e), error: true);
    } catch (_) {
      _showSnack('Something went wrong. Please try again.', error: true);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete your account?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This permanently removes your profile, trips, and activity. '
          'This can\'t be undone.',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          content: const Text('Account deletion isn\'t available in this demo'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Privacy & Security',
              subtitle: 'Control what you share and with whom',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _SectionLabel('Visibility'),
                  _SwitchCard(
                    icon: Icons.public_rounded,
                    title: 'Public Profile',
                    subtitle: 'Anyone can view your profile and reviews',
                    value: _publicProfile,
                    onChanged: (v) => setState(() => _publicProfile = v),
                  ),
                  _SwitchCard(
                    icon: Icons.group_rounded,
                    title: 'Share Activity With Friends',
                    subtitle: 'Trip check-ins and reviews appear to friends',
                    value: _shareActivityWithFriends,
                    onChanged: (v) =>
                        setState(() => _shareActivityWithFriends = v),
                  ),
                  _SwitchCard(
                    icon: Icons.location_on_outlined,
                    title: 'Location Sharing',
                    subtitle: 'Used for nearby recommendations on this trip',
                    value: _locationSharing,
                    onChanged: (v) => setState(() => _locationSharing = v),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('Security'),
                  _SwitchCard(
                    icon: Icons.verified_user_outlined,
                    title: 'Two-Factor Authentication',
                    subtitle: _twoFactorEnabled
                        ? 'Enabled — a code is emailed to you when signing in'
                        : 'Email a code to you as an extra step when signing in',
                    value: _twoFactorEnabled,
                    busy: _twoFactorBusy,
                    onChanged: _onTwoFactorChanged,
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('Your Data'),
                  ListTileCard(
                    icon: Icons.download_rounded,
                    title: 'Download My Data',
                    subtitle: 'Export your trips and activity',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: context.colors.ink,
                        content: const Text('Export isn\'t available in this demo'),
                      ),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.delete_outline_rounded,
                    title: 'Delete Account',
                    iconColor: Colors.redAccent,
                    onTap: _confirmDeleteAccount,
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
