import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

class FareCalculatorScreen extends StatefulWidget {
  const FareCalculatorScreen({super.key});

  @override
  State<FareCalculatorScreen> createState() => _FareCalculatorScreenState();
}

class _FareCalculatorScreenState extends State<FareCalculatorScreen> {
  double _distance = 8;
  bool _calculated = false;

  @override
  Widget build(BuildContext context) {
    final fares = [
      (
        mode: 'Rapid Penang Bus',
        icon: Icons.directions_bus_filled_rounded,
        color: Color(0xFF5C6BC0),
        fare: (1.2 + _distance * 0.15),
      ),
      (
        mode: 'E-hailing (Grab)',
        icon: Icons.local_taxi_rounded,
        color: AppColors.accent,
        fare: (3.5 + _distance * 1.6),
      ),
      (
        mode: 'Taxi',
        icon: Icons.local_taxi_rounded,
        color: Color(0xFFFFB347),
        fare: (3.0 + _distance * 2.0),
      ),
      (
        mode: 'Bicycle Rental',
        icon: Icons.directions_bike_rounded,
        color: Color(0xFF11998E),
        fare: 5.0,
      ),
    ];

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Fare Calculator',
              subtitle: 'Estimate transport cost',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Container(
                    padding: EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: context.colors.ink.withValues(alpha: 0.05),
                          blurRadius: 12,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Distance',
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Spacer(),
                            Text(
                              '${_distance.toStringAsFixed(1)} km',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _distance,
                          min: 1,
                          max: 30,
                          divisions: 58,
                          activeColor: context.colors.ink,
                          onChanged: (v) => setState(() {
                            _distance = v;
                            _calculated = false;
                          }),
                        ),
                        SizedBox(height: 8),
                        GradientButton(
                          label: 'Calculate Fares',
                          icon: Icons.calculate_rounded,
                          height: 48,
                          onPressed: () => setState(() => _calculated = true),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  if (_calculated) ...[
                    Text(
                      'Estimated Fares',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    SizedBox(height: 14),
                    ...fares.map(
                      (f) => Container(
                        margin: EdgeInsets.only(bottom: 10),
                        padding: EdgeInsets.all(14),
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
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: f.color.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(f.icon, color: f.color, size: 19),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                f.mode,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            Text(
                              'RM ${f.fare.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'Adjust distance and tap Calculate',
                          style: TextStyle(color: context.colors.muted),
                        ),
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
