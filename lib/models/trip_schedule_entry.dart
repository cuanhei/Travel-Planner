/// One row of a trip's saved day-by-day schedule — backed by
/// `trip_schedule_stops` joined with `trip_stops` for the place's own
/// details. Covers every position on a day's route: the day's start
/// anchor, each visited stop, and the end anchor (which may be a hotel
/// — see [isHotel]), all as flat, ordered rows rather than the
/// [TripDay]/[DaySchedule] shape used while a trip is still being
/// planned (see `trip_day.dart`/`day_schedule.dart`) — by the time this
/// is read back, the schedule is just data to display, not something
/// still being computed.
class TripScheduleEntry {
  const TripScheduleEntry({
    required this.dayNumber,
    required this.sequence,
    required this.isHotel,
    required this.stopName,
    required this.stopAddress,
    required this.category,
    this.scheduledArrival,
    this.scheduledDeparture,
    this.travelMode,
    this.travelMinutes,
  });

  final int dayNumber;

  /// Order within the day — 0 is always the day's start anchor.
  final int sequence;

  /// True when this position is an accommodation (the overall trip
  /// start/end are never hotels; a day-boundary anchor in between
  /// always is — see `TripDay.startIsOverallStart`/`endIsOverallEnd`
  /// from planning time).
  final bool isHotel;

  final String stopName;
  final String stopAddress;

  /// Coarse category (e.g. "Shopping", "Food") — see
  /// `iconForCategory` in `trip_stop_location.dart` for the icon this
  /// maps to.
  final String category;

  /// Raw `HH:mm:ss` time-of-day strings from Postgres' `time` column —
  /// null where that end of the visit doesn't apply (the day's start
  /// anchor has no arrival; the end anchor has no departure).
  final String? scheduledArrival;
  final String? scheduledDeparture;

  /// Null for the very first row of a day (nothing precedes the start
  /// anchor) or when the previous position was the exact same place
  /// (no travel needed).
  final String? travelMode;
  final int? travelMinutes;

  factory TripScheduleEntry.fromMap(Map<String, dynamic> map) {
    final stop = map['trip_stops'] as Map<String, dynamic>?;
    return TripScheduleEntry(
      dayNumber: map['day_number'] as int,
      sequence: map['sequence'] as int,
      isHotel: map['is_hotel'] as bool? ?? false,
      stopName: (stop?['name'] as String?) ?? 'Stop',
      stopAddress: (stop?['address'] as String?) ?? '',
      category: (stop?['category'] as String?) ?? 'Other',
      scheduledArrival: map['scheduled_arrival'] as String?,
      scheduledDeparture: map['scheduled_departure'] as String?,
      travelMode: map['travel_mode'] as String?,
      travelMinutes: (map['travel_minutes'] as num?)?.toInt(),
    );
  }
}
