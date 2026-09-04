import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/trip.dart';
import '../models/trip_stop_location.dart';
import '../models/weather_forecast.dart';
import '../utils/scheduling/day_assignment.dart';
import '../utils/scheduling/day_ordering.dart';
import '../utils/scheduling/meal_planning.dart';
import '../utils/scheduling/place_identity.dart';
import '../utils/scheduling/travel_matrix.dart';
import '../utils/scheduling/trip_day.dart';
import '../utils/scheduling/validation.dart';
import 'google_places_service.dart';
import 'trip_service.dart';
import 'weather_service.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The stop in [stops] whose `trip_stops.id` is [id], or null if [id] is
/// null or nothing matches — used to resolve
/// [Trip.startLocationStopId]/[Trip.endLocationStopId] against a stop
/// list already fetched for other reasons, rather than a second query.
TripStopLocation? _findStopById(List<TripStopLocation> stops, String? id) {
  if (id == null) return null;
  for (final stop in stops) {
    if (stop.id == id) return stop;
  }
  return null;
}

/// One [TripDay] plus its final visiting order, after
/// [TripSchedulerService.run] has assigned and ordered every stop.
typedef ScheduledDay = ({TripDay day, DayOrderingResult ordering});

/// A stop [TripSchedulerService.run] couldn't fit anywhere, plus *why*
/// — spec §49's "Unable to Schedule" list, previously surfaced as a bare
/// name with a generic "didn't fit" message regardless of the actual
/// cause. See [explainUnscheduled].
class UnscheduledStop {
  const UnscheduledStop({required this.stop, required this.reason});

  final TripStopLocation stop;
  final String reason;
}

/// The end result of [TripSchedulerService.run] — spec's full flow
/// distilled to a day-by-day schedule plus anything that couldn't be
/// fit anywhere (spec §49), never silently dropped.
class ScheduleResult {
  const ScheduleResult({
    required this.days,
    required this.unscheduledStops,
    this.revision = 0,
  });

  final int revision;

  final List<ScheduledDay> days;
  final List<UnscheduledStop> unscheduledStops;
}

/// A best-effort, human-readable explanation for why [stop] never made
/// it onto any day — checked from most to least specific; the last case
/// is a catch-all for "lost out to other stops/travel time/weather
/// during scoring," not a hard constraint that can be named precisely.
/// Purely diagnostic: doesn't change what got scheduled, only explains
/// it after the fact, so it's safe to compute once at the very end of
/// [TripSchedulerService.run] over whichever [days] it actually built.
String explainUnscheduled(TripStopLocation stop, List<TripDay> days) {
  if (!hasValidCoordinates(stop)) {
    return 'This place has no usable map coordinates. Choose it again from search.';
  }
  if (stop.estimatedVisitDurationMinutes <= 0) {
    return 'Set a positive visit duration for this place.';
  }
  if (stop.businessStatus == 'CLOSED_PERMANENTLY') {
    return 'This place is permanently closed.';
  }
  if (stop.businessStatus == 'CLOSED_TEMPORARILY') {
    return 'This place is temporarily closed.';
  }
  if (days.isEmpty) {
    return "This trip has no valid dates to schedule against.";
  }

  final tripDates = [
    for (final day in days)
      (date: day.date, dailyStart: day.dailyStart, dailyEnd: day.dailyEnd),
  ];
  if (!isSchedulableAnyDate(stop, tripDates)) {
    return 'This place is closed on every day of your trip.';
  }

  final longestDayMinutes = days
      .map((d) => d.availableDuration.inMinutes)
      .reduce((a, b) => a > b ? a : b);
  if (stop.estimatedVisitDurationMinutes > longestDayMinutes) {
    final neededHours = (stop.estimatedVisitDurationMinutes / 60)
        .toStringAsFixed(1);
    final availableHours = (longestDayMinutes / 60).toStringAsFixed(1);
    return "Needs about ${neededHours}h to visit — longer than any single "
        "day's ${availableHours}h window.";
  }

  return "Couldn't fit alongside your other stops once travel time, "
      'opening hours, and your daily time limits were accounted for — try removing '
      'another stop, extending the trip, or shortening a visit duration.';
}

/// Distinguishes missing routes and an individually impossible visit from a
/// stop that fits alone but loses out to other selected visits.
Future<String> diagnoseUnscheduledStop(
  TripStopLocation stop,
  List<TripDay> days,
  TravelMatrixSource matrix,
) async {
  final basic = explainUnscheduled(stop, days);
  if (!basic.startsWith("Couldn't fit")) return basic;
  var hasRoutes = false;
  for (final day in days) {
    if (validateStopForDate(
          stop,
          date: day.date,
          dailyStart: day.dailyStart,
          dailyEnd: day.dailyEnd,
        ) ==
        StopValidationResult.invalid) {
      continue;
    }
    final origin = day.routeOrigin;
    final end = day.endAnchor;
    if (origin != null && await matrix.travelTime(origin, stop) == null) {
      continue;
    }
    if (end != null && await matrix.travelTime(stop, end) == null) continue;
    hasRoutes = true;
    final alone = await orderDay(
      day.copyWithStops([stop]),
      travelMatrix: matrix,
    );
    if (alone.visits.isNotEmpty && alone.endAnchorReachable) return basic;
  }
  return hasRoutes
      ? 'The visit, opening hours and travel to the final location cannot fit within any daily time window.'
      : 'No route is available to or from this place using the selected transport mode. Try another mode or location.';
}

/// Orchestrates the constraint-based scheduling engine: builds the
/// trip's days with accommodation-anchor chaining
/// (`utils/scheduling/trip_day.dart`), resolves per-day weather
/// availability (spec §12 — never assumed for a day outside the
/// forecast window), builds a travel-time matrix over every stop
/// (`utils/scheduling/travel_matrix.dart`), assigns stops to days
/// (`day_assignment.dart`), orders each day
/// (`day_ordering.dart`), and re-optimizes across days when a stop
/// doesn't actually fit where it was first assigned (spec §34) — then
/// persists the result via [TripService.saveSchedule].
///
/// Core planning and automatic meals finish before optional nearby suggestions
/// are fetched by the planner UI. Draft planning does not write to the database.
class TripSchedulerService {
  TripSchedulerService({
    TripService? tripService,
    WeatherService? weatherService,
    TravelMatrixSource? travelMatrix,
    GooglePlacesService? placesService,
  }) : _tripService = tripService ?? TripService(),
       _weatherService = weatherService ?? WeatherService(),
       _injectedTravelMatrix = travelMatrix,
       _placesService = placesService ?? GooglePlacesService();

  final TripService _tripService;
  final WeatherService _weatherService;
  final GooglePlacesService _placesService;

  /// Caller-supplied travel matrix (tests inject a fake here) — when
  /// null, [run] builds the real [RouteServiceTravelMatrix] itself once
  /// the trip is loaded, using [Trip.transportMode] (spec §2.1's
  /// "Preferred transportation mode") rather than always defaulting to
  /// driving. Can't be built at construction time: this service is
  /// constructed before any tripId is known (see AiPlannerScreen), so
  /// there's no trip to read the mode from yet.
  final TravelMatrixSource? _injectedTravelMatrix;

  /// Re-assignment passes attempted for stops [day_ordering.dart]
  /// couldn't actually fit where [day_assignment.dart] first placed
  /// them (spec §34), before accepting them as genuinely unschedulable.
  /// Bounded so a pathological trip (every day already full) can't
  /// loop forever chasing a fit that will never exist.
  static const _maxReoptimizationPasses = 3;

  Future<ScheduleResult> run(String tripId) async {
    final trip = await _tripService.getTrip(tripId);
    final allStops = await _tripService.getTripStops(tripId);
    final accommodations = await _tripService.getAccommodations(tripId);
    final result = await plan(
      trip: trip,
      allStops: allStops,
      accommodationByNight: {
        for (final a in accommodations) _dateOnly(a.nightDate): a.stop,
      },
    );
    final existingIds = allStops.map((s) => s.id).toSet();
    final newStops = [
      for (final d in result.days)
        for (final v in d.ordering.visits)
          if (!existingIds.contains(v.stop.id)) v.stop,
    ];
    final revision = await _tripService.saveSchedule(
      tripId,
      buildScheduleRows(result.days, travelMode: trip.transportMode),
      newStops: newStops,
      expectedRevision: trip.scheduleRevision,
      days: buildScheduleDayRows(result.days),
    );
    return ScheduleResult(
      days: result.days,
      unscheduledStops: result.unscheduledStops,
      revision: revision,
    );
  }

  Future<ScheduleResult> plan({
    required Trip trip,
    required List<TripStopLocation> allStops,
    required Map<DateTime, TripStopLocation> accommodationByNight,
  }) async {
    final travelMatrix =
        _injectedTravelMatrix ??
        RouteServiceTravelMatrix(
          travelMode: TravelMode.fromDbValue(trip.transportMode),
        );
    final startDate = trip.startDate;
    final endDate = trip.endDate;
    if (startDate == null || endDate == null) {
      // No dates to build days from at all — nothing this engine can
      // schedule against, so every stop is reported unscheduled rather
      // than guessed at.
      final stops = allStops;
      return ScheduleResult(
        days: const [],
        unscheduledStops: [
          for (final s in stops)
            UnscheduledStop(
              stop: s,
              reason: 'This trip has no travel dates set yet.',
            ),
        ],
      );
    }

    // The real Starting-From/Ending-At place (spec §2.1/§16), if set —
    // already among allStops, since it was saved the same way as any
    // other stop (see CreateTripScreen._saveTripLocations); resolved by
    // id here rather than a separate fetch.
    final tripStartLocation = _findStopById(allStops, trip.startLocationStopId);
    final tripEndLocation = _findStopById(allStops, trip.endLocationStopId);
    // Neither the accommodation stop nor the trip's own start/end anchor
    // is something to "visit" — exclude them from the pool the
    // assignment/ordering passes place into the day itself.
    final stops = allStops
        .where((s) => s.visitPurpose != VisitPurpose.accommodation)
        .where(
          (s) =>
              s.id == null ||
              (s.id != trip.startLocationStopId &&
                  s.id != trip.endLocationStopId),
        )
        .toList();

    // Anchors (spec §12/15's per-day weather check needs to know *where*
    // each day actually is before it can be resolved) don't depend on
    // weather at all — build the day list once without it purely to
    // learn each day's start/end anchor, then resolve weather per day
    // against that, then build the real day list. buildTripDays is pure
    // date/anchor arithmetic (no I/O), so building it twice is cheap.
    final anchorOnlyDays = buildTripDays(
      startDate: startDate,
      endDate: endDate,
      dailyStartTime: trip.startTime,
      dailyEndTime: trip.endTime,
      accommodationByNight: accommodationByNight,
      tripStartLocation: tripStartLocation,
      tripEndLocation: tripEndLocation,
    );
    final weatherByDate = await _resolveWeatherPerDay(anchorOnlyDays, allStops);

    final days = buildTripDays(
      startDate: startDate,
      endDate: endDate,
      dailyStartTime: trip.startTime,
      dailyEndTime: trip.endTime,
      accommodationByNight: accommodationByNight,
      tripStartLocation: tripStartLocation,
      tripEndLocation: tripEndLocation,
      weatherByDate: weatherByDate,
    );
    if (days.isEmpty) {
      return ScheduleResult(
        days: const [],
        unscheduledStops: [
          for (final s in stops)
            UnscheduledStop(
              stop: s,
              reason: "This trip's date range isn't valid.",
            ),
        ],
      );
    }

    if (travelMatrix is RouteServiceTravelMatrix) {
      final everyPoint = <TripStopLocation>{
        ...stops,
        for (final day in days) ...[
          if (day.startAnchor != null) day.startAnchor!,
          if (day.endAnchor != null) day.endAnchor!,
        ],
      }.toList();
      await travelMatrix.precompute(everyPoint);
    }

    final unscheduled = <TripStopLocation>{
      ...await assignStopsToDays(stops, days, travelMatrix: travelMatrix),
    };

    final orderings = <TripDay, DayOrderingResult>{
      for (final day in days)
        day: await orderDay(day, travelMatrix: travelMatrix),
    };

    for (var pass = 0; pass < _maxReoptimizationPasses; pass++) {
      final bumped = <TripStopLocation>[];
      for (final day in days) {
        final result = orderings[day]!;
        if (result.unfitStops.isEmpty) continue;
        day.assignedStops.removeWhere(result.unfitStops.contains);
        bumped.addAll(result.unfitStops);
      }
      if (bumped.isEmpty) break;

      unscheduled.addAll(
        await assignStopsToDays(bumped, days, travelMatrix: travelMatrix),
      );
      for (final day in days) {
        orderings[day] = await orderDay(day, travelMatrix: travelMatrix);
      }
    }
    // Reconcile the last pass too: never lose a selected stop.
    for (final day in days) {
      unscheduled.addAll(orderings[day]!.unfitStops);
      day.assignedStops
        ..clear()
        ..addAll(orderings[day]!.visits.map((v) => v.stop));
    }
    for (final day in days) {
      final meals = await planMissingMeals(
        day: day,
        ordering: orderings[day]!,
        travelMatrix: travelMatrix,
        placesService: _placesService,
      );
      for (final meal in meals) {
        final candidate = meal.copyWith(id: const Uuid().v4());
        final proposed = day.copyWithStops([...day.assignedStops, candidate]);
        final ordered = await orderDay(proposed, travelMatrix: travelMatrix);
        // Optional meals must never displace a selected attraction or meal.
        if (ordered.unfitStops.isNotEmpty || !ordered.endAnchorReachable) {
          continue;
        }
        day.assignedStops.add(candidate);
        orderings[day] = ordered;
      }
    }
    final scheduled = {
      for (final day in days)
        for (final visit in orderings[day]!.visits) visit.stop,
    };
    unscheduled
      ..addAll(stops.where((s) => !scheduled.contains(s)))
      ..removeWhere(scheduled.contains);

    final resultDays = [
      for (final day in days) (day: day, ordering: orderings[day]!),
    ];

    return ScheduleResult(
      days: resultDays,
      unscheduledStops: [
        for (final stop in unscheduled)
          UnscheduledStop(
            stop: stop,
            reason: await diagnoseUnscheduledStop(stop, days, travelMatrix),
          ),
      ],
    );
  }

  /// Per-day forecast resolution — spec §12: whether weather is
  /// available is checked *per trip day*, not once for the whole trip,
  /// and (this is the fix over the previous single-lookup version) each
  /// day's forecast comes from wherever *that day* actually is: its own
  /// start anchor (the hotel the traveler slept at, or the trip's
  /// Starting-From point on Day 1), falling back to the end anchor, then
  /// to [fallbackStops]' first entry only if a day has no anchor at all.
  /// A multi-city trip (different hotels in different towns) gets a
  /// different, correct forecast area per day instead of the whole trip
  /// silently using wherever the very first stop happens to be.
  ///
  /// Caches one forecast window per distinct reference location (rounded
  /// to ~1km) so trip days sharing the same hotel don't each trigger
  /// their own network round-trip. Returns an empty map — never a faked
  /// forecast — for a day with nowhere to search from, or when every
  /// lookup fails (network, or the trip is outside Malaysia).
  Future<Map<DateTime, WeatherForecast>> _resolveWeatherPerDay(
    List<TripDay> days,
    List<TripStopLocation> fallbackStops,
  ) async {
    final result = <DateTime, WeatherForecast>{};
    final windowCache = <String, ResolvedWeatherWindow?>{};

    for (final day in days) {
      final referenceStop =
          day.startAnchor ??
          day.endAnchor ??
          (fallbackStops.isNotEmpty ? fallbackStops.first : null);
      if (referenceStop == null) continue;

      final key =
          '${referenceStop.latitude.toStringAsFixed(2)},'
          '${referenceStop.longitude.toStringAsFixed(2)}';
      final window = windowCache.containsKey(key)
          ? windowCache[key]
          : windowCache[key] = await _fetchWindowSafely(referenceStop);
      final forecast = window?.forecastForDate(day.date);
      if (forecast != null) result[day.date] = forecast;
    }
    return result;
  }

  Future<ResolvedWeatherWindow?> _fetchWindowSafely(
    TripStopLocation stop,
  ) async {
    try {
      return await _weatherService.getForecastWindowForPosition(
        LatLng(stop.latitude, stop.longitude),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Converts a full day-by-day schedule into the row shape
/// [TripService.saveSchedule] expects — shared by [TripSchedulerService]
/// itself and by anything that mutates an already-generated schedule
/// afterward (e.g. `AiPlannerScreen` adding a spec §46 nearby
/// recommendation to one day) and needs to re-persist all of it, since
/// [TripService.saveSchedule] always replaces every row for the trip
/// rather than patching one day in place.
List<ScheduleWriteRow> buildScheduleRows(
  List<ScheduledDay> resultDays, {
  String? travelMode,
}) {
  final rows = <ScheduleWriteRow>[];
  for (var i = 0; i < resultDays.length; i++) {
    final visits = resultDays[i].ordering.visits;
    for (var sequence = 0; sequence < visits.length; sequence++) {
      final visit = visits[sequence];
      final stopId = visit.stop.id;
      if (stopId == null) throw StateError('A scheduled visit has no ID.');
      rows.add((
        dayNumber: i + 1,
        sequence: sequence,
        stopId: stopId,
        isHotel: false,
        scheduledArrival: visit.arrival,
        scheduledVisitStart: visit.visitStart,
        scheduledDeparture: visit.visitEnd,
        travelMode: travelMode ?? 'drive',
        travelMinutes: visit.travelFromPrevious.inMinutes,
      ));
    }
  }
  return rows;
}

List<Map<String, dynamic>> buildScheduleDayRows(List<ScheduledDay> days) => [
  for (var i = 0; i < days.length; i++)
    {
      'day_number': i + 1,
      'start_stop_id': days[i].day.routeOrigin?.id,
      'end_stop_id': days[i].day.endAnchor?.id,
      'daily_start': days[i].day.dailyStart.toIso8601String().split('T').last,
      'daily_end': days[i].day.dailyEnd.toIso8601String().split('T').last,
      'return_travel_minutes': days[i].ordering.travelToEndAnchor?.inMinutes,
      'end_anchor_reachable': days[i].ordering.endAnchorReachable,
    },
];
