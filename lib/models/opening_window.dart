import 'trip_stop_location.dart';

/// A place's opening/closing time on one specific calendar date, derived
/// from [TripStopLocation.openingHoursPeriods]. Three distinct states —
/// don't collapse [isUnconstrained] and [closedAllDay] into "null and
/// treat as open", they mean opposite things for scheduling:
/// - [isUnconstrained]: no opening-hours data at all (most Photon/OSM
///   stops, or a Google place Places just doesn't report hours for) —
///   schedule it whenever, no check needed.
/// - [closedAllDay]: hours data exists but this place doesn't open at
///   all on this date's weekday — can never be scheduled this day,
///   regardless of order.
/// - otherwise [open]/[close] are both set — the window to schedule
///   within.
class OpeningWindow {
  const OpeningWindow.unconstrained() : open = null, close = null, closedAllDay = false;
  const OpeningWindow.closedAllDay() : open = null, close = null, closedAllDay = true;
  const OpeningWindow.window(DateTime openTime, DateTime closeTime)
    : open = openTime,
      close = closeTime,
      closedAllDay = false;

  final DateTime? open;
  final DateTime? close;
  final bool closedAllDay;

  bool get isUnconstrained => open == null && close == null && !closedAllDay;
}

/// Looks up [stop]'s opening/closing time on [date] (only the date part
/// is used) from its machine-readable [TripStopLocation.openingHoursPeriods]
/// — see [OpeningWindow] for what each result state means.
///
/// A close time on a *different* weekday than its matching open period
/// (e.g. a club open Friday 22:00, closing Saturday 02:00) rolls forward
/// onto the following calendar date(s) as needed, rather than assuming
/// same-day close.
OpeningWindow openingWindowOn(TripStopLocation stop, DateTime date) {
  final periods = stop.openingHoursPeriods;
  if (periods == null || periods.isEmpty) {
    return const OpeningWindow.unconstrained();
  }

  // Google's Point.day is 0 (Sunday) .. 6 (Saturday); Dart's
  // DateTime.weekday is 1 (Monday) .. 7 (Sunday) — `% 7` maps Sunday
  // (7) to 0 and leaves Monday (1) .. Saturday (6) unchanged.
  final weekday = date.weekday % 7;
  for (final period in periods) {
    if (period.openDay != weekday) continue;

    final open = DateTime(date.year, date.month, date.day, period.openHour, period.openMinute);
    if (period.closeDay == null) {
      // Places omits `close` for a place open 24 hours starting this
      // period — there's no real closing time to enforce.
      return const OpeningWindow.unconstrained();
    }

    final dayOffset = (period.closeDay! - period.openDay) % 7;
    final closeDate = date.add(Duration(days: dayOffset));
    final close = DateTime(
      closeDate.year,
      closeDate.month,
      closeDate.day,
      period.closeHour!,
      period.closeMinute!,
    );
    return OpeningWindow.window(open, close);
  }

  // Periods exist for other weekdays but none for this one — the place
  // simply doesn't open on this date.
  return const OpeningWindow.closedAllDay();
}
