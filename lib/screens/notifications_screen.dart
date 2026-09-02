import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/detail_header.dart';

/// Alerts and reminders feed: trip updates, weather alerts, and social
/// notifications grouped by recency.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  static final _today = [
    (
      icon: Icons.wb_cloudy_rounded,
      color: Color(0xFF2E9CCA),
      title: 'Rain expected in Penang tomorrow',
      subtitle: 'Pack an umbrella for your Gurney Drive stop',
      time: '1h ago',
    ),
    (
      icon: Icons.favorite_rounded,
      color: Color(0xFFFF7A59),
      title: 'Mei Ling liked your review',
      subtitle: 'Your review of Chew Jetty',
      time: '3h ago',
    ),
  ];

  static final _earlier = [
    (
      icon: Icons.event_available_rounded,
      color: Color(0xFF11998E),
      title: 'Trip reminder: Penang Adventure',
      subtitle: 'Your trip starts in 3 days',
      time: 'Yesterday',
    ),
    (
      icon: Icons.mode_comment_rounded,
      color: Color(0xFF5C6BC0),
      title: 'New comment on your post',
      subtitle: 'Arif Hakim commented on Gurney Drive Hawker Centre',
      time: '2 days ago',
    ),
    (
      icon: Icons.local_offer_rounded,
      color: Color(0xFFFFB347),
      title: 'Budget alert',
      subtitle: 'You\'ve used 70% of your Penang trip budget',
      time: '3 days ago',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Notifications'),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _GroupLabel('Today'),
                  ..._today.map(
                    (n) => _NotificationTile(
                      icon: n.icon,
                      color: n.color,
                      title: n.title,
                      subtitle: n.subtitle,
                      time: n.time,
                    ),
                  ),
                  SizedBox(height: 12),
                  _GroupLabel('Earlier'),
                  ..._earlier.map(
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
