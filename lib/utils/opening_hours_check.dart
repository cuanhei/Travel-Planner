import '../models/nearby_place.dart';

bool isClosedDuringVisit({
  required List<OpeningHoursPeriod>? periods,
  required DateTime date,
  required int arrivalMinutes,
  required int endMinutes,
}) {
  if (periods == null || periods.isEmpty) return false;
  if (endMinutes <= arrivalMinutes) return false;

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
      closeAbsolute = openAbsolute + 1440;
    } else {
      closeAbsolute =
          (period.closeDay ?? period.openDay) * 1440 +
          (period.closeHour ?? 0) * 60 +
          (period.closeMinute ?? 0);

      if (closeAbsolute <= openAbsolute) closeAbsolute += 7 * 1440;
    }

    for (final shift in [-7 * 1440, 0, 7 * 1440]) {
      final start = openAbsolute + shift;
      final end = closeAbsolute + shift;
      if (start <= targetStart && end >= targetEnd) return false;
    }
  }
  return true;
}
