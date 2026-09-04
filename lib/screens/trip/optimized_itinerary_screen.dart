import 'package:flutter/material.dart';

import '../../models/day_schedule.dart';
import '../../models/pending_trip_draft.dart';
import '../../models/trip_day.dart';
import '../../models/trip_stop_location.dart';
import '../../models/unscheduled_stop.dart';
import '../../services/day_schedule_service.dart';
import '../../services/gap_filling_service.dart';
import '../../services/geographic_assignment_service.dart';
import '../../services/itinerary_validation_service.dart';
import '../../services/trip_service.dart';
import '../../services/weather_adjustment_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

const _dayAnchorMonthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. "5 Sep 2026".
String _formatFullDate(DateTime d) =>
    '${d.day} ${_dayAnchorMonthNames[d.month - 1]} ${d.year}';

String _formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

/// e.g. "2:30 PM" (locale-aware, via [TimeOfDay.format]).
String _formatClock(BuildContext context, DateTime dt) =>
    TimeOfDay.fromDateTime(dt).format(context);

/// Review screen for the Create Trip flow — builds a real, feasible,
/// timed itinerary in three stages and shows the result day by day:
/// 1. [buildTripDays] — the day-by-day skeleton (start/end anchors:
///    the overall trip start/end on the first/last day, each night's
///    accommodation in between).
/// 2. [GeographicAssignmentService] — which of the traveler's picked
///    stops geographically belong on which day, by actual driving-time
///    detour, not just nearest hotel.
/// 3. [DayScheduleService] — for each day, the stop order and exact
///    arrival/visit/departure times that respect real opening hours,
///    with anything that couldn't fit any order left in
///    [DaySchedule.unscheduledStops] rather than dropped.
///
/// No simulated weather, category-based clustering, or guessed
/// transport legs anywhere in this — [_SaveTripButton] performs the
/// actual create-trip step: nothing from Create Trip is written to the
/// database until the traveler confirms here.
class OptimizedItineraryScreen extends StatefulWidget {
  const OptimizedItineraryScreen({
    super.key,
    required this.draft,
    this.tripName = '',
    this.description = '',
  });

  final String tripName;
  final String description;

  /// Everything Create Trip collected but hasn't written to the database
  /// yet — [_SaveTripButton] is what actually creates the trip, from
  /// here, once the traveler has reviewed this generated itinerary.
  final PendingTripDraft draft;

  @override
  State<OptimizedItineraryScreen> createState() =>
      _OptimizedItineraryScreenState();
}

class _OptimizedItineraryScreenState extends State<OptimizedItineraryScreen> {
  final _assignmentService = GeographicAssignmentService();
  final _scheduleService = DayScheduleService();
  final _weatherAdjustmentService = WeatherAdjustmentService();
  final _gapFillingService = GapFillingService();
  late final List<TripDay> _tripDays = buildTripDays(widget.draft);
  late final Future<List<DaySchedule>> _scheduleFuture = _computeSchedules();

  Future<List<DaySchedule>> _computeSchedules() async {
    if (_tripDays.isEmpty) return const [];

    var assignment = const <int, List<TripStopLocation>>{};
    if (widget.draft.stops.isNotEmpty) {
      final detours = await _assignmentService.computeDetours(
        days: _tripDays,
        places: widget.draft.stops,
      );
      assignment = _assignmentService.assignPlacesToDays(detours);
    }

    final baseSchedules = [
      for (final day in _tripDays)
        await _scheduleService.scheduleDay(
          day: day,
          stops: assignment[day.dayNumber] ?? const [],
          dayStart: widget.draft.startTime,
          dayEnd: widget.draft.endTime,
        ),
    ];

    final weatherAdjusted = await _weatherAdjustmentService.adjust(
      baseSchedules: baseSchedules,
      dayStart: widget.draft.startTime,
      dayEnd: widget.draft.endTime,
    );

    final gapFilled = await _gapFillingService.fillGaps(
      schedules: weatherAdjusted,
      dayStart: widget.draft.startTime,
    );

    final issues = validateItinerary(gapFilled);
    if (issues.isEmpty) {
      debugPrint('[ItineraryValidation] All checks passed.');
    } else {
      debugPrint('[ItineraryValidation] ${issues.length} issue(s) found:');
      for (final issue in issues) {
        debugPrint('[ItineraryValidation] - $issue');
      }
    }

    return gapFilled;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: widget.tripName.isEmpty
                  ? 'Optimized Itinerary'
                  : widget.tripName,
              subtitle: widget.description.isEmpty
                  ? 'Grouped by day, start to end'
                  : widget.description,
            ),
            Expanded(
              child: FutureBuilder<List<DaySchedule>>(
                future: _scheduleFuture,
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState != ConnectionState.done;
                  final schedules = snapshot.data ?? const [];
                  final unscheduled = [
                    for (final s in schedules) ...s.unscheduledStops,
                  ];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: [
                      Row(
                        children: [
                          _SummaryStat(
                            icon: Icons.flag_rounded,
                            label: 'Stops',
                            value: '${widget.draft.stops.length}',
                          ),
                          _SummaryStat(
                            icon: Icons.calendar_today_rounded,
                            label: 'Days',
                            value: '${_tripDays.length}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (_tripDays.isEmpty)
                        Text(
                          'Pick your travel dates and start/end locations '
                          'to see the day-by-day plan.',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 13,
                          ),
                        )
                      else if (loading)
                        for (final day in _tripDays)
                          _TripDayLoadingCard(day: day)
                      else ...[
                        for (final schedule in schedules)
                          _TripDaySection(schedule: schedule),
                        if (unscheduled.isNotEmpty)
                          _UnscheduledSection(entries: unscheduled),
                      ],
                      const SizedBox(height: 8),
                      _SaveTripButton(
                        tripName: widget.tripName,
                        description: widget.description,
                        draft: widget.draft,
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

/// "Save Trip" button — this is the actual create-trip step for the
/// whole Create Trip flow. Nothing is written to the database before
/// this point; tapping it inserts the `trips` row (plus one
/// `trip_accommodations` row per night) from [draft], then returns to
/// My Trips.
class _SaveTripButton extends StatefulWidget {
  const _SaveTripButton({
    required this.tripName,
    required this.description,
    required this.draft,
  });

  final String tripName;
  final String description;
  final PendingTripDraft draft;

  @override
  State<_SaveTripButton> createState() => _SaveTripButtonState();
}

class _SaveTripButtonState extends State<_SaveTripButton> {
  final _tripService = TripService();
  bool _saving = false;

  Future<void> _handleTap() async {
    setState(() => _saving = true);
    final draft = widget.draft;
    try {
      await _tripService.createTrip(
        name: widget.tripName,
        description: widget.description,
        destination: draft.endLocation?.name ?? draft.startLocation?.name,
        startLocationName: draft.startLocation?.name,
        startAddress: draft.startLocation?.address,
        startLatitude: draft.startLocation?.latitude,
        startLongitude: draft.startLocation?.longitude,
        endLocationName: draft.endLocation?.name,
        endAddress: draft.endLocation?.address,
        endLatitude: draft.endLocation?.latitude,
        endLongitude: draft.endLocation?.longitude,
        startDate: draft.dateRange?.start,
        endDate: draft.dateRange?.end,
        startTime: _formatTimeOfDay(draft.startTime),
        endTime: _formatTimeOfDay(draft.endTime),
        totalBudget: draft.totalBudget,
        accommodations: draft.accommodations,
      );
    } catch (e) {
      // Full exception (PostgrestException's message/code/details/hint)
      // printed to the console — the SnackBar alone can truncate or get
      // dismissed before it's readable.
      debugPrint('Create trip failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          content: Text('Could not save trip: $e'),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text(
          widget.tripName.isEmpty
              ? 'Trip saved to My Trips!'
              : '"${widget.tripName}" saved to My Trips!',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientButton(
      label: 'Save Trip',
      icon: Icons.bookmark_added_rounded,
      loading: _saving,
      onPressed: _saving ? () {} : _handleTap,
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: context.colors.ink.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.accent, size: 18),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: context.colors.muted, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Placeholder shown for each day while [DayScheduleService] is still
/// working — anchors only, same shell as [_TripDaySection] but no
/// timeline yet.
class _TripDayLoadingCard extends StatelessWidget {
  const _TripDayLoadingCard({required this.day});

  final TripDay day;

  @override
  Widget build(BuildContext context) {
    return _DayCardShell(
      day: day,
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Building this day\'s schedule…',
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// One day's card: start anchor, the timed stop-by-stop schedule
/// [DayScheduleService] built for it (real stop order, real travel
/// time, real opening hours — see [DaySchedule]), and the end anchor
/// with its actual arrival time.
class _TripDaySection extends StatelessWidget {
  const _TripDaySection({required this.schedule});

  final DaySchedule schedule;

  @override
  Widget build(BuildContext context) {
    final day = schedule.day;
    return _DayCardShell(
      day: day,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnchorLine(
            label: 'Start From',
            anchor: day.startAnchor,
            isHotel: !day.startIsOverallStart,
            time: _formatClock(context, _dayStart(day, schedule)),
          ),
          if (schedule.scheduledStops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No stops fit this day.',
                style: TextStyle(color: context.colors.muted, fontSize: 12),
              ),
            )
          else
            for (final scheduledStop in schedule.scheduledStops)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _ScheduledStopCard(scheduledStop: scheduledStop),
              ),
          _AnchorLine(
            label: 'End At',
            anchor: day.endAnchor,
            isHotel: !day.endIsOverallEnd,
            time: _formatClock(context, schedule.endArrival),
          ),
        ],
      ),
    );
  }

  /// The day's own start time — the first scheduled stop's arrival minus
  /// its travel time if there's at least one stop, otherwise just the
  /// day's end arrival (a day with nothing scheduled still starts and
  /// ends at the same anchor-to-anchor travel time).
  DateTime _dayStart(TripDay day, DaySchedule schedule) {
    final stops = schedule.scheduledStops;
    if (stops.isEmpty) return schedule.endArrival;
    final first = stops.first;
    return first.arrival.subtract(
      Duration(minutes: first.travelMinutesFromPrevious),
    );
  }
}

/// Shared card chrome (background, date header) for both
/// [_TripDayLoadingCard] and [_TripDaySection].
class _DayCardShell extends StatelessWidget {
  const _DayCardShell({required this.day, required this.child});

  final TripDay day;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DAY ${day.dayNumber}',
            style: TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatFullDate(day.date),
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _AnchorLine extends StatelessWidget {
  const _AnchorLine({
    required this.label,
    required this.anchor,
    required this.isHotel,
    this.time,
  });

  final String label;
  final TripStopLocation anchor;
  final bool isHotel;

  /// The actual clock time this anchor is reached, when known.
  final String? time;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          isHotel ? Icons.hotel_rounded : Icons.location_on_rounded,
          size: 18,
          color: isHotel ? AppColors.accent : context.colors.muted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                anchor.name,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
        if (time != null)
          Text(
            time!,
            style: TextStyle(
              color: context.colors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
}

/// One scheduled stop's real timeline: travel time in from wherever came
/// before it, arrival, a wait-for-opening callout if it arrived early,
/// and the visit window — all from [ScheduledStop], nothing simulated.
class _ScheduledStopCard extends StatelessWidget {
  const _ScheduledStopCard({required this.scheduledStop});

  final ScheduledStop scheduledStop;

  @override
  Widget build(BuildContext context) {
    final stop = scheduledStop.stop;
    final waitMinutes = scheduledStop.waitTime.inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            '${scheduledStop.travelMinutesFromPrevious} min travel'
            '${waitMinutes > 0 ? ' · ${waitMinutes}m wait for opening' : ''}',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(
                  stop.categoryIcon,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stop.name,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (scheduledStop.hasWeatherConcern)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.umbrella_rounded,
                              size: 16,
                              color: Colors.orange,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      stop.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_formatClock(context, scheduledStop.visitStart)} – '
                        '${_formatClock(context, scheduledStop.visitEnd)}',
                        style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Every stop that couldn't be fit anywhere — not its assigned day, not
/// another day with better weather, not a leftover gap on any day — see
/// [DaySchedule.unscheduledStops]. Not deleted, just not on the
/// timeline; a traveler can still manually work one in later.
class _UnscheduledSection extends StatelessWidget {
  const _UnscheduledSection({required this.entries});

  final List<UnscheduledStop> entries;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.orange,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Unscheduled',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'These stops didn\'t fit their day\'s opening hours or '
            'timing, no matter the order tried. Nothing was deleted —'
            ' plan around them manually, or drop them.',
            style: TextStyle(color: context.colors.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    entry.stop.categoryIcon,
                    size: 16,
                    color: context.colors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.stop.name,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          entry.reason,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
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
