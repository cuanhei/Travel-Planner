import '../../models/trip_stop_location.dart';
import 'opening_windows.dart';
import 'place_identity.dart';

/// Whether a stop can be visited on a given date within a given daily
/// time window — spec §11. [invalid] means don't schedule this stop
/// here at all; [validWithTimeRestriction] means it's schedulable but
/// only within part of the daily window (the visit must be timed to
/// the place's actual open period, not the full day).
enum StopValidationResult { valid, invalid, validWithTimeRestriction }

/// Validates [stop] for a single [date] against [dailyStart]/
/// [dailyEnd] (that day's `TripDay.dailyStart`/`dailyEnd`) — spec §11's
/// checks: operational, open this date, opening period overlaps the
/// daily window, and (implicitly, since a period entirely outside the
/// daily window can't be visited at all) whether any open period
/// exists within it.
///
/// A stop with no [TripStopLocation.openingPeriods] at all (a Photon-
/// sourced stop, or a Google result Places had no hours for) can't be
/// ruled out one way or the other, so it's treated as [valid] — the
/// spec's validation is about catching *known* closures, not
/// penalizing stops the app simply has no hours data for.
StopValidationResult validateStopForDate(
  TripStopLocation stop, {
  required DateTime date,
  required DateTime dailyStart,
  required DateTime dailyEnd,
}) {
  if (stop.businessStatus == 'CLOSED_PERMANENTLY' ||
      stop.businessStatus == 'CLOSED_TEMPORARILY') {
    return StopValidationResult.invalid;
  }

  if (!hasValidCoordinates(stop) ||
      stop.estimatedVisitDurationMinutes <= 0 ||
      !dailyStart.isBefore(dailyEnd)) {
    return StopValidationResult.invalid;
  }
  final windows = openingWindowsFor(stop, date);
  if (windows == null) return StopValidationResult.valid;
  var overlaps = false;
  for (final window in windows) {
    if (!window.open.isAfter(dailyStart) && !window.close.isBefore(dailyEnd)) {
      return StopValidationResult.valid;
    }
    if (window.open.isBefore(dailyEnd) && window.close.isAfter(dailyStart)) {
      overlaps = true;
    }
  }
  return overlaps
      ? StopValidationResult.validWithTimeRestriction
      : StopValidationResult.invalid;
}

/// Whether [stop] is schedulable on *any* date in [tripDates] — spec
/// §11's "closed during the entire trip" check, surfaced to the
/// traveler as "Unable to Schedule" rather than silently dropped.
bool isSchedulableAnyDate(
  TripStopLocation stop,
  Iterable<({DateTime date, DateTime dailyStart, DateTime dailyEnd})> tripDates,
) {
  for (final d in tripDates) {
    final result = validateStopForDate(
      stop,
      date: d.date,
      dailyStart: d.dailyStart,
      dailyEnd: d.dailyEnd,
    );
    if (result != StopValidationResult.invalid) return true;
  }
  return false;
}
