import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/list_tile_card.dart';

/// UI-only privacy & security preferences.
class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _publicProfile = false;
  bool _shareActivityWithFriends = true;
  bool _locationSharing = true;
  bool _twoFactor = false;

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
                    subtitle: 'Extra verification step when signing in',
                    value: _twoFactor,
                    onChanged: (v) => setState(() => _twoFactor = v),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

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
