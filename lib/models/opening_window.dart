import 'trip_stop_location.dart';

class OpeningWindow {
  const OpeningWindow.unconstrained()
    : open = null,
      close = null,
      closedAllDay = false;
  const OpeningWindow.closedAllDay()
    : open = null,
      close = null,
      closedAllDay = true;
  const OpeningWindow.window(DateTime openTime, DateTime closeTime)
    : open = openTime,
      close = closeTime,
      closedAllDay = false;

  final DateTime? open;
  final DateTime? close;
  final bool closedAllDay;

  bool get isUnconstrained => open == null && close == null && !closedAllDay;
}

OpeningWindow openingWindowOn(TripStopLocation stop, DateTime date) {
  final periods = stop.openingHoursPeriods;
  if (periods == null || periods.isEmpty) {
    return const OpeningWindow.unconstrained();
  }

  final weekday = date.weekday % 7;
  for (final period in periods) {
    if (period.openDay != weekday) continue;

    final open = DateTime(
      date.year,
      date.month,
      date.day,
      period.openHour,
      period.openMinute,
    );
    if (period.closeDay == null) {
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

  return const OpeningWindow.closedAllDay();
}
