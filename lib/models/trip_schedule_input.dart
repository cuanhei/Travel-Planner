import 'trip_stop_location.dart';

class TripDayInput {
  const TripDayInput({
    required this.dayNumber,
    required this.date,
    this.startTimeOverride,
  });

  final int dayNumber;
  final DateTime date;

  final String? startTimeOverride;
}

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

  final int sequence;

  final TripStopLocation location;
  final int visitMinutes;

  final int arrivalMinutes;
  final int endMinutes;

  final bool weatherFlagged;

  final List<String> weatherBadPeriods;
  final String? weatherForecastPhrase;
  final DateTime? weatherCheckedAt;
}

enum TripLegKind { stop, accommodation, tripEnd }

extension TripLegKindColumn on TripLegKind {
  String get column => switch (this) {
    TripLegKind.stop => 'stop',
    TripLegKind.accommodation => 'accommodation',
    TripLegKind.tripEnd => 'trip_end',
  };
}

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

  final int sequence;

  final String fromName;
  final double fromLatitude;
  final double fromLongitude;

  final String toName;
  final double toLatitude;
  final double toLongitude;

  final TripLegKind legKind;

  final String transportMode;

  final int? durationMinutes;
}
