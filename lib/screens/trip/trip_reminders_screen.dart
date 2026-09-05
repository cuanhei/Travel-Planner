import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../services/locale_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/trip_reminder_support.dart';
import 'trip_details_screen.dart';

class TripRemindersScreen extends StatelessWidget {
  const TripRemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: tr('home_reminders_title')),
            Expanded(
              child: StreamBuilder<List<Trip>>(
                stream: TripService().watchMyTrips(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      !snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final reminders = tripsNeedingReminder(
                    snapshot.data ?? const <Trip>[],
                  );
                  if (reminders.isEmpty) return const _EmptyReminders();
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    itemCount: reminders.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final trip = reminders[i];
                      return TripReminderCard(
                        message: tripReminderMessage(trip),
                        ongoing: trip.status == TripStatus.current,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TripDetailsScreen(trip: trip),
                          ),
                        ),
                      );
                    },
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

class _EmptyReminders extends StatelessWidget {
  const _EmptyReminders();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_off_rounded,
              color: context.colors.muted,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              tr('home_reminders_empty_title'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('home_reminders_empty_body'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
