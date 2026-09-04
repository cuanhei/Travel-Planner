/// One open→close window within a place's weekly schedule, from Google
/// Places API (New)'s structured `regularOpeningHours.periods` /
/// `currentOpeningHours.periods` — e.g. a restaurant open 11:00–22:00 on
/// Mondays. Kept as a distinct machine-checkable shape from the
/// pre-formatted `weekdayDescriptions` strings (e.g. `"Monday: 9:00 AM –
/// 6:00 PM"`) those same responses also carry: the strings are locale-
/// dependent display text, not something a scheduling engine should
/// parse back apart to check "is this place open at 14:30 on day 3".
///
/// [openDay]/[closeDay] follow Google's convention: 0 = Sunday .. 6 =
/// Saturday. A period with no close time at all means the place never
/// closes from this open time — Google's representation of a 24-hour
/// place.
class OpeningPeriod {
  const OpeningPeriod({
    required this.openDay,
    required this.openHour,
    required this.openMinute,
    this.closeDay,
    this.closeHour,
    this.closeMinute,
  });

  final int openDay;
  final int openHour;
  final int openMinute;

  final int? closeDay;
  final int? closeHour;
  final int? closeMinute;

  /// True when this period never closes (a 24-hour place) — Google
  /// omits `close` entirely for that case rather than sending a
  /// same-as-open close time.
  bool get isOpenAllDay => closeDay == null;

  factory OpeningPeriod.fromJson(Map<String, dynamic> json) {
    final open = json['open'] as Map<String, dynamic>;
    final close = json['close'] as Map<String, dynamic>?;
    return OpeningPeriod(
      openDay: open['day'] as int,
      openHour: open['hour'] as int,
      openMinute: open['minute'] as int,
      closeDay: close?['day'] as int?,
      closeHour: close?['hour'] as int?,
      closeMinute: close?['minute'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'open': {'day': openDay, 'hour': openHour, 'minute': openMinute},
    if (!isOpenAllDay)
      'close': {'day': closeDay, 'hour': closeHour, 'minute': closeMinute},
  };
}

/// Parses the `periods` array out of a raw `regularOpeningHours` or
/// `currentOpeningHours` JSON object (as already decoded from a Places
/// API (New) response) — null if that object is null or has no periods.
List<OpeningPeriod>? parseOpeningPeriods(Map<String, dynamic>? hours) {
  final periods = hours?['periods'] as List?;
  if (periods == null) return null;
  return [
    for (final p in periods) OpeningPeriod.fromJson(p as Map<String, dynamic>),
  ];
}
