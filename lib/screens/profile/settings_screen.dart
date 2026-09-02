import 'package:flutter/material.dart';

import '../../l10n/app_language.dart';
import '../../services/auth_service.dart';
import '../../services/fcm_service.dart';
import '../../services/locale_service.dart';
import '../../services/notification_prefs_service.dart';
import '../../services/push_notifications.dart';
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
  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  Future<void> _togglePush(bool value) async {
    if (!value) {
      await NotificationPrefsService.instance.setPushEnabled(false);
      return;
    }
    final token = await FcmService.instance.enable();
    if (token == null) {
      if (mounted) _showMessage(tr('auth_push_permission_denied'));
      return;
    }
    debugPrint('FCM token: $token');
    await NotificationPrefsService.instance.setPushEnabled(true, fcmToken: token);
    showLocalNotification(tr('auth_push_enabled_title'), tr('auth_push_enabled_body'));
  }

  Future<void> _toggleTripReminders(bool value) async {
    await NotificationPrefsService.instance.setTripRemindersEnabled(value);
    if (value) {
      showLocalNotification(tr('auth_trip_reminders_enabled_title'), tr('auth_trip_reminders_enabled_body'));
    }
  }

  Future<void> _toggleEmailUpdates(bool value) async {
    await NotificationPrefsService.instance.setEmailUpdatesEnabled(value);
    _showMessage(value ? tr('auth_email_updates_on') : tr('auth_email_updates_off'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: tr('auth_settings_title')),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _SectionLabel(tr('auth_notifications')),
                  ValueListenableBuilder<NotificationPrefs>(
                    valueListenable: NotificationPrefsService.instance.current,
                    builder: (context, prefs, _) {
                      final pushOn = prefs.pushEnabled && !pushPermissionDenied;
                      return Column(
                        children: [
                          _SwitchCard(
                            icon: Icons.notifications_none_rounded,
                            title: tr('auth_push_notifications'),
                            value: pushOn,
                            onChanged: _togglePush,
                          ),
                          _SwitchCard(
                            icon: Icons.event_available_rounded,
                            title: tr('auth_trip_reminders'),
                            value: pushOn && prefs.tripRemindersEnabled,
                            onChanged: pushOn ? _toggleTripReminders : null,
                          ),
                          _SwitchCard(
                            icon: Icons.email_outlined,
                            title: tr('auth_email_updates'),
                            value: prefs.emailUpdatesEnabled,
                            onChanged: _toggleEmailUpdates,
                          ),
                        ],
                      );
                    },
                  ),
                  SizedBox(height: 20),
                  _SectionLabel(tr('auth_appearance')),
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeModeNotifier,
                    builder: (context, mode, _) {
                      return _SwitchCard(
                        icon: Icons.dark_mode_outlined,
                        title: tr('auth_dark_mode'),
                        value: mode == ThemeMode.dark,
                        onChanged: (v) => themeModeNotifier.value = v
                            ? ThemeMode.dark
                            : ThemeMode.light,
                      );
                    },
                  ),
                  ValueListenableBuilder<String>(
                    valueListenable: currentLanguageCode,
                    builder: (context, code, _) {
                      return ListTileCard(
                        icon: Icons.language_rounded,
                        title: tr('auth_language'),
                        subtitle: languageByCode(code).nativeName,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LanguageScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                  SizedBox(height: 20),
                  _SectionLabel(tr('auth_account')),
                  ListTileCard(
                    icon: Icons.person_outline_rounded,
                    title: tr('auth_edit_profile'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.lock_outline_rounded,
                    title: tr('auth_change_password_title'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.privacy_tip_outlined,
                    title: tr('auth_privacy_security'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrivacySecurityScreen(),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  _SectionLabel(tr('auth_support')),
                  ListTileCard(
                    icon: Icons.help_outline_rounded,
                    title: tr('auth_help_center'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
                    ),
                  ),
                  ListTileCard(
                    icon: Icons.info_outline_rounded,
                    title: tr('auth_about'),
                    subtitle: 'Version 1.0.0',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AboutScreen()),
                    ),
                  ),
                  SizedBox(height: 20),
                  ListTileCard(
                    icon: Icons.logout_rounded,
                    title: tr('auth_sign_out'),
                    iconColor: Colors.redAccent,
                    trailing: SizedBox.shrink(),
                    onTap: () async {
                      await AuthService.instance.signOut();
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
  final ValueChanged<bool>? onChanged;

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
