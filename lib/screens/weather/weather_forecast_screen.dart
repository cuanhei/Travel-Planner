import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'weather_alert_screen.dart';

/// Full weather forecast for the trip destination: current conditions,
/// hourly strip, and a 5-day outlook.
class WeatherForecastScreen extends StatelessWidget {
  const WeatherForecastScreen({super.key});

  static final _hourly = [
    (label: 'Now', icon: Icons.wb_sunny_rounded, temp: '31°'),
    (label: '1 PM', icon: Icons.wb_cloudy_rounded, temp: '30°'),
    (label: '3 PM', icon: Icons.cloud_rounded, temp: '29°'),
    (label: '5 PM', icon: Icons.grain_rounded, temp: '27°'),
    (label: '7 PM', icon: Icons.nights_stay_rounded, temp: '26°'),
    (label: '9 PM', icon: Icons.nights_stay_rounded, temp: '25°'),
  ];

  static final _daily = [
    (day: 'Today', icon: Icons.wb_sunny_rounded, high: '31°', low: '25°'),
    (day: 'Fri', icon: Icons.wb_cloudy_rounded, high: '30°', low: '25°'),
    (day: 'Sat', icon: Icons.grain_rounded, high: '28°', low: '24°'),
    (day: 'Sun', icon: Icons.thunderstorm_rounded, high: '27°', low: '24°'),
    (day: 'Mon', icon: Icons.wb_sunny_rounded, high: '31°', low: '25°'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: context.colors.ink,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Text(
                    'Weather Forecast',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => WeatherAlertScreen()),
                  ),
                  icon: Icon(
                    Icons.notifications_active_outlined,
                    color: context.colors.ink,
                    size: 22,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2E9CCA), Color(0xFF6DD5FA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF2E9CCA).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Penang, Malaysia',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 56),
                  SizedBox(height: 8),
                  Text(
                    '31°C',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Partly Cloudy',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _StatColumn(
                        icon: Icons.water_drop_rounded,
                        label: 'Humidity',
                        value: '78%',
                      ),
                      _StatColumn(
                        icon: Icons.air_rounded,
                        label: 'Wind',
                        value: '14 km/h',
                      ),
                      _StatColumn(
                        icon: Icons.wb_twilight_rounded,
                        label: 'UV Index',
                        value: 'High',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Hourly Forecast',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            SizedBox(height: 14),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _hourly.length,
                separatorBuilder: (_, _) => SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final h = _hourly[index];
                  return Container(
                    width: 66,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Text(
                          h.label,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11,
                          ),
                        ),
                        Icon(h.icon, color: Color(0xFF2E9CCA), size: 20),
                        Text(
                          h.temp,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 24),
            Text(
              '5-Day Outlook',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            SizedBox(height: 14),
            ..._daily.map(
              (d) => Container(
                margin: EdgeInsets.only(bottom: 10),
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: context.colors.ink.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        d.day,
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Icon(d.icon, color: Color(0xFF2E9CCA), size: 20),
                    Spacer(),
                    Text(
                      d.high,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      d.low,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 10.5)),
      ],
    );
  }
}
