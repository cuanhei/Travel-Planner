import 'package:flutter/material.dart';

import '../../models/day_schedule.dart';
import '../../models/pending_trip_draft.dart';
import '../../models/place_environment.dart';
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

  List<DaySchedule>? _schedules;
  String _statusMessage = 'Getting started…';

  @override
  void initState() {
    super.initState();
    // Deferred a frame so the very first status update isn't a setState
    // fired from within initState/the first build itself.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final schedules = await _computeSchedules();
    if (mounted) setState(() => _schedules = schedules);
  }

  Future<List<DaySchedule>> _computeSchedules() async {
    if (_tripDays.isEmpty) return const [];

    var assignment = const <int, List<TripStopLocation>>{};
    if (widget.draft.stops.isNotEmpty) {
      setState(
        () => _statusMessage = 'Figuring out which stops fit which day…',
      );
      final detours = await _assignmentService.computeDetours(
        days: _tripDays,
        places: widget.draft.stops,
      );
      assignment = _assignmentService.assignPlacesToDays(detours);
    }

    setState(
      () => _statusMessage = 'Working out travel times and opening hours…',
    );
    final baseSchedules = [
      for (final day in _tripDays)
        await _scheduleService.scheduleDay(
          day: day,
          stops: assignment[day.dayNumber] ?? const [],
          dayStart: widget.draft.startTime,
          dayEnd: widget.draft.endTime,
        ),
    ];

    setState(() => _statusMessage = 'Checking the weather forecast…');
    final weatherAdjusted = await _weatherAdjustmentService.adjust(
      baseSchedules: baseSchedules,
      dayStart: widget.draft.startTime,
      dayEnd: widget.draft.endTime,
    );

    setState(() => _statusMessage = 'Filling in any remaining gaps…');
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
    final schedules = _schedules;
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
              child: schedules == null
                  ? _BuildingItineraryView(statusMessage: _statusMessage)
                  : _ItineraryContent(
                      tripDays: _tripDays,
                      schedules: schedules,
                      draft: widget.draft,
                      tripName: widget.tripName,
                      description: widget.description,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen loading state shown for the whole time the pipeline is
/// computing (geographic clustering → route order → opening
/// hours/travel/duration → weather adjustment → gap filling) — nothing
/// about the itinerary is shown until it's actually finished, rather
/// than revealing partial per-day placeholders as they trickle in.
class _BuildingItineraryView extends StatelessWidget {
  const _BuildingItineraryView({required this.statusMessage});

  final String statusMessage;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.12),
              ),
              alignment: Alignment.center,
              child: const SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Planning your itinerary…',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                statusMessage,
                key: ValueKey(statusMessage),
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The finished itinerary — everything shown only once [schedules] is
/// fully computed.
class _ItineraryContent extends StatelessWidget {
  const _ItineraryContent({
    required this.tripDays,
    required this.schedules,
    required this.draft,
    required this.tripName,
    required this.description,
  });

  final List<TripDay> tripDays;
  final List<DaySchedule> schedules;
  final PendingTripDraft draft;
  final String tripName;
  final String description;

  @override
  Widget build(BuildContext context) {
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
              value: '${draft.stops.length}',
            ),
            _SummaryStat(
              icon: Icons.calendar_today_rounded,
              label: 'Days',
              value: '${tripDays.length}',
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (tripDays.isEmpty)
          Text(
            'Pick your travel dates and start/end locations '
            'to see the day-by-day plan.',
            style: TextStyle(color: context.colors.muted, fontSize: 13),
          )
        else ...[
          for (final schedule in schedules) _TripDaySection(schedule: schedule),
          if (unscheduled.isNotEmpty) _UnscheduledSection(entries: unscheduled),
        ],
        const SizedBox(height: 8),
        _SaveTripButton(
          tripName: tripName,
          description: description,
          draft: draft,
          schedules: schedules,
        ),
      ],
    );
  }
}

/// "Save Trip" button — this is the actual create-trip step for the
/// whole Create Trip flow. Nothing is written to the database before
/// this point; tapping it inserts the `trips` row, one
/// `trip_accommodations` row per night, then the whole generated
/// itinerary — every location involved into `trip_stops` and the timed
/// day-by-day route into `trip_schedule_stops` (see
/// [TripService.saveTripSchedule]) — before returning to My Trips.
/// Disabled (shown greyed out, not tappable) until [schedules] is
/// available, since there's nothing to save yet while the pipeline is
/// still computing.
class _SaveTripButton extends StatefulWidget {
  const _SaveTripButton({
    required this.tripName,
    required this.description,
    required this.draft,
    required this.schedules,
  });

  final String tripName;
  final String description;
  final PendingTripDraft draft;
  final List<DaySchedule>? schedules;

  @override
  State<_SaveTripButton> createState() => _SaveTripButtonState();
}

class _SaveTripButtonState extends State<_SaveTripButton> {
  final _tripService = TripService();
  bool _saving = false;

  Future<void> _handleTap() async {
    final schedules = widget.schedules;
    if (schedules == null) return;

    setState(() => _saving = true);
    final draft = widget.draft;
    try {
      final tripId = await _tripService.createTrip(
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
      await _tripService.saveTripSchedule(
        tripId: tripId,
        schedules: schedules,
        dayStart: draft.startTime,
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
    final ready = widget.schedules != null;
    return GradientButton(
      label: 'Save Trip',
      icon: Icons.bookmark_added_rounded,
      loading: _saving,
      onPressed: (_saving || !ready) ? () {} : _handleTap,
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
            for (var i = 0; i < schedule.scheduledStops.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: _ScheduledStopCard(
                  scheduledStop: schedule.scheduledStops[i],
                  previousLocationName: i == 0
                      ? day.startAnchor.name
                      : schedule.scheduledStops[i - 1].stop.name,
                ),
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

/// Shared card chrome (background, date header) for [_TripDaySection].
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

/// Why [scheduledStop] landed here — grounded only in what the pipeline
/// actually computed for it (travel time from whatever came before it,
/// whether it waited for opening, and its indoor/outdoor/mixed
/// [PlaceEnvironment] against [ScheduledStop.hasWeatherConcern]), not a
/// fabricated explanation.
String _reasonForStop(ScheduledStop scheduledStop, String previousLocationName) {
  final stop = scheduledStop.stop;
  final parts = <String>[];

  final travel = scheduledStop.travelMinutesFromPrevious;
  parts.add(
    travel <= 2
        ? 'Right next to $previousLocationName'
        : '$travel min from $previousLocationName',
  );

  if (scheduledStop.waitTime.inMinutes > 0) {
    parts.add('scheduled right as it opens');
  }

  final environment = getEnvironment(stop.primaryType, stop.types);
  if (scheduledStop.hasWeatherConcern) {
    parts.add("kept despite mixed weather — no better slot fit");
  } else if (environment == PlaceEnvironment.outdoor) {
    parts.add('good weather for an outdoor visit');
  } else if (environment == PlaceEnvironment.indoor) {
    parts.add('indoor, weather-proof pick');
  }

  return parts.join(' · ');
}

/// One scheduled stop's real timeline: travel time in from wherever came
/// before it, arrival, a wait-for-opening callout if it arrived early,
/// the visit window, and why the planner placed it here (see
/// [_reasonForStop]) — all derived from [ScheduledStop], nothing
/// simulated.
class _ScheduledStopCard extends StatelessWidget {
  const _ScheduledStopCard({
    required this.scheduledStop,
    required this.previousLocationName,
  });

  final ScheduledStop scheduledStop;
  final String previousLocationName;

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
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 12,
                          color: context.colors.muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _reasonForStop(scheduledStop, previousLocationName),
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
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
