import '../../models/trip_stop_location.dart';
import '../../models/weather_forecast.dart';
import 'travel_matrix.dart';
import 'trip_day.dart';
import 'weather_suitability.dart';
import 'opening_windows.dart';
import 'validation.dart';

/// One stop's simulated visit within a day's ordering — spec §28-30:
/// arrival (previous departure + travel), visit start (waits for
/// opening if early), and visit end.
class ScheduledVisit {
  const ScheduledVisit({
    required this.stop,
    required this.arrival,
    required this.visitStart,
    required this.visitEnd,
    required this.travelFromPrevious,
  });

  final TripStopLocation stop;
  final DateTime arrival;
  final DateTime visitStart;
  final DateTime visitEnd;

  /// Travel time from whatever preceded this stop (the previous visit,
  /// or the day's start anchor for the first one) — zero if there was
  /// no "previous" to travel from at all.
  final Duration travelFromPrevious;

  Duration get waitTime => visitStart.difference(arrival);
}

/// The result of ordering one [TripDay]'s assigned stops — spec §27-34.
class DayOrderingResult {
  const DayOrderingResult({
    required this.visits,
    required this.unfitStops,
    required this.finishTime,
    this.travelToEndAnchor,
    this.endAnchorReachable = true,
  });

  /// Every successfully-scheduled stop, in visiting order.
  final List<ScheduledVisit> visits;

  /// Stops that couldn't be fit into this day at all, even after
  /// trying every remaining candidate at each step (spec §33-34) — the
  /// caller (`trip_scheduler_service.dart`) is responsible for trying
  /// to move these to another day and re-optimizing both, not this
  /// function (which only ever looks at one day).
  final List<TripStopLocation> unfitStops;

  /// When the day's last visit ends (or [TripDay.dailyStart] if
  /// nothing was scheduled) — checked against [TripDay.dailyEnd].
  final DateTime finishTime;
  final Duration? travelToEndAnchor;
  final bool endAnchorReachable;
}

const _closingRiskThresholdMinutes = 60;
const _closingRiskPenaltyPerMinute = 0.5;
const _mealDriftPenaltyPerMinute = 0.5;

/// spec §27's WeatherTimePenalty / §32's time-of-day weather planning —
/// scores a candidate's placement against the forecast period its
/// [ScheduledVisit.visitStart] actually falls into (see
/// `weather_suitability.dart`'s [forecastForTime]), so an outdoor stop
/// is pulled toward a good-weather part of the day and away from a
/// bad/severe one, independent of [_closingRiskPenaltyPerMinute]/
/// [_mealDriftPenaltyPerMinute]'s effect on the same score. Sized to
/// meaningfully outweigh a same-score alternative that only differs by
/// travel/wait time or closing risk (whose maximum is
/// `_closingRiskThresholdMinutes * _closingRiskPenaltyPerMinute` = 30):
/// [_weatherTimeAvoidPenalty] is well past that, [_weatherTimePoorPenalty]
/// comparable to it, and [_weatherTimePreferredBonus] pulls a preferred
/// slot ahead of a merely "normal" one by a similar margin.
const _weatherTimePreferredBonus = -20.0;
const _weatherTimePoorPenalty = 30.0;
const _weatherTimeAvoidPenalty = 60.0;

/// spec §31's preferred/allowed windows, in minutes-from-midnight.
/// [MealType.snack] has no strong preferred time — spec calls it
/// "FLEXIBLE" — so its window spans the whole day with no out-of-window
/// penalty, just the (currently zero, since preferred == its own
/// midpoint is meaningless) drift term.
const _mealWindows = {
  MealType.breakfast: (
    preferredMinutes: 8 * 60,
    allowedStart: 7 * 60,
    allowedEnd: 10 * 60,
  ),
  MealType.lunch: (
    preferredMinutes: 12 * 60 + 30,
    allowedStart: 11 * 60 + 30,
    allowedEnd: 14 * 60 + 30,
  ),
  MealType.dinner: (
    preferredMinutes: 19 * 60,
    allowedStart: 18 * 60,
    allowedEnd: 21 * 60,
  ),
  MealType.snack: (
    preferredMinutes: 15 * 60,
    allowedStart: 0,
    allowedEnd: 24 * 60,
  ),
};

/// [type]'s spec §31 preferred clock time, in minutes-from-midnight —
/// exposed for `meal_planning.dart`'s spec §10 auto-planning pass, which
/// needs to know roughly *when* a meal should land before it even has a
/// candidate stop to run [evaluateCandidateVisit]'s real simulation on
/// (used there to pick which existing visit the traveler would be near
/// at that time, i.e. where to search).
int preferredMealMinutes(MealType type) => _mealWindows[type]!.preferredMinutes;

/// [type]'s spec §31 allowed window, in minutes-from-midnight — a day
/// whose [TripDay.dailyStart]/[TripDay.dailyEnd] don't overlap this at
/// all has no reasonable time to fit that meal, regardless of how good
/// a candidate might be found.
({int allowedStart, int allowedEnd}) mealAllowedWindow(MealType type) {
  final window = _mealWindows[type]!;
  return (allowedStart: window.allowedStart, allowedEnd: window.allowedEnd);
}

/// Orders [day]'s [TripDay.assignedStops] by repeatedly picking the
/// lowest-score next stop (spec §27) — never simple nearest-neighbor.
/// Simulates arrival/wait/visit/departure for each pick (spec §28-30),
/// respecting [day.dailyEnd] and, if [TripDay.endAnchor] is set, that
/// there's still time to travel back to it afterward. A stop no
/// remaining candidate slot can accommodate lands in
/// [DayOrderingResult.unfitStops] instead of forcing a schedule that
/// can't actually be kept (spec §33-34).
Future<DayOrderingResult> orderDay(
  TripDay day, {
  required TravelMatrixSource travelMatrix,
}) async {
  final remaining = List<TripStopLocation>.of(day.assignedStops);
  final visits = <ScheduledVisit>[];

  TripStopLocation? currentPosition = day.routeOrigin;
  var currentTime = day.dailyStart;

  while (remaining.isNotEmpty) {
    CandidateEvaluation? best;
    for (final candidate in remaining) {
      final evaluated = await evaluateCandidateVisit(
        candidate,
        day: day,
        from: currentPosition,
        currentTime: currentTime,
        travelMatrix: travelMatrix,
      );
      if (evaluated == null) continue;
      if (best == null || evaluated.score < best.score) best = evaluated;
    }
    if (best == null) break; // nothing left fits from here — stop early
    visits.add(best.visit);
    remaining.remove(best.visit.stop);
    currentPosition = best.visit.stop;
    currentTime = best.visit.visitEnd;
  }

  final trimmed = await _trimToFitEndAnchor(
    day,
    visits: visits,
    currentTime: currentTime,
    travelMatrix: travelMatrix,
  );
  remaining.addAll(trimmed.cut);

  return DayOrderingResult(
    visits: visits,
    unfitStops: remaining,
    finishTime: trimmed.finishTime,
    travelToEndAnchor: trimmed.travel,
    endAnchorReachable: trimmed.reachable,
  );
}

/// Simulates [day]'s stops in exactly the given [order] — unlike
/// [orderDay], this never searches for a better sequence, so a
/// traveler's manual drag-reorder (Edit Schedule) is respected as-is
/// when feasible. Walks [order] step by step with the same
/// arrival/wait/visit/departure simulation [orderDay] uses per
/// candidate (spec §28-30); a stop that can't be visited at its given
/// position — closed, or would finish past [TripDay.dailyEnd] — is
/// skipped (landing in [DayOrderingResult.unfitStops]) without
/// disturbing where the *other* stops in [order] land, so the traveler
/// sees exactly what does and doesn't fit about their chosen sequence
/// (spec §34: "don't just accept the manual order verbatim... if it's
/// infeasible" — surface it, rather than silently forcing a schedule
/// that can't be kept, or discarding their ordering choice by
/// re-searching for a different one).
Future<DayOrderingResult> simulateFixedOrder(
  TripDay day,
  List<TripStopLocation> order, {
  required TravelMatrixSource travelMatrix,
  Map<String, DateTime> notBeforeByStopId = const {},
}) async {
  final visits = <ScheduledVisit>[];
  final unfit = <TripStopLocation>[];

  TripStopLocation? currentPosition = day.routeOrigin;
  var currentTime = day.dailyStart;

  for (final stop in order) {
    final evaluated = await evaluateCandidateVisit(
      stop,
      day: day,
      from: currentPosition,
      currentTime: currentTime,
      notBefore: notBeforeByStopId[stop.id],
      travelMatrix: travelMatrix,
    );
    if (evaluated == null) {
      unfit.add(stop);
      continue;
    }
    visits.add(evaluated.visit);
    currentPosition = stop;
    currentTime = evaluated.visit.visitEnd;
  }

  final trimmed = await _trimToFitEndAnchor(
    day,
    visits: visits,
    currentTime: currentTime,
    travelMatrix: travelMatrix,
  );
  unfit.addAll(trimmed.cut);

  return DayOrderingResult(
    visits: visits,
    unfitStops: unfit,
    finishTime: trimmed.finishTime,
    travelToEndAnchor: trimmed.travel,
    endAnchorReachable: trimmed.reachable,
  );
}

/// The day must still be able to reach [TripDay.endAnchor] (e.g. back at
/// the hotel) by [TripDay.dailyEnd] — if the last stop in [visits] makes
/// that impossible, cuts it loose (mutating [visits] in place) rather
/// than accepting an unkeepable plan. Shared by [orderDay] and
/// [simulateFixedOrder], which differ only in how [visits] got built.
Future<
  ({
    List<TripStopLocation> cut,
    DateTime finishTime,
    Duration? travel,
    bool reachable,
  })
>
_trimToFitEndAnchor(
  TripDay day, {
  required List<ScheduledVisit> visits,
  required DateTime currentTime,
  required TravelMatrixSource travelMatrix,
}) async {
  final cut = <TripStopLocation>[];
  while (true) {
    final finish = visits.isEmpty ? day.dailyStart : visits.last.visitEnd;
    final from = visits.isEmpty ? day.routeOrigin : visits.last.stop;
    if (day.endAnchor == null || from == null) {
      return (cut: cut, finishTime: finish, travel: null, reachable: true);
    }
    final travel = await travelMatrix.travelTime(from, day.endAnchor!);
    if (travel != null &&
        !travel.isNegative &&
        !finish.add(travel).isAfter(day.dailyEnd)) {
      return (cut: cut, finishTime: finish, travel: travel, reachable: true);
    }
    if (visits.isEmpty) {
      return (cut: cut, finishTime: finish, travel: travel, reachable: false);
    }
    cut.add(visits.removeLast().stop);
  }
}

/// One candidate stop's simulated visit-if-scheduled-here, plus its
/// spec §27 score — [evaluateCandidateVisit]'s result. Exposed (not
/// just an [orderDay]-internal type) since spec §42-43's nearby-
/// recommendation candidate checks (`nearby_recommendation.dart`) need
/// the exact same arrival/opening-hours/weather/meal simulation as the
/// core scheduler, not a separate ad-hoc distance check.
class CandidateEvaluation {
  const CandidateEvaluation({required this.visit, required this.score});
  final ScheduledVisit visit;
  final double score;
}

/// Evaluates visiting [stop] next, from [from] (or nowhere, for the
/// first stop of the day) at [currentTime] — spec §27's score
/// (RoutesAPITravelTime + WaitingTime + OpeningHourPenalty +
/// ClosingRiskPenalty + MealTimePenalty + WeatherTimePenalty, the last
/// only when [TripDay.weatherAvailable] — spec §15/32: never scored on
/// a day the engine has no forecast for). Returns null when [stop]
/// can't be visited at all from here: no route, arriving after every
/// opening window today, or finishing past closing/[TripDay.dailyEnd].
///
/// Used both by [orderDay]/[simulateFixedOrder]'s within-day sequencing
/// and by `nearby_recommendation.dart`'s spec §42-43 candidate checks
/// (calling this once, from the day's last scheduled stop) — the same
/// "would this stop fit here" simulation either way.
Future<CandidateEvaluation?> evaluateCandidateVisit(
  TripStopLocation stop, {
  required TripDay day,
  required TripStopLocation? from,
  required DateTime currentTime,
  required TravelMatrixSource travelMatrix,
  DateTime? notBefore,
}) async {
  if (validateStopForDate(
        stop,
        date: day.date,
        dailyStart: day.dailyStart,
        dailyEnd: day.dailyEnd,
      ) ==
      StopValidationResult.invalid) {
    return null;
  }
  var travel = Duration.zero;
  if (from != null) {
    final duration = await travelMatrix.travelTime(from, stop);
    if (duration == null || duration.isNegative) return null;
    travel = duration;
  }
  final arrival = currentTime.add(travel);
  var earliest = arrival.isBefore(day.dailyStart) ? day.dailyStart : arrival;
  if (notBefore != null && earliest.isBefore(notBefore)) earliest = notBefore;
  var latest = day.dailyEnd;
  final mealType = stop.mealType;
  if (stop.visitPurpose == VisitPurpose.meal && mealType != null) {
    final window = _mealWindows[mealType]!;
    final midnight = DateTime(day.date.year, day.date.month, day.date.day);
    final mealStart = midnight.add(Duration(minutes: window.allowedStart));
    final mealEnd = midnight.add(Duration(minutes: window.allowedEnd));
    if (earliest.isBefore(mealStart)) earliest = mealStart;
    if (latest.isAfter(mealEnd)) latest = mealEnd;
  }
  final duration = Duration(minutes: stop.estimatedVisitDurationMinutes);
  final windows = openingWindowsFor(stop, day.date);
  DateTime? visitStart;
  DateTime? closeTime;
  if (windows == null) {
    if (!earliest.add(duration).isAfter(latest)) visitStart = earliest;
  } else {
    for (final window in windows) {
      final start = earliest.isBefore(window.open) ? window.open : earliest;
      final end = start.add(duration);
      if (!end.isAfter(window.close) && !end.isAfter(latest)) {
        visitStart = start;
        closeTime = window.close;
        break;
      }
    }
  }
  if (visitStart == null) return null;
  final visitEnd = visitStart.add(duration);

  final waitMinutes = visitStart.difference(arrival).inMinutes;
  final closingRisk = closeTime == null
      ? 0.0
      : _closingRiskPenalty(visitEnd, closeTime);
  final mealPenalty = _mealTimePenalty(stop, visitStart);
  final forecast = day.weatherForecast;
  final weatherPenalty = day.weatherAvailable && forecast != null
      ? _weatherTimePenalty(stop, forecast, visitStart)
      : 0.0;

  final score =
      travel.inMinutes.toDouble() +
      waitMinutes.toDouble() +
      closingRisk +
      mealPenalty +
      weatherPenalty;

  return CandidateEvaluation(
    visit: ScheduledVisit(
      stop: stop,
      arrival: arrival,
      visitStart: visitStart,
      visitEnd: visitEnd,
      travelFromPrevious: travel,
    ),
    score: score,
  );
}

double _closingRiskPenalty(DateTime visitEnd, DateTime close) {
  final bufferMinutes = close.difference(visitEnd).inMinutes;
  if (bufferMinutes >= _closingRiskThresholdMinutes) return 0;
  return (_closingRiskThresholdMinutes - bufferMinutes) *
      _closingRiskPenaltyPerMinute;
}

/// Prefer the usual mealtime within the hard meal/opening/day windows already
/// checked by evaluateCandidateVisit.
double _mealTimePenalty(TripStopLocation stop, DateTime visitStart) {
  final mealType = stop.mealType;
  if (stop.visitPurpose != VisitPurpose.meal || mealType == null) return 0;
  final window = _mealWindows[mealType]!;
  final minutesOfDay = visitStart.hour * 60 + visitStart.minute;
  final drift = (minutesOfDay - window.preferredMinutes).abs();
  return drift * _mealDriftPenaltyPerMinute;
}

/// spec §27's WeatherTimePenalty / §32: scores [stop] against whichever
/// of [forecast]'s 3 periods [visitStart] falls into (see
/// [forecastForTime]) — the same day-assignment suitability table spec
/// §14 defines (via [placeWeatherSuitability]), just applied per visit
/// time instead of once for the whole day. Only ever called when
/// [TripDay.weatherAvailable] is true (see [evaluateCandidateVisit]).
double _weatherTimePenalty(
  TripStopLocation stop,
  WeatherForecast forecast,
  DateTime visitStart,
) {
  final condition = weatherConditionFor(forecastForTime(forecast, visitStart));
  final suitability = placeWeatherSuitability(stop.environmentType, condition);
  return switch (suitability) {
    PlaceWeatherSuitability.preferred => _weatherTimePreferredBonus,
    PlaceWeatherSuitability.normal => 0.0,
    PlaceWeatherSuitability.poor => _weatherTimePoorPenalty,
    PlaceWeatherSuitability.avoid => _weatherTimeAvoidPenalty,
  };
}
