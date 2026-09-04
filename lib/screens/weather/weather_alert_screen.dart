import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
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
      severity: tr('weather_severity_active'),
      color: Color(0xFF2E9CCA),
      icon: Icons.grain_rounded,
      title: tr('weather_alert_rain_title'),
      description: tr('weather_alert_rain_desc'),
      time: tr('weather_alert_rain_time'),
    ),
    (
      severity: tr('weather_severity_advisory'),
      color: Color(0xFFFFB347),
      icon: Icons.wb_sunny_rounded,
      title: tr('weather_alert_uv_title'),
      description: tr('weather_alert_uv_desc'),
      time: tr('weather_alert_uv_time'),
    ),
    (
      severity: tr('weather_severity_past'),
      color: context.colors.muted,
      icon: Icons.thunderstorm_rounded,
      title: tr('weather_alert_storm_title'),
      description: tr('weather_alert_storm_desc'),
      time: tr('weather_alert_storm_time'),
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
              title: tr('weather_alert_title'),
              subtitle: tr('weather_alert_subtitle'),
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
