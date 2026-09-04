import '../../models/trip_stop_location.dart';

typedef OpeningWindow = ({DateTime open, DateTime close});

/// Null means unknown hours; an empty list means known closed on this date.
/// Include yesterday's overnight periods and Google's no-close 24/7 format.
List<OpeningWindow>? openingWindowsFor(TripStopLocation stop, DateTime date) {
  final periods = stop.openingPeriods;
  if (periods == null || periods.isEmpty) return null;
  final midnight = DateTime(date.year, date.month, date.day);
  final tomorrow = midnight.add(const Duration(days: 1));
  final windows = <OpeningWindow>[];
  for (final period in periods) {
    if (period.isOpenAllDay) {
      return [(open: midnight, close: tomorrow)];
    }
    // Include a full previous week, since a weekly period can span days.
    for (var offset = -7; offset <= 0; offset++) {
      final openingDate = midnight.add(Duration(days: offset));
      if (openingDate.weekday % 7 != period.openDay) continue;
      final open = openingDate.add(
        Duration(hours: period.openHour, minutes: period.openMinute),
      );
      var daysUntilClose =
          ((period.closeDay ?? period.openDay) - period.openDay) % 7;
      if (daysUntilClose == 0 &&
          period.closeHour! * 60 + period.closeMinute! <=
              period.openHour * 60 + period.openMinute) {
        daysUntilClose = 1;
      }
      final close = openingDate.add(
        Duration(
          days: daysUntilClose,
          hours: period.closeHour!,
          minutes: period.closeMinute!,
        ),
      );
      if (open.isBefore(tomorrow) && close.isAfter(midnight)) {
        windows.add((open: open, close: close));
      }
    }
  }
  windows.sort((a, b) => a.open.compareTo(b.open));
  return windows;
}
