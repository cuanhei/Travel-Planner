import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/list_tile_card.dart';
import '../welcome_screen.dart';
import 'about_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'help_center_screen.dart';
import 'language_screen.dart';
import 'privacy_security_screen.dart';

/// App preferences: notifications, language, account, and sign out.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _tripReminders = true;
  bool _emailUpdates = false;
  String _language = 'English';

  Future<void> _pickLanguage() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => LanguageScreen(current: _language),
      ),
    );
    if (result != null) setState(() => _language = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Settings'),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _SectionLabel('Notifications'),
                  _SwitchCard(
                    icon: Icons.notifications_none_rounded,
                    title: 'Push Notifications',
                    value: _pushNotifications,
                    onChanged: (v) => setState(() => _pushNotifications = v),
                  ),
                  _SwitchCard(
                    icon: Icons.event_available_rounded,
                    title: 'Trip Reminders',
                    value: _tripReminders,
                    onChanged: (v) => setState(() => _tripReminders = v),
                  ),
                  _SwitchCard(
                    icon: Icons.email_outlined,
                    title: 'Email Updates',
                    value: _emailUpdates,
                    onChanged: (v) => setState(() => _emailUpdates = v),
                  ),
                  SizedBox(height: 20),
                  _SectionLabel('Appearance'),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeModeNotifier,
                    builder: (context, mode, _) {
                      return _SwitchCard(
                        icon: Icons.dark_mode_outlined,
                        title: 'Dark Mode',
                        value: mode == ThemeMode.dark,
                        onChanged: (v) => themeModeNotifier.value = v
                            ? ThemeMode.dark
                            : ThemeMode.light,
                      );
                    },
                  ),
                  ListTileCard(
                    icon: Icons.language_rounded,
                    title: 'Language',
                    subtitle: _language,
                    onTap: _pickLanguage,
                  ),
                  SizedBox(height: 20),
                  _SectionLabel('Account'),
                  ListTileCard(
                    icon: Icons.person_outline_rounded,
                    title: 'Edit Profile',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Change Password',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy & Security',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacySecurityScreen(),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  _SectionLabel('Support'),
                  ListTileCard(
                    icon: Icons.help_outline_rounded,
                    title: 'Help Center',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.info_outline_rounded,
                    title: 'About TravelPlanner',
                    subtitle: 'Version 1.0.0',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                  ),
                  SizedBox(height: 20),
                  ListTileCard(
                    icon: Icons.logout_rounded,
                    title: 'Sign Out',
                    iconColor: Colors.redAccent,
                    trailing: SizedBox.shrink(),
                    onTap: () async {
                      await AuthService.instance.signOut();
                      TripService.resetCache();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => WelcomeScreen()),
                        (route) => false,
                      );
                    },
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
      padding: EdgeInsets.only(bottom: 10, left: 2),
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
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: Offset(0, 5),
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
          SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
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
