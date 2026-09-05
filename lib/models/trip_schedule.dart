import 'nearby_place.dart';
import 'trip_schedule_input.dart';
import 'trip_stop_location.dart';

class TripSchedule {
  const TripSchedule({
    required this.transportMode,
    required this.tripStartTime,
    required this.tripEndTime,
    required this.days,
  });

  final String transportMode;

  final String? tripStartTime;
  final String? tripEndTime;

  final List<TripScheduleDay> days;
}

class TripScheduleDay {
  const TripScheduleDay({
    required this.dayNumber,
    required this.date,
    required this.startTimeOverride,
    required this.stops,
    required this.legs,
  });

  final int dayNumber;
  final DateTime date;

  final String? startTimeOverride;

  final List<TripScheduleStop> stops;

  final List<TripScheduleLeg> legs;
}

class TripScheduleStop {
  const TripScheduleStop({
    required this.location,
    required this.sequence,
    required this.visitMinutes,
    required this.arrivalMinutes,
    required this.endMinutes,
    required this.weatherFlagged,
    required this.weatherBadPeriods,
    this.weatherForecastPhrase,
  });

  final TripStopLocation location;
  final int sequence;
  final int visitMinutes;

  final int arrivalMinutes;
  final int endMinutes;

  final bool weatherFlagged;
  final List<String> weatherBadPeriods;
  final String? weatherForecastPhrase;

  factory TripScheduleStop.fromMap(Map<String, dynamic> row) {
    final periods = row['opening_hours_periods'] as List?;
    return TripScheduleStop(
      location: TripStopLocation(
        id: row['id'] as String?,
        name: row['name'] as String,
        address: (row['address'] as String?) ?? '',
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        osmId: row['osm_id'] as String?,
        category: (row['category'] as String?) ?? 'Other',
        placeId: row['place_id'] as String?,
        primaryType: row['primary_type'] as String?,
        types: [
          for (final t in (row['types'] as List?) ?? const []) t as String,
        ],
        businessStatus: row['business_status'] as String?,
        regularOpeningHours: [
          for (final h in (row['opening_hours'] as List?) ?? const [])
            h as String,
        ],
        regularOpeningHoursPeriods: periods == null
            ? null
            : [
                for (final p in periods)
                  OpeningHoursPeriod.fromJson(p as Map<String, dynamic>),
              ],
      ),
      sequence: row['sequence'] as int,
      visitMinutes: (row['visit_minutes'] as num?)?.toInt() ?? 0,
      arrivalMinutes: (row['arrival_minutes'] as num?)?.toInt() ?? 0,
      endMinutes: (row['end_minutes'] as num?)?.toInt() ?? 0,
      weatherFlagged: (row['weather_flagged'] as bool?) ?? false,
      weatherBadPeriods: [
        for (final p in (row['weather_bad_periods'] as List?) ?? const [])
          p as String,
      ],
      weatherForecastPhrase: row['weather_forecast_phrase'] as String?,
    );
  }
}

class TripScheduleLeg {
  const TripScheduleLeg({
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

  factory TripScheduleLeg.fromMap(Map<String, dynamic> row) {
    return TripScheduleLeg(
      sequence: row['sequence'] as int,
      fromName: row['from_name'] as String,
      fromLatitude: (row['from_latitude'] as num).toDouble(),
      fromLongitude: (row['from_longitude'] as num).toDouble(),
      toName: row['to_name'] as String,
      toLatitude: (row['to_latitude'] as num).toDouble(),
      toLongitude: (row['to_longitude'] as num).toDouble(),
      legKind: _legKindFromColumn(row['leg_kind'] as String),
      transportMode: row['transport_mode'] as String,
      durationMinutes: (row['duration_minutes'] as num?)?.toInt(),
    );
  }
}

TripLegKind _legKindFromColumn(String column) {
  switch (column) {
    case 'accommodation':
      return TripLegKind.accommodation;
    case 'trip_end':
      return TripLegKind.tripEnd;
    default:
      return TripLegKind.stop;
  }
}
