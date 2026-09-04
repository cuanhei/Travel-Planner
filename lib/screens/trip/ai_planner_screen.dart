import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/trip.dart';
import '../../models/trip_draft.dart';
import '../../models/trip_stop_location.dart';
import '../../services/google_places_service.dart';
import '../../services/trip_scheduler_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../services/trip_planning_service.dart';
import '../../utils/scheduling/place_identity.dart';
import '../../utils/scheduling/recommendation_requests.dart';
import '../../utils/scheduling/schedule_insertion.dart';
import '../../utils/scheduling/day_ordering.dart';
import '../../utils/scheduling/nearby_recommendation.dart';
import '../../utils/scheduling/travel_matrix.dart';
import '../../utils/scheduling/trip_day.dart';
import '../../utils/weather_display.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/recommendation_status.dart';
import '../../widgets/gradient_button.dart';
import 'trip_details_screen.dart';

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

/// Builds a draft itinerary with real routes, hours, meals and weather before
/// atomically creating the trip. Optional nearby places require Add to Day.
class AiPlannerScreen extends StatefulWidget {
  const AiPlannerScreen({super.key, required this.draft});

  final TripDraft draft;

  @override
  State<AiPlannerScreen> createState() => _AiPlannerScreenState();
}

class _AiPlannerScreenState extends State<AiPlannerScreen> {
  final _schedulerService = TripSchedulerService();
  final _tripService = TripService();
  final _placesService = GooglePlacesService();

  /// Null until [_generate] successfully creates the trip row — every
  /// method below that needs it is only ever reachable after that (they
  /// all read from [_result], which [_generate] doesn't set until the
  /// trip, and its schedule, both exist for real).
  String? _tripId;
  final String _draftId = const Uuid().v4();
  PreparedTrip? _prepared;
  final Map<TripDay, String> _recommendationErrors = {};
  final Map<String, TripStopLocation> _pendingCandidates = {};
  final _recommendationRequests = RecommendationRequests<TripDay>();
  Set<TripStopLocation> _allStops = {};

  Trip? _trip;
  ScheduleResult? _result;
  bool _loading = true;
  String? _error;

  /// The travel matrix built once the core schedule exists — reused for
  /// every day's nearby-recommendation search and for re-optimizing a
  /// day after the traveler adds one (spec §47), rather than building a
  /// fresh one per call.
  TravelMatrixSource? _travelMatrix;
  Set<String> _interestCategories = const {};

  /// spec §36-47's nearby recommendations, keyed by [TripDay] (the same
  /// identity [_result]'s `ScheduledDay.day` uses) — one entry per gap
  /// found in that day (spec: not just "after the last stop" — a day
  /// can have idle time in the middle too, or be entirely empty), absent
  /// while still loading for that day, empty once loaded with nothing
  /// worth suggesting anywhere. Populated lazily per day rather than
  /// blocking the whole screen on every day's Places lookup finishing.
  final Map<TripDay, List<GapRecommendations>> _recommendations = {};
  final Set<TripDay> _recommendationsLoading = {};

  /// Days currently mid-"Add to Day N" (spec §47's re-optimize-then-
  /// persist), so that day's card can show a busy state and its Add
  /// buttons can be disabled to prevent a double-tap.
  final Set<TripDay> _addingTo = {};

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Retain the exact prepared payload for a safe retry after a timeout.
      final prepared = _prepared ??= await prepareTripDraft(
        widget.draft,
        tripId: _draftId,
        scheduler: _schedulerService,
        placesService: _placesService,
      );
      if (!mounted) return;
      final tripId = await _tripService.createPlannedTrip(
        tripId: _draftId,
        trip: prepared.fields,
        stops: prepared.stops,
        rows: buildScheduleRows(
          prepared.schedule.days,
          travelMode: prepared.trip.transportMode,
        ),
        interests: widget.draft.selectedInterests,
        days: buildScheduleDayRows(prepared.schedule.days),
        accommodationByNight: prepared.accommodationByNight,
      );
      final trip = await _tripService.getTrip(tripId);
      if (!mounted) return;
      final result = ScheduleResult(
        days: prepared.schedule.days,
        unscheduledStops: prepared.schedule.unscheduledStops,
        revision: trip.scheduleRevision,
      );
      setState(() {
        _tripId = tripId;
        _trip = trip;
        _result = result;
        _loading = false;
        _allStops = prepared.stops.toSet();
      });
      unawaited(_startRecommendations(trip, result));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not finish planning and saving your itinerary. '
            'Check your connection and retry.';
      });
    }
  }

  Future<void> _startRecommendations(Trip trip, ScheduleResult result) async {
    if (!trip.autoRecommend || result.days.isEmpty) return;

    if (!mounted) return;
    _travelMatrix = RouteServiceTravelMatrix(
      travelMode: TravelMode.fromDbValue(trip.transportMode),
    );
    _interestCategories = widget.draft.selectedInterests;
    final alreadyOnTrip = _allStops;
    for (final scheduledDay in result.days) {
      unawaited(_loadRecommendationsForDay(scheduledDay, alreadyOnTrip));
    }
  }

  Future<void> _loadRecommendationsForDay(
    ScheduledDay scheduledDay,
    Set<TripStopLocation> alreadyOnTrip,
  ) async {
    final travelMatrix = _travelMatrix;
    if (travelMatrix == null || !mounted) return;
    final day = scheduledDay.day;
    final ticket = _recommendationRequests.begin(day);
    if (ticket == null) return;

    setState(() {
      _recommendationsLoading.add(day);
      _recommendationErrors.remove(day);
    });
    List<GapRecommendations> gapResults;
    String? error;
    try {
      gapResults = await findGapRecommendations(
        day: day,
        ordering: scheduledDay.ordering,
        alreadyOnTrip: alreadyOnTrip,
        travelMatrix: travelMatrix,
        placesService: _placesService,
        interestCategories: _interestCategories,
      );
    } catch (_) {
      gapResults = const [];
      error = 'Nearby places could not be loaded. Please retry.';
    }
    if (!mounted || !_recommendationRequests.complete(day, ticket)) return;
    setState(() {
      _recommendations[day] = gapResults;
      if (error != null) _recommendationErrors[day] = error;
      _recommendationsLoading.remove(day);
    });
  }

  Future<void> _addRecommendation(
    TripDay day,
    ScheduleGap gap,
    CandidateEvaluation candidate,
  ) async {
    final matrix = _travelMatrix;
    final result = _result;
    if (matrix == null || result == null || _addingTo.isNotEmpty) return;
    final key = placeIdentity(candidate.visit.stop);
    if (_allStops.any((s) => placeIdentity(s) == key)) return;
    final index = result.days.indexWhere((d) => d.day == day);
    if (index < 0 ||
        !(_recommendations[day] ?? []).any(
          (g) => g.gap == gap && g.candidates.contains(candidate),
        )) {
      return;
    }
    setState(() => _addingTo.add(day));
    final stop = _pendingCandidates.putIfAbsent(
      key,
      () => candidate.visit.stop.copyWith(id: const Uuid().v4()),
    );
    try {
      final ordering = await insertIntoGap(
        day: day,
        ordering: result.days[index].ordering,
        gap: gap,
        stop: stop,
        travelMatrix: matrix,
      );
      if (ordering == null) {
        throw StateError(
          'This place no longer fits without changing your existing visits.',
        );
      }
      final proposedDay = day.copyWithStops(ordering.visits.map((v) => v.stop));
      final newDays = List<ScheduledDay>.of(result.days);
      newDays[index] = (day: proposedDay, ordering: ordering);
      final revision = await _tripService.saveSchedule(
        _tripId!,
        buildScheduleRows(newDays, travelMode: _trip!.transportMode),
        expectedRevision: result.revision,
        operationId: stop.id,
        newStops: [stop],
        recommendation: true,
        days: buildScheduleDayRows(newDays),
      );
      if (!mounted) return;
      setState(() {
        _result = ScheduleResult(
          days: newDays,
          unscheduledStops: result.unscheduledStops,
          revision: revision,
        );
        _allStops = {..._allStops, stop};
        _recommendationRequests.invalidate();
        _recommendations.clear();
        _recommendationErrors.clear();
        _recommendationsLoading.clear();
        _addingTo.clear();
      });
      for (final scheduledDay in newDays) {
        unawaited(_loadRecommendationsForDay(scheduledDay, _allStops));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingTo.clear());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not add ${stop.name}: $e'),
        ),
      );
    }
  }

  void _continueToTrip() {
    final trip = _trip;
    if (trip == null) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'AI Planner',
              subtitle: _trip?.name ?? 'Generating your itinerary…',
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const _GeneratingState();
    final error = _error;
    if (error != null) {
      return _ErrorState(message: error, onRetry: _generate);
    }
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    if (result.days.isEmpty) {
      return _NoScheduleState(onContinue: _continueToTrip);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        _SummaryRow(result: result),
        const SizedBox(height: 24),
        for (var i = 0; i < result.days.length; i++)
          _DaySection(
            dayNumber: i + 1,
            scheduledDay: result.days[i],
            recommendations: _recommendations[result.days[i].day],
            recommendationsLoading: _recommendationsLoading.contains(
              result.days[i].day,
            ),
            adding: _addingTo.isNotEmpty,
            recommendationError: _recommendationErrors[result.days[i].day],
            onRetryRecommendations: _trip!.autoRecommend
                ? () => _loadRecommendationsForDay(result.days[i], _allStops)
                : null,
            onAddRecommendation: (gap, candidate) =>
                _addRecommendation(result.days[i].day, gap, candidate),
          ),
        if (result.unscheduledStops.isNotEmpty) ...[
          _UnscheduledSection(stops: result.unscheduledStops),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 16),
        GradientButton(
          label: 'View Trip',
          icon: Icons.arrow_forward_rounded,
          onPressed: _continueToTrip,
        ),
      ],
    );
  }
}

class _GeneratingState extends StatelessWidget {
  const _GeneratingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 20),
            Text(
              'Building your day-by-day itinerary…',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Checking opening hours, travel time between stops, and the '
              'weather forecast for your dates.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
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
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _NoScheduleState extends StatelessWidget {
  const _NoScheduleState({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.event_busy_rounded,
              color: context.colors.muted,
              size: 28,
            ),
            const SizedBox(height: 10),
            Text(
              'This trip has no dates set yet, so there\'s nothing to '
              'schedule — add your travel dates to generate an itinerary.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            GradientButton(
              label: 'View Trip',
              icon: Icons.arrow_forward_rounded,
              expand: false,
              onPressed: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.result});

  final ScheduleResult result;

  @override
  Widget build(BuildContext context) {
    final scheduledStops = result.days.fold<int>(
      0,
      (sum, d) => sum + d.ordering.visits.length,
    );
    final totalTravelMinutes = result.days.fold<int>(
      0,
      (sum, d) =>
          sum +
          d.ordering.visits.fold<int>(
            0,
            (s, v) => s + v.travelFromPrevious.inMinutes,
          ),
    );
    return Row(
      children: [
        _SummaryStat(
          icon: Icons.calendar_today_rounded,
          label: 'Days',
          value: '${result.days.length}',
        ),
        _SummaryStat(
          icon: Icons.flag_rounded,
          label: 'Stops',
          value: '$scheduledStops',
        ),
        _SummaryStat(
          icon: Icons.directions_transit_rounded,
          label: 'Travel Time',
          value: '${totalTravelMinutes}m',
        ),
      ],
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

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.dayNumber,
    required this.scheduledDay,
    required this.recommendations,
    required this.recommendationsLoading,
    required this.adding,
    required this.onAddRecommendation,
    this.recommendationError,
    this.onRetryRecommendations,
  });

  final int dayNumber;
  final ScheduledDay scheduledDay;

  /// spec §36-47's suggestions for this day, one entry per free gap
  /// found (spec: not just after the last stop) — null while still
  /// loading (or never started, e.g. auto-recommend is off), empty once
  /// loaded with nothing worth suggesting anywhere in the day.
  final List<GapRecommendations>? recommendations;
  final bool recommendationsLoading;
  final String? recommendationError;
  final VoidCallback? onRetryRecommendations;

  /// True while a "Add to Day N" tap on this day is still being saved
  /// and re-optimized — disables every Add button on this day's card so
  /// a second tap can't race the first.
  final bool adding;
  final void Function(ScheduleGap gap, CandidateEvaluation candidate)
  onAddRecommendation;

  String get _dateLabel {
    final date = scheduledDay.day.date;
    return '${_monthNames[date.month - 1]} ${date.day}';
  }

  @override
  Widget build(BuildContext context) {
    final day = scheduledDay.day;
    final visits = scheduledDay.ordering.visits;
    final forecast = day.weatherForecast;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  'Day $dayNumber · $_dateLabel',
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (day.weatherAvailable && forecast != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E9CCA).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        weatherIconFor(forecast.summaryForecast),
                        color: const Color(0xFF2E9CCA),
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        translateWeather(forecast.summaryForecast),
                        style: const TextStyle(
                          color: Color(0xFF2E9CCA),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          if (day.routeOrigin != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${day.startAnchor == null ? 'Assumed start' : 'Start'}: '
                '${day.routeOrigin!.name} · ${formatClockTime(day.dailyStart)}',
              ),
            ),
          if (visits.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                'No stops scheduled this day.',
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
            )
          else
            for (var i = 0; i < visits.length; i++) ...[
              if (i > 0 || day.routeOrigin != null)
                _TransportConnector(visit: visits[i]),
              _VisitCard(visit: visits[i]),
            ],
          if (day.endAnchor != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                scheduledDay.ordering.endAnchorReachable
                    ? 'End: ${day.endAnchor!.name}'
                          '${scheduledDay.ordering.travelToEndAnchor == null ? '' : ' · ${formatDuration(scheduledDay.ordering.travelToEndAnchor!)} travel'}'
                    : 'Could not find a route to ${day.endAnchor!.name} within this day.',
              ),
            ),
          if (recommendationsLoading) ...[
            const SizedBox(height: 10),
            _RecommendationLoading(),
          ] else if (recommendationError != null) ...[
            RecommendationStatus(
              message: recommendationError!,
              onRetry: onRetryRecommendations,
            ),
          ] else if (recommendations != null && recommendations!.isEmpty) ...[
            RecommendationStatus(
              message:
                  visits.isEmpty &&
                      day.routeOrigin == null &&
                      day.endAnchor == null
                  ? 'Add a starting location or accommodation to find nearby places.'
                  : findScheduleGaps(
                      day: day,
                      ordering: scheduledDay.ordering,
                    ).isEmpty
                  ? 'No free window long enough for another visit.'
                  : 'No nearby places fit the available time and route. You can try again or add a stop in Edit Schedule.',
              onRetry: onRetryRecommendations,
            ),
          ] else if (recommendations != null &&
              recommendations!.isNotEmpty) ...[
            for (final gapRecommendations in recommendations!) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Text(
                  gapRecommendations.gap.label,
                  style: TextStyle(
                    color: context.colors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              for (final candidate in gapRecommendations.candidates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RecommendationCard(
                    dayNumber: dayNumber,
                    candidate: candidate,
                    adding: adding,
                    onAdd: () =>
                        onAddRecommendation(gapRecommendations.gap, candidate),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TransportConnector extends StatelessWidget {
  const _TransportConnector({required this.visit});

  final ScheduledVisit visit;

  @override
  Widget build(BuildContext context) {
    final minutes = visit.travelFromPrevious.inMinutes;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 23),
          Container(
            width: 2,
            height: 18,
            color: context.colors.muted.withValues(alpha: 0.2),
          ),
          const SizedBox(width: 14),
          Icon(Icons.directions_rounded, size: 15, color: context.colors.muted),
          const SizedBox(width: 6),
          Text(
            minutes <= 0
                ? 'Nearby'
                : '${formatDuration(visit.travelFromPrevious)} travel',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (visit.waitTime.inMinutes > 0) ...[
            const SizedBox(width: 8),
            Text(
              '· ${formatDuration(visit.waitTime)} waiting',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VisitCard extends StatelessWidget {
  const _VisitCard({required this.visit});

  final ScheduledVisit visit;

  @override
  Widget build(BuildContext context) {
    final stop = visit.stop;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.horizon),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(stop.categoryIcon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  stop.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
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
                    '${formatClockTime(visit.visitStart)} – ${formatClockTime(visit.visitEnd)}',
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
    );
  }
}

class _UnscheduledSection extends StatelessWidget {
  const _UnscheduledSection({required this.stops});

  final List<UnscheduledStop> stops;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                "Couldn't fit ${stops.length} stop${stops.length == 1 ? '' : 's'}",
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final unscheduled in stops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    unscheduled.stop.categoryIcon,
                    size: 16,
                    color: context.colors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          unscheduled.stop.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          unscheduled.reason,
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11,
                            height: 1.3,
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

/// Small inline spinner shown while a day's spec §38 nearby search is
/// still running — distinct from [_GeneratingState] (which blocks the
/// whole screen for the core schedule), since a slow recommendation
/// lookup shouldn't hold up the itinerary the traveler already has.
class _RecommendationLoading extends StatelessWidget {
  const _RecommendationLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.colors.muted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Looking for nearby places…',
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// One spec §46 nearby-recommendation card: what it is, how it fits,
/// and an explicit "Add to Day N" the traveler has to tap — the engine
/// never inserts a recommendation on its own.
class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.dayNumber,
    required this.candidate,
    required this.adding,
    required this.onAdd,
  });

  final int dayNumber;
  final CandidateEvaluation candidate;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final visit = candidate.visit;
    final stop = visit.stop;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 14,
                color: AppColors.accent,
              ),
              const SizedBox(width: 6),
              Text(
                'Nearby Recommendation',
                style: TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: AppColors.horizon),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(stop.categoryIcon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stop.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RecommendationStat(
                icon: _environmentIcon(stop.environmentType),
                label: _environmentLabel(stop.environmentType),
              ),
              if (stop.rating != null)
                _RecommendationStat(
                  icon: Icons.star_rounded,
                  label: stop.rating!.toStringAsFixed(1),
                ),
              _RecommendationStat(
                icon: Icons.directions_rounded,
                label: '${formatDuration(visit.travelFromPrevious)} travel',
              ),
              _RecommendationStat(
                icon: Icons.schedule_rounded,
                label:
                    'Suggested: ${formatClockTime(visit.visitStart)} – ${formatClockTime(visit.visitEnd)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: adding ? null : onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: adding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Add to Day $dayNumber',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _environmentIcon(EnvironmentType type) => switch (type) {
    EnvironmentType.indoor => Icons.home_rounded,
    EnvironmentType.outdoor => Icons.park_rounded,
    EnvironmentType.mixed => Icons.dashboard_rounded,
  };

  String _environmentLabel(EnvironmentType type) => switch (type) {
    EnvironmentType.indoor => 'Indoor',
    EnvironmentType.outdoor => 'Outdoor',
    EnvironmentType.mixed => 'Mixed',
  };
}

class _RecommendationStat extends StatelessWidget {
  const _RecommendationStat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.colors.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
