import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import '../widgets/detail_header.dart';

List<({IconData icon, Color color, String title, String subtitle, String time})>
_todayNotifications() => [
  (
    icon: Icons.wb_cloudy_rounded,
    color: const Color(0xFF2E9CCA),
    title: tr('auth_notif_rain_title'),
    subtitle: tr('auth_notif_rain_subtitle'),
    time: '1${tr('auth_hours_ago_suffix')}',
  ),
  (
    icon: Icons.favorite_rounded,
    color: const Color(0xFFFF7A59),
    title: tr('auth_notif_liked_review_title'),
    subtitle: tr('auth_notif_liked_review_subtitle'),
    time: '3${tr('auth_hours_ago_suffix')}',
  ),
];

List<({IconData icon, Color color, String title, String subtitle, String time})>
_earlierNotifications() => [
  (
    icon: Icons.event_available_rounded,
    color: const Color(0xFF11998E),
    title: tr('auth_notif_trip_reminder_title'),
    subtitle: tr('auth_notif_trip_reminder_subtitle'),
    time: tr('auth_yesterday_word'),
  ),
  (
    icon: Icons.mode_comment_rounded,
    color: const Color(0xFF5C6BC0),
    title: tr('auth_notif_new_comment_title'),
    subtitle: tr('auth_notif_new_comment_subtitle'),
    time: '2 ${tr('auth_days_ago_words_suffix')}',
  ),
  (
    icon: Icons.local_offer_rounded,
    color: const Color(0xFFFFB347),
    title: tr('auth_notif_budget_alert_title'),
    subtitle: tr('auth_notif_budget_alert_subtitle'),
    time: '3 ${tr('auth_days_ago_words_suffix')}',
  ),
];

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: tr('auth_notifications')),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _GroupLabel(tr('weather_day_today')),
                  ..._todayNotifications().map(
                    (n) => _NotificationTile(
                      icon: n.icon,
                      color: n.color,
                      title: n.title,
                      subtitle: n.subtitle,
                      time: n.time,
                    ),
                  ),
                  SizedBox(height: 12),
                  _GroupLabel(tr('auth_earlier_word')),
                  ..._earlierNotifications().map(
                    (n) => _NotificationTile(
                      icon: n.icon,
                      color: n.color,
                      title: n.title,
                      subtitle: n.subtitle,
                      time: n.time,
                    ),
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

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

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.time,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: color, size: 19),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
                SizedBox(height: 5),
                Text(
                  time,
                  style: TextStyle(
                    color: context.colors.muted.withValues(alpha: 0.7),
                    fontSize: 10.5,
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
