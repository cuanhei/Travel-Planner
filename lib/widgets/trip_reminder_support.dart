import 'package:flutter/material.dart';

import '../models/trip.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

const int kTripReminderWindowDays = 3;

List<Trip> tripsNeedingReminder(List<Trip> trips) {
  final ongoing = trips.where((t) => t.status == TripStatus.current).toList();
  final upcoming = trips.where((t) {
    final days = t.daysUntilStart;
    return t.status == TripStatus.upcoming &&
        days != null &&
        days >= 0 &&
        days <= kTripReminderWindowDays;
  }).toList()..sort((a, b) => a.daysUntilStart!.compareTo(b.daysUntilStart!));
  return [...ongoing, ...upcoming];
}

String tripReminderMessage(Trip trip) {
  final place = trip.destination.isEmpty ? trip.name : trip.destination;
  String template;
  if (trip.status == TripStatus.current) {
    template = tr('home_reminder_ongoing');
  } else {
    final days = trip.daysUntilStart ?? 0;
    template = switch (days) {
      0 => tr('home_reminder_today'),
      1 => tr('home_reminder_tomorrow'),
      _ => tr('home_reminder_days'),
    };
  }
  return template
      .replaceAll('{place}', place)
      .replaceAll('{days}', '${trip.daysUntilStart ?? 0}');
}

class TripReminderCard extends StatelessWidget {
  const TripReminderCard({
    super.key,
    required this.message,
    required this.ongoing,
    required this.onTap,
    this.moreCount = 0,
  });

  final String message;
  final bool ongoing;
  final VoidCallback onTap;

  final int moreCount;

  @override
  Widget build(BuildContext context) {
    final color = ongoing ? const Color(0xFF11998E) : const Color(0xFFFF7A59);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  ongoing
                      ? Icons.flight_takeoff_rounded
                      : Icons.notifications_active_rounded,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (moreCount > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '+$moreCount',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(Icons.chevron_right_rounded, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
