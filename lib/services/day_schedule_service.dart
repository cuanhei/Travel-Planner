import 'package:flutter/material.dart';

import '../models/day_schedule.dart';
import '../models/opening_window.dart';
import '../models/place_environment.dart';
import '../models/trip_day.dart';
import '../models/trip_stop_location.dart';
import '../models/unscheduled_stop.dart';
import '../models/weather_condition.dart';
import '../models/weather_forecast.dart';
import 'travel_time_cache.dart';

/// One attempted stop order's outcome — used internally to compare
/// candidate orders and keep the best.
class _Attempt {
  const _Attempt({
    required this.scheduled,
    required this.unfitted,
    required this.endArrival,
    this.weatherPenalty = 0,
  });

  final List<ScheduledStop> scheduled;
  final List<UnscheduledStop> unfitted;
  final DateTime endArrival;

  /// Sum of soft weather penalties (see [DayScheduleService.scheduleDay]'s
  /// `forecast` parameter) — a [PlaceEnvironment.mixed] stop landing in a
  /// forecast-bad period adds to this without being outright infeasible,
  /// so orders that happen to dodge it are still preferred when they're
  /// otherwise equally good.
  final int weatherPenalty;

  /// Fewer unfitted stops wins outright; then lower weather penalty; a
  /// remaining tie goes to whichever order reaches the day's end anchor
  /// earlier (less backtracking/waiting overall).
  bool isBetterThan(_Attempt other) {
    if (unfitted.length != other.unfitted.length) {
      return unfitted.length < other.unfitted.length;
    }
    if (weatherPenalty != other.weatherPenalty) {
      return weatherPenalty < other.weatherPenalty;
    }
    return endArrival.isBefore(other.endArrival);
  }
}

/// Builds a feasible, timed schedule for one day at a time: orders that
/// day's candidate stops (trying every ordering for a small list, since
/// Google Routes API travel time makes "just sort by distance" an
/// unreliable proxy for actual drive time — see the class doc on
/// [scheduleDay]), then walks that order forward through real time —
/// travel, waiting for opening if early, the visit itself — checking
/// every stop against its actual opening hours along the way.
///
/// When [scheduleDay] is given a [WeatherForecast] for that day, the same
/// order search also treats a [PlaceEnvironment.outdoor] stop landing in
/// a forecast-bad-weather period as infeasible for that order (so the
/// search naturally prefers whichever order/position keeps it out of
/// the rain — the same reordering machinery already used for opening
/// hours, not a separate pass) and gives a [PlaceEnvironment.mixed] stop
/// in bad weather a soft penalty instead (see [ScheduledStop.hasWeatherConcern]).
/// [PlaceEnvironment.indoor] is never affected. An outdoor stop that
/// can't avoid bad weather in *any* order tried lands in
/// [DaySchedule.unscheduledStops] just like an opening-hours failure
/// would — see `weather_adjustment_service.dart` for what happens to it
/// from there (retried on another day, or the floating pool).
///
/// Deliberately doesn't attempt cross-day reassignment itself: a stop
/// that can't fit any order tried for its assigned day lands in
/// [DaySchedule.unscheduledStops] (a "floating pool") rather than being
/// retried here on a different day — that's `WeatherAdjustmentService`'s
/// job, re-running this scheduler against other days' candidate lists.
class DayScheduleService {
  DayScheduleService({TravelTimeCache? travelTimeCache})
    : _travelTimeCache = travelTimeCache ?? TravelTimeCache();

  final TravelTimeCache _travelTimeCache;

  /// Above this many candidate stops, trying every ordering (n!) stops
  /// being practical — falls back to a single nearest-neighbor order
  /// instead of an exhaustive search. 6! = 720 orders, still fast; 7!
  /// is 5040 and each order needs several network-bound duration
  /// lookups (cached after the first time they're seen, but still).
  static const _maxStopsForExhaustiveSearch = 6;

  /// Builds [day]'s feasible timeline from its candidate [stops] (e.g.
  /// one day's group from [GeographicAssignmentService.assignPlacesToDays]).
  /// [dayStart]/[dayEnd] are that day's active-hours clock times (the
  /// trip's daily start/end time, applied to [TripDay.date]) — a visit
  /// may not run past [dayEnd] even if the place itself is still open.
  Future<DaySchedule> scheduleDay({
    required TripDay day,
    required List<TripStopLocation> stops,
    required TimeOfDay dayStart,
    required TimeOfDay dayEnd,
    WeatherForecast? forecast,
  }) async {
    final startTime = _dateTimeOn(day.date, dayStart);
    final endTime = _dateTimeOn(day.date, dayEnd);

    if (stops.isEmpty) {
      final travelToEnd = await _travelTimeCache.durationBetween(
        day.startAnchor,
        day.endAnchor,
      );
      return DaySchedule(
        day: day,
        scheduledStops: const [],
        unscheduledStops: const [],
        endArrival: startTime.add(travelToEnd),
      );
    }

    // A stop that's simply closed all day (any order) never belongs on
    // this day's timeline at all — filter those out up front rather
    // than letting every candidate order fail on it individually.
    final closedAllDay = <UnscheduledStop>[];
    final candidates = <TripStopLocation>[];
    for (final stop in stops) {
      if (openingWindowOn(stop, day.date).closedAllDay) {
        closedAllDay.add(
          UnscheduledStop(stop: stop, reason: 'Closed on this day'),
        );
      } else {
        candidates.add(stop);
      }
    }

    final orders = candidates.length <= _maxStopsForExhaustiveSearch
        ? _permutations(candidates)
        : [await _nearestNeighborOrder(day.startAnchor, candidates)];

    _Attempt? best;
    for (final order in orders) {
      final attempt = await _tryOrder(
        day: day,
        order: order,
        startTime: startTime,
        endTime: endTime,
        forecast: forecast,
      );
      if (best == null || attempt.isBetterThan(best)) {
        best = attempt;
        // Nothing unfitted and no weather penalty at all — can't do
        // better than this, no need to keep searching.
        if (attempt.unfitted.isEmpty && attempt.weatherPenalty == 0) break;
      }
    }

    return DaySchedule(
      day: day,
      scheduledStops: best!.scheduled,
      unscheduledStops: [...best.unfitted, ...closedAllDay],
      endArrival: best.endArrival,
    );
  }

  /// Walks one specific, already-decided stop [order] forward in time —
  /// no permutation search — for `GapFillingService`: testing whether a
  /// single floating-pool candidate fits at a specific position among an
  /// otherwise-fixed set of stops. [endCutoff] is an explicit hard
  /// deadline (e.g. midnight — "just get to the hotel before the next
  /// calendar day", not the trip's normal daily end time) rather than
  /// one derived from a [TimeOfDay].
  ///
  /// The result is only genuinely usable when
  /// [DaySchedule.unscheduledStops] comes back empty — any entry there
  /// means something in [order] (the inserted candidate, or a stop that
  /// was already fixed) didn't survive this exact arrangement.
  Future<DaySchedule> scheduleFixedOrder({
    required TripDay day,
    required List<TripStopLocation> order,
    required TimeOfDay dayStart,
    required DateTime endCutoff,
    WeatherForecast? forecast,
  }) async {
    final startTime = _dateTimeOn(day.date, dayStart);
    final attempt = await _tryOrder(
      day: day,
      order: order,
      startTime: startTime,
      endTime: endCutoff,
      forecast: forecast,
    );
    return DaySchedule(
      day: day,
      scheduledStops: attempt.scheduled,
      unscheduledStops: attempt.unfitted,
      endArrival: attempt.endArrival,
    );
  }

  /// Walks [order] forward in time from [startTime] at [day.startAnchor],
  /// skipping (not aborting on) any stop that fails feasibility — the
  /// next stop in [order] is still attempted from wherever the schedule
  /// left off, so one bad fit doesn't sink the rest of an otherwise good
  /// order.
  Future<_Attempt> _tryOrder({
    required TripDay day,
    required List<TripStopLocation> order,
    required DateTime startTime,
    required DateTime endTime,
    WeatherForecast? forecast,
  }) async {
    var current = startTime;
    var currentLocation = day.startAnchor;
    final scheduled = <ScheduledStop>[];
    final unfitted = <UnscheduledStop>[];
    var weatherPenalty = 0;

    for (final stop in order) {
      final travel = await _travelTimeCache.durationBetween(
        currentLocation,
        stop,
      );
      final arrival = current.add(travel);
      final window = openingWindowOn(stop, day.date);

      var visitStart = arrival;
      final closing = window.isUnconstrained ? null : window.close;
      if (!window.isUnconstrained) {
        final opening = window.open;
        if (opening != null && arrival.isBefore(opening)) {
          visitStart = opening;
        }
        if (closing != null && arrival.isAfter(closing)) {
          unfitted.add(
            UnscheduledStop(stop: stop, reason: 'Arrives after closing'),
          );
          continue;
        }
      }

      final visitEnd = visitStart.add(
        Duration(minutes: stop.estimatedVisitMinutes),
      );
      final exceedsClosing = closing != null && visitEnd.isAfter(closing);
      if (exceedsClosing) {
        unfitted.add(
          UnscheduledStop(
            stop: stop,
            reason: "Visit wouldn't finish before closing",
          ),
        );
        continue;
      }
      if (visitEnd.isAfter(endTime)) {
        unfitted.add(
          UnscheduledStop(
            stop: stop,
            reason: 'Would run past the allowed time window',
          ),
        );
        continue;
      }

      // Weather: an outdoor stop landing in a forecast-bad period is
      // treated the same as an opening-hours failure for this order —
      // infeasible here, so the search prefers whichever order/position
      // keeps it dry instead. Mixed gets a soft penalty and a flag, not
      // a rejection; indoor is never affected.
      var hasWeatherConcern = false;
      if (forecast != null) {
        final environment = getEnvironment(stop.primaryType, stop.types);
        final isBad = forecast.isBadFor(periodForTime(visitStart));
        if (isBad && environment == PlaceEnvironment.outdoor) {
          unfitted.add(
            UnscheduledStop(
              stop: stop,
              reason: 'Outdoor stop conflicts with forecast weather',
            ),
          );
          continue;
        }
        if (isBad && environment == PlaceEnvironment.mixed) {
          hasWeatherConcern = true;
          weatherPenalty++;
        }
      }

      scheduled.add(
        ScheduledStop(
          stop: stop,
          travelMinutesFromPrevious: travel.inMinutes,
          arrival: arrival,
          visitStart: visitStart,
          visitEnd: visitEnd,
          hasWeatherConcern: hasWeatherConcern,
        ),
      );
      current = visitEnd;
      currentLocation = stop;
    }

    final travelToEnd = await _travelTimeCache.durationBetween(
      currentLocation,
      day.endAnchor,
    );
    return _Attempt(
      scheduled: scheduled,
      unfitted: unfitted,
      endArrival: current.add(travelToEnd),
      weatherPenalty: weatherPenalty,
    );
  }

  /// Greedy fallback for a candidate list too large to permute
  /// exhaustively: repeatedly pick whichever remaining stop is closest
  /// (by travel time) to wherever the route currently is.
  Future<List<TripStopLocation>> _nearestNeighborOrder(
    TripStopLocation start,
    List<TripStopLocation> stops,
  ) async {
    final remaining = [...stops];
    final order = <TripStopLocation>[];
    var current = start;
    while (remaining.isNotEmpty) {
      TripStopLocation? nearest;
      Duration? nearestDuration;
      for (final candidate in remaining) {
        final duration = await _travelTimeCache.durationBetween(
          current,
          candidate,
        );
        if (nearestDuration == null || duration < nearestDuration) {
          nearest = candidate;
          nearestDuration = duration;
        }
      }
      order.add(nearest!);
      remaining.remove(nearest);
      current = nearest;
    }
    return order;
  }

  List<List<TripStopLocation>> _permutations(List<TripStopLocation> items) {
    if (items.length <= 1) return [items];
    final result = <List<TripStopLocation>>[];
    for (var i = 0; i < items.length; i++) {
      final rest = [...items]..removeAt(i);
      for (final perm in _permutations(rest)) {
        result.add([items[i], ...perm]);
      }
    }
    return result;
  }

  DateTime _dateTimeOn(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
