import 'package:latlong2/latlong.dart';

import '../../models/nearby_place.dart';
import '../../models/trip_stop_location.dart';
import '../../services/google_places_service.dart';
import 'day_ordering.dart';
import 'travel_matrix.dart';
import 'trip_day.dart';
import 'validation.dart';

const _mealTypesInOrder = [MealType.breakfast, MealType.lunch, MealType.dinner];

/// spec §10-11/§31: for a day whose non-meal stops are already assigned
/// and ordered, finds a real restaurant for every meal (breakfast,
/// lunch, dinner) the traveler hasn't already picked one for themselves
/// — spec §6: a user-selected stop is never silently replaced, so any
/// meal [ordering]/[day.assignedStops] already covers is left alone. A
/// meal whose spec §31 allowed window doesn't overlap [day]'s
/// dailyStart/dailyEnd at all is skipped outright — there's no time of
/// day left to put it.
///
/// Searches near whichever already-scheduled stop (or day start/end
/// anchor) the traveler would be at/near around that meal's preferred
/// clock time (see [preferredMealMinutes]), evaluates every candidate
/// with the same [evaluateCandidateVisit] simulation the core scheduler
/// scores every other stop with — a closed or unreachable-in-time
/// candidate is never picked — and returns at most one winner per still
/// -missing meal (never more than 3 stops total). The caller is
/// responsible for adding the result to [TripDay.assignedStops] and
/// re-running `orderDay`/`simulateFixedOrder` afterward (same pattern
/// as `nearby_recommendation.dart`'s add flow): the exact arrival/visit
/// time used to pick a winner here is only an approximation of where it
/// will actually land once the day is re-sequenced with it included.
Future<List<TripStopLocation>> planMissingMeals({
  required TripDay day,
  required DayOrderingResult ordering,
  required TravelMatrixSource travelMatrix,
  GooglePlacesService? placesService,
}) async {
  final covered = <MealType>{
    for (final stop in day.assignedStops)
      if (stop.visitPurpose == VisitPurpose.meal && stop.mealType != null)
        stop.mealType!,
  };
  if (covered.length == _mealTypesInOrder.length) return const [];

  final dailyStartMinutes = day.dailyStart.hour * 60 + day.dailyStart.minute;
  final dailyEndMinutes = day.dailyEnd.hour * 60 + day.dailyEnd.minute;

  final places = placesService ?? GooglePlacesService();
  final planned = <TripStopLocation>[];

  for (final mealType in _mealTypesInOrder) {
    if (covered.contains(mealType)) continue;

    final allowed = mealAllowedWindow(mealType);
    final overlapsDay =
        allowed.allowedStart < dailyEndMinutes &&
        allowed.allowedEnd > dailyStartMinutes;
    if (!overlapsDay) continue;

    final reference = _referenceStopAndTime(
      day,
      ordering,
      preferredMealMinutes(mealType),
    );
    if (reference == null) continue;

    List<NearbyPlace> found;
    try {
      found = await places.nearbySearch(
        center: LatLng(reference.stop.latitude, reference.stop.longitude),
        includedTypes: const {'restaurant'},
      );
    } catch (_) {
      continue;
    }

    CandidateEvaluation? best;
    for (final place in found) {
      final stop = TripStopLocation.fromNearbyPlace(place).copyWith(
        visitPurpose: VisitPurpose.meal,
        mealType: mealType,
        estimatedVisitDurationMinutes: mealType == MealType.breakfast ? 45 : 60,
      );

      if (stop.businessStatus == 'CLOSED_PERMANENTLY' ||
          stop.businessStatus == 'CLOSED_TEMPORARILY') {
        continue;
      }
      if (validateStopForDate(
            stop,
            date: day.date,
            dailyStart: day.dailyStart,
            dailyEnd: day.dailyEnd,
          ) ==
          StopValidationResult.invalid) {
        continue;
      }

      final evaluated = await evaluateCandidateVisit(
        stop,
        day: day,
        from: reference.stop,
        currentTime: reference.time,
        travelMatrix: travelMatrix,
      );
      if (evaluated == null) continue;
      if (best == null || evaluated.score < best.score) best = evaluated;
    }
    if (best != null) planned.add(best.visit.stop);
  }

  return planned;
}

/// The stop the traveler would be at (or just leaving) around
/// [preferredMinutesOfDay], to search near — the latest visit that's
/// already started by then, departing when that visit ends; the day's
/// start anchor departing at [TripDay.dailyStart] if the preferred time
/// falls before the first visit even starts (or there are no visits at
/// all yet); null only when there's truly nothing to search near.
({TripStopLocation stop, DateTime time})? _referenceStopAndTime(
  TripDay day,
  DayOrderingResult ordering,
  int preferredMinutesOfDay,
) {
  if (ordering.visits.isEmpty) {
    final anchor = day.routeOrigin ?? day.endAnchor;
    return anchor == null ? null : (stop: anchor, time: day.dailyStart);
  }

  final preferredTime = DateTime(
    day.date.year,
    day.date.month,
    day.date.day,
    preferredMinutesOfDay ~/ 60,
    preferredMinutesOfDay % 60,
  );
  ScheduledVisit? latestBefore;
  for (final visit in ordering.visits) {
    if (!visit.visitStart.isAfter(preferredTime)) {
      latestBefore = visit;
    } else {
      break;
    }
  }
  if (latestBefore != null) {
    return (stop: latestBefore.stop, time: latestBefore.visitEnd);
  }

  final startAnchor = day.routeOrigin;
  if (startAnchor != null) return (stop: startAnchor, time: day.dailyStart);
  final first = ordering.visits.first;
  return (stop: first.stop, time: first.arrival);
}
