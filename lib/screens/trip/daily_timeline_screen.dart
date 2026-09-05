import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../models/trip_schedule_entry.dart';
import '../../models/trip_stop_location.dart' show iconForCategory;
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../transport/transport_routes_screen.dart';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. "Aug 14".
String _formatShortDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

/// "14:05:00" (Postgres `time`) → "2:05 PM"; null through unchanged.
String? _formatTimeString(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  final period = hour >= 12 ? 'PM' : 'AM';
  final displayHour = hour % 12 == 0 ? 12 : hour % 12;
  return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
}

IconData _iconForTravelMode(String? mode) => switch (mode) {
  'drive' => Icons.directions_car_filled_rounded,
  'walk' => Icons.directions_walk_rounded,
  'transit' => Icons.directions_bus_filled_rounded,
  _ => Icons.alt_route_rounded,
};

String _labelForTravelMode(String? mode) => switch (mode) {
  'drive' => 'Driving',
  'walk' => 'Walking',
  'transit' => 'Public transport',
  _ => 'Getting there',
};

/// A node in a day's timeline — either a stop ([_Activity]) or the
/// travel between two stops ([_Transport]).
abstract class _TimelineEntry {}

class _Activity extends _TimelineEntry {
  _Activity(this.time, this.title, this.subtitle, this.icon);

  final String time;
  final String title;
  final String subtitle;
  final IconData icon;

  /// Purely local/session state — there's no "completed" column on
  /// `trip_schedule_stops`, so this (like the similar tracker on Trip
  /// Details' Activity feed) resets the next time this screen opens.
  bool completed = false;
}

class _Transport extends _TimelineEntry {
  _Transport(this.minutes, this.mode);

  final int minutes;
  final String? mode;
}

/// Real, saved day-by-day schedule for a trip — everything
/// [DayScheduleService] worked out at planning time (stop order, real
/// travel minutes, opening-hours-aware arrival/departure times) and
/// [TripService.saveTripSchedule] persisted to `trip_schedule_stops`,
/// read back and displayed one day at a time.
class DailyTimelineScreen extends StatefulWidget {
  const DailyTimelineScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<DailyTimelineScreen> createState() => _DailyTimelineScreenState();
}

class _DailyTimelineScreenState extends State<DailyTimelineScreen> {
  final _tripService = TripService();
  late final Future<List<TripScheduleEntry>> _scheduleFuture = _tripService
      .getTripSchedule(widget.trip.id);

  int _selectedDay = 1;

  /// The first not-yet-completed stop in [items] — only this one gets a
  /// "Complete" button, so the traveler works through the day in order.
  _Activity? _firstUndone(List<_TimelineEntry> items) {
    for (final item in items) {
      if (item is _Activity && !item.completed) return item;
    }
    return null;
  }

  List<_TimelineEntry> _entriesForDay(List<TripScheduleEntry> dayEntries) {
    final entries = <_TimelineEntry>[];
    for (final entry in dayEntries) {
      if (entry.travelMinutes != null) {
        entries.add(_Transport(entry.travelMinutes!, entry.travelMode));
      }
      final time =
          _formatTimeString(entry.scheduledArrival) ??
          _formatTimeString(entry.scheduledDeparture) ??
          '';
      entries.add(
        _Activity(
          time,
          entry.stopName,
          entry.isHotel ? 'Accommodation' : entry.stopAddress,
          entry.isHotel ? Icons.hotel_rounded : iconForCategory(entry.category),
        ),
      );
    }
    return entries;
  }

  String? _dateLabelFor(int dayNumber) {
    final start = widget.trip.startDate;
    if (start == null) return null;
    return _formatShortDate(start.add(Duration(days: dayNumber - 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Daily Timeline',
              subtitle: 'Your day-by-day schedule',
            ),
            Expanded(
              child: FutureBuilder<List<TripScheduleEntry>>(
                future: _scheduleFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load the schedule: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }

                  final byDay = <int, List<TripScheduleEntry>>{};
                  for (final entry in snapshot.data ?? const []) {
                    byDay.putIfAbsent(entry.dayNumber, () => []).add(entry);
                  }
                  final dayNumbers = byDay.keys.toList()..sort();

                  if (dayNumbers.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          "This trip doesn't have a saved schedule yet.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ),
                    );
                  }

                  if (!dayNumbers.contains(_selectedDay)) {
                    _selectedDay = dayNumbers.first;
                  }
                  final items = _entriesForDay(byDay[_selectedDay]!);

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          children: [
                            for (final dayNumber in dayNumbers)
                              Expanded(
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedDay = dayNumber),
                                  child: Container(
                                    margin: EdgeInsets.only(
                                      right: dayNumber == dayNumbers.last
                                          ? 0
                                          : 10,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: dayNumber == _selectedDay
                                          ? context.colors.ink
                                          : context.colors.card,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          'Day $dayNumber',
                                          style: TextStyle(
                                            color: dayNumber == _selectedDay
                                                ? Colors.white
                                                : context.colors.ink,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        if (_dateLabelFor(dayNumber) !=
                                            null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            _dateLabelFor(dayNumber)!,
                                            style: TextStyle(
                                              color: dayNumber == _selectedDay
                                                  ? Colors.white70
                                                  : context.colors.muted,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            final isLast = index == items.length - 1;
                            if (item is _Activity) {
                              return _ActivityRow(
                                activity: item,
                                isLast: isLast,
                                showCompleteButton: identical(
                                  item,
                                  _firstUndone(items),
                                ),
                                onComplete: () =>
                                    setState(() => item.completed = true),
                              );
                            }
                            return _TransportRow(
                              transport: item as _Transport,
                              isLast: isLast,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TransportRoutesScreen(
                                    tripId: widget.trip.id,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
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

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.leading,
    required this.content,
    required this.isLast,
  });

  final Widget leading;
  final Widget content;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              leading,
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: context.colors.muted.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.activity,
    required this.isLast,
    required this.showCompleteButton,
    required this.onComplete,
  });

  final _Activity activity;
  final bool isLast;
  final bool showCompleteButton;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    const done = Color(0xFF11998E);
    return _TimelineRow(
      isLast: isLast,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: activity.completed
              ? done.withValues(alpha: 0.15)
              : AppColors.accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          activity.completed ? Icons.check_rounded : activity.icon,
          color: activity.completed ? done : AppColors.accent,
          size: 18,
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                activity.time,
                style: TextStyle(
                  color: activity.completed ? context.colors.muted : AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
              if (activity.completed) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: done.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: done,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            activity.title,
            style: TextStyle(
              color: activity.completed
                  ? context.colors.muted
                  : context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            activity.subtitle,
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
          if (showCompleteButton) ...[
            const SizedBox(height: 10),
            Material(
              color: context.colors.ink,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onComplete,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, color: Colors.white, size: 15),
                      SizedBox(width: 6),
                      Text(
                        'Complete',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows the real travel time/mode already computed at planning time —
/// tapping opens Transport for live public-transport alternatives for
/// this trip, since the schedule itself only ever records driving time
/// (see `TripService.saveTripSchedule`).
class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.transport,
    required this.isLast,
    required this.onTap,
  });

  final _Transport transport;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.accent;
    return _TimelineRow(
      isLast: isLast,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Icon(
          _iconForTravelMode(transport.mode),
          color: color,
          size: 15,
        ),
      ),
      content: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '~${transport.minutes} min',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _labelForTravelMode(transport.mode),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
