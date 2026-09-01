import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Active and past weather alerts (rain, storm, heat) for the trip area.
class WeatherAlertScreen extends StatelessWidget {
  const WeatherAlertScreen({super.key});

  static List<
    ({
      String severity,
      Color color,
      IconData icon,
      String title,
      String description,
      String time,
    })
  >
  _alerts(BuildContext context) => [
    (
      severity: 'Active',
      color: Color(0xFF2E9CCA),
      icon: Icons.grain_rounded,
      title: 'Heavy Rain Warning',
      description:
          'Heavy rain expected across George Town and Gurney Drive '
          'between 3 PM and 7 PM today. Consider indoor activities.',
      time: 'Today, 3:00 PM',
    ),
    (
      severity: 'Advisory',
      color: Color(0xFFFFB347),
      icon: Icons.wb_sunny_rounded,
      title: 'High UV Index',
      description:
          'UV index expected to reach 10 (very high) around midday. '
          'Wear sunscreen and stay hydrated.',
      time: 'Today, 12:00 PM',
    ),
    (
      severity: 'Past',
      color: context.colors.muted,
      icon: Icons.thunderstorm_rounded,
      title: 'Thunderstorm Alert',
      description:
          'Isolated thunderstorms passed through the area last evening.',
      time: 'Yesterday, 6:30 PM',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final alerts = _alerts(context);
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Weather Alerts',
              subtitle: 'Rain, storm, and heat advisories',
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                itemCount: alerts.length,
                itemBuilder: (context, index) {
                  final a = alerts[index];
                  return Container(
                    margin: EdgeInsets.only(bottom: 14),
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: a.color.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: a.color.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(a.icon, color: a.color, size: 20),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                a.title,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: a.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                a.severity,
                                style: TextStyle(
                                  color: a.color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 10),
                        Text(
                          a.description,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          a.time,
                          style: TextStyle(
                            color: a.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
