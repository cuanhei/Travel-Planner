import '../models/nearby_place.dart';

/// True if [periods] don't fully cover the visit window
/// `[arrivalMinutes, endMinutes)` on [date] — i.e. the place is expected
/// to be closed for at least part of the planned visit. [arrivalMinutes]/
/// [endMinutes] are minutes since that day's own midnight (may exceed
/// 1440 for a plan that runs past it, matching the rest of the app's
/// clock arithmetic elsewhere — see `_computeDayTimes`).
///
/// Always false when [periods] is null/empty: a Photon/OSM-sourced stop
/// carries no opening-hours data at all, so there's nothing to flag —
/// only a Google Places result ([TripStopLocation.openingHoursPeriods])
/// can ever be checked.
bool isClosedDuringVisit({
  required List<OpeningHoursPeriod>? periods,
  required DateTime date,
  required int arrivalMinutes,
  required int endMinutes,
}) {
  if (periods == null || periods.isEmpty) return false;
  if (endMinutes <= arrivalMinutes) return false;

  // Google's Point.day: 0 = Sunday .. 6 = Saturday. Dart's DateTime.weekday
  // is 1 = Monday .. 7 = Sunday, so `% 7` maps Sunday (7) to 0 and every
  // other day to itself.
  final googleDay = date.weekday % 7;
  final targetStart = googleDay * 1440 + arrivalMinutes;
  final targetEnd = googleDay * 1440 + endMinutes;

  for (final period in periods) {
    final openAbsolute =
        period.openDay * 1440 + period.openHour * 60 + period.openMinute;
    int closeAbsolute;
    if (period.closeDay == null &&
        period.closeHour == null &&
        period.closeMinute == null) {
      // No close time at all means open 24 hours starting that day.
      closeAbsolute = openAbsolute + 1440;
    } else {
      closeAbsolute =
          (period.closeDay ?? period.openDay) * 1440 +
          (period.closeHour ?? 0) * 60 +
          (period.closeMinute ?? 0);
      // Closing time is on/before the opening time within the same
      // week's numbering — it actually closes the following week (e.g.
      // a period open Saturday, closing Sunday wraps day 6 -> day 0).
      if (closeAbsolute <= openAbsolute) closeAbsolute += 7 * 1440;
    }
    // Check this period against the target both in its own week and
    // shifted a week either direction, so a period anchored near the
    // week boundary (e.g. "opens Saturday") still covers a target near
    // the opposite boundary (e.g. "visit is early Sunday").
    for (final shift in [-7 * 1440, 0, 7 * 1440]) {
      final start = openAbsolute + shift;
      final end = closeAbsolute + shift;
      if (start <= targetStart && end >= targetEnd) return false;
    }
  }
  return true;
}
