import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'start_navigation_screen.dart';
import 'transport_routes_screen.dart';

/// Full walk → wait → ride → alight instructions for one chosen bus
/// departure.
class RouteDetailsScreen extends StatelessWidget {
  const RouteDetailsScreen({super.key, required this.departure});

  final BusDeparture departure;

  @override
  Widget build(BuildContext context) {
    final d = departure;
    final steps = [
      (
        title: 'Walk to ${d.nearestStop}',
        detail: 'About ${d.walkToStopMinutes} min on foot from your current location.',
        icon: Icons.directions_walk_rounded,
      ),
      (
        title: 'Wait for Bus ${d.busNumber}',
        detail: 'Arrives in approximately ${d.waitMinutes} min — keep an eye out for the number.',
        icon: Icons.schedule_rounded,
      ),
      (
        title: 'Board Bus ${d.busNumber}',
        detail: 'Ride for about ${d.rideMinutes} min. Fare is ${d.fare}.',
        icon: Icons.directions_bus_filled_rounded,
      ),
      (
        title: 'Alight at ${d.destinationStop}',
        detail: 'Walk about ${d.walkFromStopMinutes} min to reach ${d.destinationName}.',
        icon: Icons.flag_rounded,
      ),
    ];

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Trip Directions',
              subtitle: 'Bus ${d.busNumber} to ${d.destinationName}',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(20),
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
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: d.color.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            d.busNumber,
                            style: TextStyle(
                              color: d.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'To ${d.destinationName}',
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14.5,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${d.totalMinutes} min total · ${d.fare}',
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Directions',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(steps.length, (index) {
                    final isLast = index == steps.length - 1;
                    final step = steps[index];
                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: d.color.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Icon(step.icon, color: d.color, size: 17),
                              ),
                              if (!isLast)
                                Expanded(
                                  child: Container(
                                    width: 2,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    color: context.colors.muted.withValues(
                                      alpha: 0.2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                bottom: isLast ? 0 : 22,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    style: TextStyle(
                                      color: context.colors.ink,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    step.detail,
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontSize: 12.5,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  GradientButton(
                    label: 'Start Navigation',
                    icon: Icons.navigation_rounded,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => StartNavigationScreen(departure: d),
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
