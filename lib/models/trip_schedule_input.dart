import 'trip_stop_location.dart';

/// One day tab's own row — its date and, for any day after the first, an
/// optional override of the trip's start time. Mirrors `trip_days`.
class TripDayInput {
  const TripDayInput({
    required this.dayNumber,
    required this.date,
    this.startTimeOverride,
  });

  final int dayNumber;
  final DateTime date;

  /// "HH:mm" (24-hour), or null to mean "use the trip's own start time" —
  /// always null for Day 1, which never has its own override.
  final String? startTimeOverride;
}

/// One scheduled stop, in the shape `trip_stops`' schedule columns need.
/// Mirrors a single `_StopEntry` plus its computed arrival/end time and
/// weather check from Create Trip's timeline.
class TripStopInput {
  const TripStopInput({
    required this.dayNumber,
    required this.sequence,
    required this.location,
    required this.visitMinutes,
    required this.arrivalMinutes,
    required this.endMinutes,
    this.weatherFlagged = false,
    this.weatherBadPeriods = const [],
    this.weatherForecastPhrase,
    this.weatherCheckedAt,
  });

  final int dayNumber;

  /// 0-indexed position within [dayNumber] — also how a same-day
  /// [TripTravelSegmentInput] with `legKind: TripLegKind.stop` finds the
  /// `trip_stops` row it arrives at (that leg's own `sequence`).
  final int sequence;

  final TripStopLocation location;
  final int visitMinutes;

  /// Minutes since that day's midnight — may exceed 1440 for a plan that
  /// runs past it, matching the app's own clock arithmetic.
  final int arrivalMinutes;
  final int endMinutes;

  final bool weatherFlagged;

  /// Lowercase period names (subset of "morning"/"afternoon"/"night")
  /// forecast as rain/thunderstorm during this stop's visit window.
  final List<String> weatherBadPeriods;
  final String? weatherForecastPhrase;
  final DateTime? weatherCheckedAt;
}

/// What kind of destination a travel leg ends at — matches
/// `trip_travel_segments.leg_kind`'s check constraint.
enum TripLegKind { stop, accommodation, tripEnd }

extension TripLegKindColumn on TripLegKind {
  String get column => switch (this) {
    TripLegKind.stop => 'stop',
    TripLegKind.accommodation => 'accommodation',
    TripLegKind.tripEnd => 'trip_end',
  };
}

/// One travel leg actually shown in a day's timeline. Mirrors a single
/// `_TravelSegment` plus its resolved endpoints.
class TripTravelSegmentInput {
  const TripTravelSegmentInput({
    required this.dayNumber,
    required this.sequence,
    required this.fromName,
    required this.fromLatitude,
    required this.fromLongitude,
    required this.toName,
    required this.toLatitude,
    required this.toLongitude,
    required this.legKind,
    required this.transportMode,
    this.durationMinutes,
  });

  final int dayNumber;

  /// 0-indexed position within the day — for `legKind: TripLegKind.stop`,
  /// this is also the destination stop's own `sequence` within the same
  /// day, letting [TripService.saveTripSchedule] resolve `to_stop_id`
  /// without a separate lookup key.
  final int sequence;

  final String fromName;
  final double fromLatitude;
  final double fromLongitude;

  final String toName;
  final double toLatitude;
  final double toLongitude;

  final TripLegKind legKind;

  /// "driving" or "transit" — matches `trips.transport_mode` /
  /// `trip_travel_segments.transport_mode`'s check constraint.
  final String transportMode;

  /// Null means the leg's travel time couldn't be computed, not an
  /// actual zero-duration leg.
  final int? durationMinutes;
}
