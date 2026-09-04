import 'package:flutter/material.dart';

import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/detail_header.dart';
import '../transport/transport_routes_screen.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Parses `trip_schedule_stops.scheduled_arrival`'s Postgres `time`
/// string (`"HH:mm:ss"`) into a [DateTime] carrying just that
/// time-of-day, for use with [formatClockTime] — null if unparseable.
DateTime? _parseTimeOfDay(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(2000, 1, 1, hour, minute);
}

/// How the traveler gets from one timeline stop to the next.
enum _TransportMode { undecided, publicTransport, eHailing, walk }

extension on _TransportMode {
  String get label => switch (this) {
    _TransportMode.undecided => 'Choose transport',
    _TransportMode.publicTransport => 'Public transport',
    _TransportMode.eHailing => 'E-hailing',
    _TransportMode.walk => 'Walking',
  };

  IconData get icon => switch (this) {
    _TransportMode.undecided => Icons.alt_route_rounded,
    _TransportMode.publicTransport => Icons.directions_bus_filled_rounded,
    _TransportMode.eHailing => Icons.local_taxi_rounded,
    _TransportMode.walk => Icons.directions_walk_rounded,
  };

  Color get color => switch (this) {
    _TransportMode.undecided => const Color(0xFF6E7A93),
    _TransportMode.publicTransport => const Color(0xFF5C6BC0),
    _TransportMode.eHailing => AppColors.accent,
    _TransportMode.walk => const Color(0xFF11998E),
  };
}

_TransportMode _modeFromTravelMode(String? raw) => switch (raw) {
  'public_transport' => _TransportMode.publicTransport,
  'walk' => _TransportMode.walk,
  'drive' => _TransportMode.eHailing,
  _ => _TransportMode.undecided,
};

/// A node in a day's timeline — either a stop ([_ActivityEntry]) or the
/// commute between two stops ([_TransportEntry]).
abstract class _TimelineEntry {}

class _AnchorEntry extends _TimelineEntry {
  _AnchorEntry(this.label);
  final String label;
}

class _ActivityEntry extends _TimelineEntry {
  _ActivityEntry(this.row);

  final TripScheduleRow row;
  bool completed = false;
}

class _TransportEntry extends _TimelineEntry {
  _TransportEntry(
    this.estimatedMinutes, {
    this.mode = _TransportMode.undecided,
  });

  final int estimatedMinutes;
  _TransportMode mode;
}

typedef _DayGroup = ({
  int dayNumber,
  DateTime? date,
  List<_TimelineEntry> items,
});

/// Vertical timeline of each day's activities for the trip, backed by
/// the real AI-Planner-generated schedule (`trip_schedule_stops`) —
/// replaces the old hardcoded 3-day Penang itinerary. The commute
/// between stops is still shown as its own tappable step where the
/// traveler picks public transport/e-hailing/walking (spec doesn't yet
/// have a per-leg mode decided by the engine — see
/// `TripSchedulerService._persistSchedule` — so this stays an
/// interactive, *local-only* choice, same as the "Complete" checkmark
/// below: neither is persisted back to `trip_schedule_stops` yet).
class DailyTimelineScreen extends StatefulWidget {
  const DailyTimelineScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<DailyTimelineScreen> createState() => _DailyTimelineScreenState();
}

class _DailyTimelineScreenState extends State<DailyTimelineScreen> {
  final _tripService = TripService();

  bool _loading = true;
  String? _error;
  List<_DayGroup> _days = const [];
  int _day = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trip = await _tripService.getTrip(widget.tripId);
      final schedule = await _tripService.getSchedule(widget.tripId);
      final dayRows = await _tripService.getScheduleDays(widget.tripId);
      final metadata = {for (final d in dayRows) d['day_number'] as int: d};

      final byDay = <int, List<TripScheduleRow>>{};
      for (final row in schedule) {
        byDay.putIfAbsent(row.dayNumber, () => []).add(row);
      }
      final dayCount = trip.startDate != null && trip.endDate != null
          ? trip.endDate!.difference(trip.startDate!).inDays + 1
          : 0;
      final dayNumbers = {
        ...byDay.keys,
        for (var n = 1; n <= dayCount; n++) n,
      }.toList()..sort();
      final days = [
        for (final dayNumber in dayNumbers)
          (
            dayNumber: dayNumber,
            date: trip.startDate?.add(Duration(days: dayNumber - 1)),
            items: _entriesFor(
              byDay[dayNumber] ?? [],
              metadata[dayNumber],
              trip.transportMode,
            ),
          ),
      ];
      if (!mounted) return;
      setState(() {
        _days = days;
        _day = 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load your itinerary. Check your connection and try again.';
      });
    }
  }

  /// Interleaves each stop with the travel leg *into* it (spec's
  /// per-visit `travelMinutes` already represents that leg — see
  /// `ScheduledVisit.travelFromPrevious` in day_ordering.dart) — the
  /// first visit also includes travel from its overnight/start anchor.
  List<_TimelineEntry> _entriesFor(
    List<TripScheduleRow> rows,
    Map<String, dynamic>? day,
    String? travelMode,
  ) {
    final start = day?['start_stop'] as Map<String, dynamic>?;
    final end = day?['end_stop'] as Map<String, dynamic>?;
    final entries = <_TimelineEntry>[
      if (start != null) _AnchorEntry('Start: ${start['name']}'),
      if (rows.isEmpty) _AnchorEntry('No stops scheduled this day.'),
    ];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0 || (rows[i].travelMinutes ?? 0) > 0) {
        entries.add(
          _TransportEntry(
            rows[i].travelMinutes ?? 0,
            mode: _modeFromTravelMode(rows[i].travelMode),
          ),
        );
      }
      entries.add(_ActivityEntry(rows[i]));
    }
    if (end != null) {
      final minutes = day?['return_travel_minutes'] as int?;
      if (minutes != null && day?['end_anchor_reachable'] == true) {
        entries.add(
          _TransportEntry(minutes, mode: _modeFromTravelMode(travelMode)),
        );
      }
      entries.add(
        _AnchorEntry(
          day?['end_anchor_reachable'] == false
              ? 'Route to ${end['name']} could not fit this day.'
              : 'End: ${end['name']}',
        ),
      );
    }
    return entries;
  }

  Future<void> _pickTransportMode(_TransportEntry transport) async {
    final selected = await showModalBottomSheet<_TransportMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransportModeSheet(current: transport.mode),
    );
    if (selected == null) return;
    setState(() => transport.mode = selected);
    if (selected == _TransportMode.publicTransport && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TransportRoutesScreen(tripId: widget.tripId),
        ),
      );
    }
  }

  void _completeActivity(_ActivityEntry activity) {
    setState(() => activity.completed = true);
  }

  /// The first not-yet-completed stop in [items] — only this one gets a
  /// "Complete" button, so the traveler works through the day in order.
  _ActivityEntry? _firstUndone(List<_TimelineEntry> items) {
    for (final item in items) {
      if (item is _ActivityEntry && !item.completed) return item;
    }
    return null;
  }

  String _dayLabel(_DayGroup day) => 'Day ${day.dayNumber}';

  String _dateLabel(_DayGroup day) {
    final date = day.date;
    if (date == null) return '';
    return '${_monthNames[date.month - 1]} ${date.day}';
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
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: context.colors.muted,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_days.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No itinerary generated yet — this trip may not have travel '
            'dates set, or the AI Planner hasn\'t run for it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 13),
          ),
        ),
      );
    }

    final day = _days[_day];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: List.generate(_days.length, (i) {
              final active = i == _day;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _day = i),
                  child: Container(
                    margin: EdgeInsets.only(
                      right: i < _days.length - 1 ? 10 : 0,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active ? context.colors.ink : context.colors.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _dayLabel(_days[i]),
                          style: TextStyle(
                            color: active ? Colors.white : context.colors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dateLabel(_days[i]),
                          style: TextStyle(
                            color: active
                                ? Colors.white70
                                : context.colors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: day.items.isEmpty
              ? Center(
                  child: Text(
                    'No stops scheduled this day.',
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  itemCount: day.items.length,
                  itemBuilder: (context, index) {
                    final item = day.items[index];
                    final isLast = index == day.items.length - 1;
                    if (item is _ActivityEntry) {
                      return _ActivityRow(
                        activity: item,
                        isLast: isLast,
                        showCompleteButton: identical(
                          item,
                          _firstUndone(day.items),
                        ),
                        onComplete: () => _completeActivity(item),
                      );
                    }
                    if (item is _AnchorEntry) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          item.label,
                          style: TextStyle(color: context.colors.muted),
                        ),
                      );
                    }
                    final transport = item as _TransportEntry;
                    return _TransportRow(
                      transport: transport,
                      isLast: isLast,
                      onTap: () => _pickTransportMode(transport),
                    );
                  },
                ),
        ),
      ],
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

  final _ActivityEntry activity;
  final bool isLast;
  final bool showCompleteButton;
  final VoidCallback onComplete;

  String get _timeLabel {
    final time = _parseTimeOfDay(
      activity.row.scheduledVisitStart ?? activity.row.scheduledArrival,
    );
    return time == null
        ? 'Day ${activity.row.dayNumber}'
        : formatClockTime(time);
  }

  @override
  Widget build(BuildContext context) {
    const done = Color(0xFF11998E);
    final stop = activity.row.stop;
    final completed = activity.completed;
    return _TimelineRow(
      isLast: isLast,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: completed
              ? done.withValues(alpha: 0.15)
              : AppColors.accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          completed ? Icons.check_rounded : stop.categoryIcon,
          color: completed ? done : AppColors.accent,
          size: 18,
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _timeLabel,
                style: TextStyle(
                  color: completed ? context.colors.muted : AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
              if (completed) ...[
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
            stop.name,
            style: TextStyle(
              color: completed ? context.colors.muted : context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stop.address,
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

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.transport,
    required this.isLast,
    required this.onTap,
  });

  final _TransportEntry transport;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mode = transport.mode;
    return _TimelineRow(
      isLast: isLast,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: mode.color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: mode.color.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Icon(mode.icon, color: mode.color, size: 15),
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
                        transport.estimatedMinutes <= 0
                            ? 'Nearby'
                            : '~${transport.estimatedMinutes} min transport',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode.label,
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

class _TransportModeSheet extends StatelessWidget {
  const _TransportModeSheet({required this.current});

  final _TransportMode current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How do you want to get there?',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how to travel to the next stop',
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            _ModeOption(
              mode: _TransportMode.publicTransport,
              description: 'See live bus options and directions',
              selected: current == _TransportMode.publicTransport,
              onTap: () =>
                  Navigator.of(context).pop(_TransportMode.publicTransport),
            ),
            const SizedBox(height: 10),
            _ModeOption(
              mode: _TransportMode.eHailing,
              description: 'Book a Grab or taxi ride',
              selected: current == _TransportMode.eHailing,
              onTap: () => Navigator.of(context).pop(_TransportMode.eHailing),
            ),
            const SizedBox(height: 10),
            _ModeOption(
              mode: _TransportMode.walk,
              description: 'Free, and a good stretch of the legs',
              selected: current == _TransportMode.walk,
              onTap: () => Navigator.of(context).pop(_TransportMode.walk),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final _TransportMode mode;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? mode.color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(mode.icon, color: mode.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
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
    );
  }
}
