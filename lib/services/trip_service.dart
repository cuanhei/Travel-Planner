import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trip.dart';
import '../models/trip_schedule.dart';
import '../models/trip_schedule_input.dart';
import '../models/trip_stop_location.dart';
import 'supabase_config.dart';

const _defaultCategoryPlan = {
  'Accommodation': 600.0,
  'Food & Drinks': 350.0,
  'Transport': 150.0,
  'Shopping': 300.0,
  'Activities': 100.0,
};

class TripService {
  TripService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  static final ValueNotifier<int> tripsChanged = ValueNotifier<int>(0);

  static String? _cachedTripId;
  static Future<String>? _inFlight;

  String get _uid => _client.auth.currentUser!.id;

  Future<String> ensureDemoTrip() {
    final cached = _cachedTripId;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _resolve().whenComplete(() => _inFlight = null);
  }

  Future<String> _resolve() async {
    final membership = await retryOnJwtClockSkew(
      () => _client
          .from('trip_members')
          .select('trip_id')
          .eq('user_id', _uid)
          .order('joined_at', ascending: true)
          .limit(1)
          .maybeSingle(),
    );
    if (membership != null) {
      final tripId = membership['trip_id'] as String;
      _cachedTripId = tripId;
      return tripId;
    }

    final today = DateTime.now();
    final trip = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .insert({
            'name': 'Penang Adventure',
            'destination': 'Penang, Malaysia',
            'start_date': today.toIso8601String().split('T').first,
            'end_date': today
                .add(const Duration(days: 2))
                .toIso8601String()
                .split('T')
                .first,
            'created_by': _uid,
            'total_budget': _defaultCategoryPlan.values.fold<double>(
              0,
              (sum, v) => sum + v,
            ),
          })
          .select()
          .single(),
    );
    final tripId = trip['id'] as String;

    await retryOnJwtClockSkew(
      () => _client.from('budget_categories').insert([
        for (final entry in _defaultCategoryPlan.entries)
          {
            'trip_id': tripId,
            'label': entry.key,
            'planned_amount': entry.value,
          },
      ]),
    );

    _cachedTripId = tripId;
    tripsChanged.value++;
    return tripId;
  }

  Future<String> createTrip({
    required String name,
    String? description,
    String? destination,
    String? startLocationName,
    String? startAddress,
    double? startLatitude,
    double? startLongitude,
    String? endLocationName,
    String? endAddress,
    double? endLatitude,
    double? endLongitude,
    DateTime? startDate,
    DateTime? endDate,
    String? startTime,
    String? endTime,
    required double totalBudget,

    String transportMode = 'driving',

    List<TripStopLocation> accommodations = const [],
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Trip name cannot be empty.');
    }
    final session = _client.auth.currentSession;
    debugPrint(
      'createTrip: uid=$_uid session=${session != null} '
      'expired=${session?.isExpired}',
    );
    final row = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .insert({
            'name': trimmedName,
            'description': description,
            'destination': destination ?? '',
            'start_location_name': startLocationName,
            'start_address': startAddress,
            'start_latitude': startLatitude,
            'start_longitude': startLongitude,
            'end_location_name': endLocationName,
            'end_address': endAddress,
            'end_latitude': endLatitude,
            'end_longitude': endLongitude,
            'start_date': startDate?.toIso8601String().split('T').first,
            'end_date': endDate?.toIso8601String().split('T').first,
            'start_time': startTime,
            'end_time': endTime,
            'transport_mode': transportMode,
            'created_by': _uid,
            'total_budget': totalBudget,
          })
          .select()
          .single(),
    );
    final tripId = row['id'] as String;

    if (accommodations.isNotEmpty) {
      await retryOnJwtClockSkew(
        () => _client.from('trip_accommodations').insert([
          for (var i = 0; i < accommodations.length; i++)
            {
              'trip_id': tripId,
              'night_number': i + 1,
              'name': accommodations[i].name,
              'address': accommodations[i].address,
              'latitude': accommodations[i].latitude,
              'longitude': accommodations[i].longitude,
            },
        ]),
      );
    }

    tripsChanged.value++;
    return tripId;
  }

  Future<void> saveTripSchedule({
    required String tripId,
    required List<TripDayInput> days,
    required List<TripStopInput> stops,
    required List<TripTravelSegmentInput> segments,
  }) async {
    if (days.isNotEmpty) {
      await retryOnJwtClockSkew(
        () => _client.from('trip_days').insert([
          for (final day in days)
            {
              'trip_id': tripId,
              'day_number': day.dayNumber,
              'date': day.date.toIso8601String().split('T').first,
              'start_time_override': day.startTimeOverride,
            },
        ]),
      );
    }

    final stopIds = <(int, int), String>{};
    if (stops.isNotEmpty) {
      final rows = await retryOnJwtClockSkew(
        () => _client
            .from('trip_stops')
            .insert([for (final stop in stops) _stopRow(tripId, stop)])
            .select('id, day_number, sequence'),
      );
      for (final row in rows) {
        stopIds[(row['day_number'] as int, row['sequence'] as int)] =
            row['id'] as String;
      }
    }

    if (segments.isNotEmpty) {
      await retryOnJwtClockSkew(
        () => _client.from('trip_travel_segments').insert([
          for (final segment in segments)
            {
              'trip_id': tripId,
              'day_number': segment.dayNumber,
              'sequence': segment.sequence,
              'from_name': segment.fromName,
              'from_latitude': segment.fromLatitude,
              'from_longitude': segment.fromLongitude,
              'to_name': segment.toName,
              'to_latitude': segment.toLatitude,
              'to_longitude': segment.toLongitude,
              'to_stop_id': segment.legKind == TripLegKind.stop
                  ? stopIds[(segment.dayNumber, segment.sequence)]
                  : null,
              'leg_kind': segment.legKind.column,
              'transport_mode': segment.transportMode,
              'duration_minutes': segment.durationMinutes,
            },
        ]),
      );
    }
  }

  Map<String, dynamic> _stopRow(String tripId, TripStopInput stop) {
    final location = stop.location;
    return {
      'trip_id': tripId,
      'name': location.name,
      'address': location.address,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'osm_id': location.osmId,
      'category': location.category,
      'place_id': location.placeId,
      'primary_type': location.primaryType,
      'types': location.types,
      'business_status': location.businessStatus,
      'opening_hours': location.openingHours,
      'opening_hours_periods': location.openingHoursPeriods
          ?.map((p) => p.toJson())
          .toList(),
      'environment': location.environment.name,
      'visit_minutes': stop.visitMinutes,
      'day_number': stop.dayNumber,
      'sequence': stop.sequence,
      'arrival_minutes': stop.arrivalMinutes,
      'end_minutes': stop.endMinutes,
      'weather_flagged': stop.weatherFlagged,
      'weather_bad_periods': stop.weatherBadPeriods,
      'weather_forecast_phrase': stop.weatherForecastPhrase,
      'weather_checked_at': stop.weatherCheckedAt?.toIso8601String(),
    };
  }

  Future<TripSchedule> getTripSchedule(String tripId) async {
    final tripRow = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .select('transport_mode, start_time, end_time')
          .eq('id', tripId)
          .single(),
    );

    final dayRows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_days')
          .select()
          .eq('trip_id', tripId)
          .order('day_number', ascending: true),
    );
    final stopRows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_stops')
          .select()
          .eq('trip_id', tripId)
          .order('day_number', ascending: true)
          .order('sequence', ascending: true),
    );
    final segmentRows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_travel_segments')
          .select()
          .eq('trip_id', tripId)
          .order('day_number', ascending: true)
          .order('sequence', ascending: true),
    );

    final days = <TripScheduleDay>[];
    for (final dayRow in dayRows) {
      final dayNumber = dayRow['day_number'] as int;
      days.add(
        TripScheduleDay(
          dayNumber: dayNumber,
          date: DateTime.parse(dayRow['date'] as String),
          startTimeOverride: dayRow['start_time_override'] as String?,
          stops: [
            for (final row in stopRows)
              if (row['day_number'] == dayNumber) TripScheduleStop.fromMap(row),
          ],
          legs: [
            for (final row in segmentRows)
              if (row['day_number'] == dayNumber) TripScheduleLeg.fromMap(row),
          ],
        ),
      );
    }

    return TripSchedule(
      transportMode: (tripRow['transport_mode'] as String?) ?? 'driving',
      tripStartTime: tripRow['start_time'] as String?,
      tripEndTime: tripRow['end_time'] as String?,
      days: days,
    );
  }

  Future<void> updateDaySchedule({
    required String tripId,
    required int dayNumber,
    required String? startTimeOverride,
    required List<TripStopInput> stops,
    required List<TripTravelSegmentInput> segments,
  }) async {
    await retryOnJwtClockSkew(
      () => _client
          .from('trip_days')
          .update({'start_time_override': startTimeOverride})
          .eq('trip_id', tripId)
          .eq('day_number', dayNumber),
    );
    await retryOnJwtClockSkew(
      () => _client
          .from('trip_travel_segments')
          .delete()
          .eq('trip_id', tripId)
          .eq('day_number', dayNumber),
    );
    await retryOnJwtClockSkew(
      () => _client
          .from('trip_stops')
          .delete()
          .eq('trip_id', tripId)
          .eq('day_number', dayNumber),
    );

    final stopIds = <int, String>{};
    if (stops.isNotEmpty) {
      final rows = await retryOnJwtClockSkew(
        () => _client
            .from('trip_stops')
            .insert([for (final stop in stops) _stopRow(tripId, stop)])
            .select('id, sequence'),
      );
      for (final row in rows) {
        stopIds[row['sequence'] as int] = row['id'] as String;
      }
    }

    if (segments.isNotEmpty) {
      await retryOnJwtClockSkew(
        () => _client.from('trip_travel_segments').insert([
          for (final segment in segments)
            {
              'trip_id': tripId,
              'day_number': segment.dayNumber,
              'sequence': segment.sequence,
              'from_name': segment.fromName,
              'from_latitude': segment.fromLatitude,
              'from_longitude': segment.fromLongitude,
              'to_name': segment.toName,
              'to_latitude': segment.toLatitude,
              'to_longitude': segment.toLongitude,
              'to_stop_id': segment.legKind == TripLegKind.stop
                  ? stopIds[segment.sequence]
                  : null,
              'leg_kind': segment.legKind.column,
              'transport_mode': segment.transportMode,
              'duration_minutes': segment.durationMinutes,
            },
        ]),
      );
    }
  }

  Future<void> updateTrip({
    required String tripId,
    required String name,
    String? description,
    String? destination,
    String? startLocationName,
    String? startAddress,
    double? startLatitude,
    double? startLongitude,
    String? endLocationName,
    String? endAddress,
    double? endLatitude,
    double? endLongitude,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Trip name cannot be empty.');
    }
    await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .update({
            'name': trimmedName,
            'description': description,
            'destination': destination ?? '',
            'start_location_name': startLocationName,
            'start_address': startAddress,
            'start_latitude': startLatitude,
            'start_longitude': startLongitude,
            'end_location_name': endLocationName,
            'end_address': endAddress,
            'end_latitude': endLatitude,
            'end_longitude': endLongitude,
            'start_date': startDate?.toIso8601String().split('T').first,
            'end_date': endDate?.toIso8601String().split('T').first,
          })
          .eq('id', tripId),
    );
    tripsChanged.value++;
  }

  Future<void> deleteTrip(String tripId) async {
    await retryOnJwtClockSkew(
      () => _client.from('trips').delete().eq('id', tripId),
    );
    tripsChanged.value++;
  }

  Future<List<Trip>> myTrips() async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .select('*, trip_members!inner(user_id)')
          .eq('trip_members.user_id', _uid)
          .order('created_at', ascending: false),
    );
    return _parseTrips(rows);
  }

  Stream<List<Trip>> watchMyTrips() {
    return _client
        .from('trip_members')
        .stream(primaryKey: ['trip_id', 'user_id'])
        .eq('user_id', _uid)
        .asyncMap((memberRows) async {
          final tripIds = memberRows
              .map((row) => row['trip_id'] as String)
              .toSet()
              .toList();
          if (tripIds.isEmpty) return const <Trip>[];
          final rows = await retryOnJwtClockSkew(
            () => _client
                .from('trips')
                .select()
                .inFilter('id', tripIds)
                .order('created_at', ascending: false),
          );
          return _parseTrips(rows);
        });
  }

  Future<Trip?> findDateConflict({
    required DateTime start,
    required DateTime end,
    String? excludeTripId,
  }) async {
    final startStr = start.toIso8601String().split('T').first;
    final endStr = end.toIso8601String().split('T').first;
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .select('*, trip_members!inner(user_id)')
          .eq('trip_members.user_id', _uid)
          .lte('start_date', endStr)
          .gte('end_date', startStr),
    );
    final trips = _parseTrips(
      rows,
    ).where((t) => t.id != excludeTripId).toList();
    return trips.isEmpty ? null : trips.first;
  }

  List<Trip> _parseTrips(List<Map<String, dynamic>> rows) {
    final trips = <Trip>[];
    for (final row in rows) {
      try {
        trips.add(Trip.fromMap(row));
      } catch (e) {
        debugPrint('Skipping malformed trip row ${row['id']}: $e\n$row');
      }
    }
    return trips;
  }

  Future<List<Trip>> organizerCurrentAndUpcomingTrips() async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .select('*, trip_members!inner(user_id, role)')
          .eq('trip_members.user_id', _uid)
          .eq('trip_members.role', 'organizer')
          .order('created_at', ascending: false),
    );
    final trips = _parseTrips(
      rows,
    ).where((trip) => trip.status != TripStatus.past).toList();
    trips.sort((a, b) {
      final aCurrent = a.status == TripStatus.current;
      final bCurrent = b.status == TripStatus.current;
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
      final aDate = a.startDate;
      final bDate = b.startDate;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return trips;
  }

  Future<int> memberCount(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () =>
          _client.from('trip_members').select('user_id').eq('trip_id', tripId),
    );
    return rows.length;
  }

  Future<List<TripStopLocation>> getTripStops(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_stops')
          .select()
          .eq('trip_id', tripId)
          .order('created_at'),
    );
    return [for (final row in rows) TripStopLocation.fromMap(row)];
  }

  Future<List<TripStopLocation>> getFavoriteStops(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_favorite_stops')
          .select()
          .eq('trip_id', tripId)
          .order('created_at', ascending: true),
    );
    return [for (final row in rows) TripStopLocation.fromMap(row)];
  }

  Future<TripStopLocation> addFavoriteStop(
    String tripId,
    TripStopLocation stop,
  ) async {
    final row = await retryOnJwtClockSkew(
      () => _client
          .from('trip_favorite_stops')
          .insert({
            'trip_id': tripId,
            'name': stop.name,
            'address': stop.address,
            'latitude': stop.latitude,
            'longitude': stop.longitude,
            'osm_id': stop.osmId,
            'category': stop.category,
            'created_by': _uid,
          })
          .select()
          .single(),
    );
    return TripStopLocation.fromMap(row);
  }

  Future<void> removeFavoriteStop(String favoriteStopId) async {
    await retryOnJwtClockSkew(
      () =>
          _client.from('trip_favorite_stops').delete().eq('id', favoriteStopId),
    );
  }

  Future<List<Trip>> getMyTrips() async {
    final memberRows = await _client
        .from('trip_members')
        .select('trip_id')
        .eq('user_id', _uid);
    final tripIds = memberRows
        .map((row) => row['trip_id'] as String)
        .toSet()
        .toList();
    if (tripIds.isEmpty) return const <Trip>[];
    final rows = await retryOnJwtClockSkew(
      () => _client.from('trips').select().inFilter('id', tripIds),
    );
    return rows.map(Trip.fromMap).toList();
  }

  Future<String> getTripName(String tripId) async {
    final row = await retryOnJwtClockSkew(
      () => _client.from('trips').select('name').eq('id', tripId).single(),
    );
    return row['name'] as String;
  }

  Future<Trip> getTrip(String tripId) async {
    final row = await retryOnJwtClockSkew(
      () => _client.from('trips').select().eq('id', tripId).single(),
    );
    return Trip.fromMap(row);
  }

  Stream<List<TripStopLocation>> watchTripStops(String tripId) {
    return _client
        .from('trip_stops')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at')
        .map(
          (rows) => rows
              .map(
                (r) => TripStopLocation(
                  name: r['name'] as String,
                  address: (r['address'] as String?) ?? '',
                  latitude: (r['latitude'] as num).toDouble(),
                  longitude: (r['longitude'] as num).toDouble(),
                  osmId: r['osm_id'] as String?,
                  category: (r['category'] as String?) ?? 'Other',
                ),
              )
              .toList(),
        );
  }

  Future<int> visitCount(String placeName) async {
    final memberRows = await _client
        .from('trip_members')
        .select('trip_id')
        .eq('user_id', _uid);
    final tripIds = memberRows
        .map((r) => r['trip_id'] as String)
        .toSet()
        .toList();
    if (tripIds.isEmpty) return 0;

    final tripRows = await _client
        .from('trips')
        .select()
        .inFilter('id', tripIds);
    final pastTripIds = tripRows
        .map(Trip.fromMap)
        .where((t) => t.status == TripStatus.past)
        .map((t) => t.id)
        .toList();
    if (pastTripIds.isEmpty) return 0;

    final stopRows = await _client
        .from('trip_stops')
        .select('trip_id, name')
        .inFilter('trip_id', pastTripIds);
    final target = placeName.trim().toLowerCase();
    final visitedTripIds = <String>{};
    for (final r in stopRows) {
      final name = (r['name'] as String).trim().toLowerCase();
      if (name == target || name.contains(target) || target.contains(name)) {
        visitedTripIds.add(r['trip_id'] as String);
      }
    }
    return visitedTripIds.length;
  }

  static void resetCache() {
    _cachedTripId = null;
    _inFlight = null;
  }
}
