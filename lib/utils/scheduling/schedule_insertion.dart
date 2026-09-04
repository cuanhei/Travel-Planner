import '../../models/trip_stop_location.dart';
import 'day_ordering.dart';
import 'nearby_recommendation.dart';
import 'travel_matrix.dart';
import 'trip_day.dart';

/// Tries a recommendation on a copy. Existing visits (including meals) keep
/// their start times. Every incoming route and the final anchor are checked.
/// Null means the suggestion has become infeasible; the caller must not save.
Future<DayOrderingResult?> insertIntoGap({
  required TripDay day,
  required DayOrderingResult ordering,
  required ScheduleGap gap,
  required TripStopLocation stop,
  required TravelMatrixSource travelMatrix,
}) async {
  final existing = ordering.visits;
  var index = existing.indexWhere(
    (v) =>
        v.visitStart.isAtSameMomentAs(gap.availableUntil) && v.stop == gap.to,
  );
  if (index < 0) index = existing.length;
  final visits = <ScheduledVisit>[];
  var from = day.routeOrigin ?? (existing.isEmpty ? gap.from : null);
  var time = day.dailyStart;
  for (var i = 0; i <= existing.length; i++) {
    if (i == index) {
      final evaluated = await evaluateCandidateVisit(
        stop,
        day: day,
        from: from,
        currentTime: time,
        travelMatrix: travelMatrix,
      );
      if (evaluated == null) return null;
      visits.add(evaluated.visit);
      from = stop;
      time = evaluated.visit.visitEnd;
    }
    if (i == existing.length) break;
    final old = existing[i];
    final evaluated = await evaluateCandidateVisit(
      old.stop,
      day: day,
      from: from,
      currentTime: time,
      notBefore: old.visitStart,
      travelMatrix: travelMatrix,
    );
    if (evaluated == null || evaluated.visit.visitEnd.isAfter(old.visitEnd)) {
      return null;
    }
    visits.add(evaluated.visit);
    from = old.stop;
    time = evaluated.visit.visitEnd;
  }
  Duration? returnTravel;
  if (day.endAnchor != null && from != null) {
    returnTravel = await travelMatrix.travelTime(from, day.endAnchor!);
    if (returnTravel == null ||
        returnTravel.isNegative ||
        time.add(returnTravel).isAfter(day.dailyEnd)) {
      return null;
    }
  }
  return DayOrderingResult(
    visits: visits,
    unfitStops: const [],
    finishTime: time,
    travelToEndAnchor: returnTravel,
  );
}
