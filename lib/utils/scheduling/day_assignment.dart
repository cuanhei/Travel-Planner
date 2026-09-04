import '../../models/trip_stop_location.dart';
import 'travel_matrix.dart';
import 'trip_day.dart';
import 'validation.dart';
import 'weather_suitability.dart';

/// Penalty weights for [dayAssignmentScore] — spec §24 describes the
/// formula qualitatively ("GeographicTravelPenalty + CapacityPenalty +
/// ClosedDatePenalty + OpeningHourPenalty + MealTimePenalty +
/// WeatherPenalty") without exact constants. These are a reasonable
/// starting point behind named constants; expect a tuning pass once
/// real trips are tested end-to-end — see the implementation plan's
/// flagged risks.
const _timeRestrictionPenalty = 20.0;
const _travelPenaltyPerMinute = 1.0;
const _weatherPreferredBonus = -10.0;
const _weatherPoorPenalty = 15.0;
const _weatherAvoidPenalty = 40.0;

/// A small bonus for landing a meal stop on a day at all — the actual
/// time-of-day fit (spec §31's preferred-window penalty curve) is
/// scored by `day_ordering.dart` once the day's visiting order is
/// known; this term only needs to gently favor *a* day existing for it.
const _mealSlotBonus = -5.0;

/// Long-duration attractions (theme parks, large zoos — spec §19's
/// examples run 4-7 hours) get scheduling priority *before* short
/// flexible ones, so a day never fills up with small stops only to
/// discover later that the big attraction no longer fits anywhere.
const _longDurationThresholdMinutes = 180;

/// [stop]'s suitability score for [day] — spec §24: lower is better.
/// Returns null when [stop] simply cannot go on [day] at all: closed
/// that date (spec §11's INVALID), or [stop]'s visit duration alone
/// exceeds [day]'s remaining capacity (spec §26's hard "Ensure
/// TotalDayDuration <= DailyAvailableDuration" — a coarse pre-filter
/// here since travel time isn't known until `day_ordering.dart` picks
/// an actual order; that pass does the precise arrival/departure
/// simulation and can still bump a stop that seemed to fit).
///
/// [usedMinutes] is the day's visit-duration total from stops already
/// assigned to it earlier in the same [assignStopsToDays] pass.
Future<double?> dayAssignmentScore(
  TripStopLocation stop,
  TripDay day, {
  required TravelMatrixSource travelMatrix,
  required int usedMinutes,
}) async {
  final validation = validateStopForDate(
    stop,
    date: day.date,
    dailyStart: day.dailyStart,
    dailyEnd: day.dailyEnd,
  );
  if (validation == StopValidationResult.invalid) return null;

  final remainingMinutes = day.availableDuration.inMinutes - usedMinutes;
  if (stop.estimatedVisitDurationMinutes > remainingMinutes) return null;

  var score = 0.0;
  if (validation == StopValidationResult.validWithTimeRestriction) {
    score += _timeRestrictionPenalty;
  }

  // Geographic travel penalty: average travel time from every stop
  // already on this day (or its anchors, if still empty) — nudges
  // assignment toward geographic clustering (spec §22) without
  // hard-coding cluster boundaries as a separate pre-pass.
  final reference = <TripStopLocation>[
    ...day.assignedStops,
    if (day.startAnchor != null) day.startAnchor!,
    if (day.endAnchor != null) day.endAnchor!,
  ];
  if (reference.isNotEmpty) {
    final travelTimes = await Future.wait(
      reference.map((r) => travelMatrix.travelTime(r, stop)),
    );
    final known = travelTimes.whereType<Duration>().toList();
    if (known.isNotEmpty) {
      final avgMinutes =
          known.map((d) => d.inMinutes).reduce((a, b) => a + b) /
          known.length;
      score += avgMinutes * _travelPenaltyPerMinute;
    }
  }

  if (day.weatherAvailable) {
    final condition = weatherConditionFor(day.weatherForecast?.summaryForecast);
    final suitability = placeWeatherSuitability(stop.environmentType, condition);
    score += switch (suitability) {
      PlaceWeatherSuitability.preferred => _weatherPreferredBonus,
      PlaceWeatherSuitability.normal => 0,
      PlaceWeatherSuitability.poor => _weatherPoorPenalty,
      PlaceWeatherSuitability.avoid => _weatherAvoidPenalty,
    };
  }

  if (stop.visitPurpose == VisitPurpose.meal) {
    score += _mealSlotBonus;
  }

  return score;
}

/// Assigns every stop in [stops] to whichever [days] entry scores best
/// (spec §23-26), mutating each [TripDay.assignedStops] in place.
/// Processes time-sensitive (meal) and long-duration stops first (spec
/// §18-19), so they claim capacity before short flexible ones can fill
/// a day up around them. Returns the stops that couldn't be placed on
/// *any* day — spec §49's "Unable to Schedule" list, surfaced to the
/// traveler rather than silently dropped.
Future<List<TripStopLocation>> assignStopsToDays(
  List<TripStopLocation> stops,
  List<TripDay> days, {
  required TravelMatrixSource travelMatrix,
}) async {
  if (days.isEmpty) return List.of(stops);

  final ordered = [...stops]
    ..sort((a, b) {
      final priorityCompare = _assignmentPriority(
        a,
      ).compareTo(_assignmentPriority(b));
      if (priorityCompare != 0) return priorityCompare;
      // Within the same tier, longer visits are placed first — spec §19.
      return b.estimatedVisitDurationMinutes.compareTo(
        a.estimatedVisitDurationMinutes,
      );
    });

  final usedMinutesByDay = {for (final day in days) day: 0};
  final unscheduled = <TripStopLocation>[];

  for (final stop in ordered) {
    TripDay? bestDay;
    double? bestScore;
    for (final day in days) {
      final score = await dayAssignmentScore(
        stop,
        day,
        travelMatrix: travelMatrix,
        usedMinutes: usedMinutesByDay[day]!,
      );
      if (score == null) continue;
      if (bestScore == null || score < bestScore) {
        bestScore = score;
        bestDay = day;
      }
    }
    if (bestDay == null) {
      unscheduled.add(stop);
      continue;
    }
    bestDay.assignedStops.add(stop);
    usedMinutesByDay[bestDay] =
        usedMinutesByDay[bestDay]! + stop.estimatedVisitDurationMinutes;
  }
  return unscheduled;
}

/// Lower sorts first (assigned before). 0 = meal/time-sensitive, 1 =
/// long-duration attraction, 2 = everything else.
int _assignmentPriority(TripStopLocation stop) {
  if (stop.visitPurpose == VisitPurpose.meal) return 0;
  if (stop.estimatedVisitDurationMinutes >= _longDurationThresholdMinutes) {
    return 1;
  }
  return 2;
}
