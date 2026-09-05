import '../models/day_schedule.dart';
import '../models/opening_window.dart';
import '../models/place_environment.dart';
import '../models/trip_stop_location.dart';

/// Final safety-net pass over the finished pipeline output (day anchors
/// → duration/environment → geographic clustering → route order →
/// opening hours/travel/duration → weather adjustment → gap filling).
/// Everything checked here should already hold by construction — this
/// doesn't fix anything, it just surfaces a description of anything
/// that slipped through, so a bug earlier in the pipeline is caught
/// here rather than silently reaching the traveler as a broken
/// itinerary.
///
/// Returns an empty list when everything checks out.
List<String> validateItinerary(List<DaySchedule> schedules) {
  final issues = <String>[];
  final seenStops = <TripStopLocation>{};

  for (final schedule in schedules) {
    final day = schedule.day;
    DateTime? previousVisitEnd;

    for (final scheduled in schedule.scheduledStops) {
      final stop = scheduled.stop;

      // Every scheduled stop appears once (trip-wide, not just per day).
      if (!seenStops.add(stop)) {
        issues.add(
          'Day ${day.dayNumber}: "${stop.name}" is scheduled more than once.',
        );
      }

      // No overlapping stops.
      if (previousVisitEnd != null &&
          scheduled.arrival.isBefore(previousVisitEnd)) {
        issues.add(
          'Day ${day.dayNumber}: "${stop.name}" overlaps with the '
          'previous stop.',
        );
      }
      previousVisitEnd = scheduled.visitEnd;

      // Opening hours valid; visit finishes before closing.
      final window = openingWindowOn(stop, day.date);
      if (window.closedAllDay) {
        issues.add(
          'Day ${day.dayNumber}: "${stop.name}" is scheduled on a day '
          "it's closed.",
        );
      } else if (!window.isUnconstrained) {
        if (window.open != null && scheduled.visitStart.isBefore(window.open!)) {
          issues.add(
            'Day ${day.dayNumber}: "${stop.name}" starts before opening.',
          );
        }
        if (window.close != null &&
            scheduled.visitEnd.isAfter(window.close!)) {
          issues.add(
            'Day ${day.dayNumber}: "${stop.name}" ends after closing.',
          );
        }
      }

      // Travel time included.
      if (scheduled.travelMinutesFromPrevious < 0) {
        issues.add(
          'Day ${day.dayNumber}: "${stop.name}" has a negative travel '
          'time from the previous stop.',
        );
      }

      // Weather constraints satisfied — an outdoor stop should never
      // have been scheduled at all if it couldn't avoid bad weather
      // (see DayScheduleService/WeatherAdjustmentService), so this
      // flag should never be true for one.
      final environment = getEnvironment(stop.primaryType, stop.types);
      if (environment == PlaceEnvironment.outdoor &&
          scheduled.hasWeatherConcern) {
        issues.add(
          'Day ${day.dayNumber}: "${stop.name}" is outdoor but flagged '
          'with a weather concern — it should have been moved instead.',
        );
      }
    }

    // Hotel/end anchor is reached before midnight the next calendar day.
    final midnight = DateTime(
      day.date.year,
      day.date.month,
      day.date.day,
    ).add(const Duration(days: 1));
    if (!schedule.endArrival.isBefore(midnight)) {
      issues.add(
        'Day ${day.dayNumber}: arrival at "${day.endAnchor.name}" '
        '(${schedule.endArrival}) is not before midnight.',
      );
    }

    // Unscheduled stops retained with a reason, not silently dropped.
    for (final unscheduled in schedule.unscheduledStops) {
      if (unscheduled.reason.trim().isEmpty) {
        issues.add(
          'Day ${day.dayNumber}: "${unscheduled.stop.name}" is '
          'unscheduled with no reason recorded.',
        );
      }
    }
  }

  return issues;
}
