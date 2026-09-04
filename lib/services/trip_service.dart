import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trip.dart';
import '../models/trip_stop_location.dart';
import 'supabase_config.dart';

/// One `trip_schedule_stops` row joined back to its real stop — see
/// [TripService.getSchedule]/[TripService.saveSchedule]. Shared here
/// (rather than declared per-screen) since every screen that reads or
/// writes the persisted schedule (Trip Details, Daily Timeline, Edit
/// Schedule) needs the exact same shape.
typedef TripScheduleRow = ({
  int dayNumber,
  int sequence,
  TripStopLocation stop,
  bool isHotel,
  String? scheduledArrival,
  String? scheduledDeparture,
  String? scheduledVisitStart,
  String? travelMode,
  int? travelMinutes,
});

typedef ScheduleWriteRow = ({
  int dayNumber,
  int sequence,
  String stopId,
  bool isHotel,
  DateTime? scheduledArrival,
  DateTime? scheduledVisitStart,
  DateTime? scheduledDeparture,
  String? travelMode,
  int? travelMinutes,
});

List<Map<String, dynamic>> scheduleRowsToJson(List<ScheduleWriteRow> rows) => [
  for (final row in rows)
    {
      'stop_id': row.stopId,
      'day_number': row.dayNumber,
      'sequence': row.sequence,
      'is_hotel': row.isHotel,
      'scheduled_arrival': _timeOfDayString(row.scheduledArrival),
      'scheduled_visit_start': _timeOfDayString(row.scheduledVisitStart),
      'scheduled_departure': _timeOfDayString(row.scheduledDeparture),
      'travel_mode': row.travelMode,
      'travel_minutes': row.travelMinutes,
    },
];

/// Default category plan seeded onto a freshly created demo trip —
/// mirrors the numbers the UI used to hardcode as mock data.
const _defaultCategoryPlan = {
  'Accommodation': 600.0,
  'Food & Drinks': 350.0,
  'Transport': 150.0,
  'Shopping': 300.0,
  'Activities': 100.0,
};

/// Resolves "the current trip" for Budget/Group screens. No other
/// module has real trip creation/selection wired up yet, so this
/// stands in for that: each signed-in user gets one auto-created
/// "Penang Adventure" trip (mirroring the old mock data), reused on
/// every subsequent call. Swap this out once real trip selection
/// exists elsewhere in the app.
class TripService {
  TripService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  static String? _cachedTripId;
  static Future<String>? _inFlight;

  String get _uid => _client.auth.currentUser!.id;

  Future<String> ensureDemoTrip() {
    final cached = _cachedTripId;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _resolve().whenComplete(() => _inFlight = null);
  }

  Future<String> _resolve() async {
    // Deterministic when a user ends up in more than one trip (e.g. they
    // opened Budget/Group once before joining someone else's trip via
    // code) — always resolves to whichever trip they've belonged to
    // longest, so repeated calls never flip between trips.
    final membership = await retryOnJwtClockSkew(
      () => _client
          .from('trip_members')
          .select('trip_id')
          .eq('user_id', _uid)
          .order('joined_at')
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
    return tripId;
  }

  /// Inserts a new row into `trips` from the Create Trip form — trip
  /// details + travel information only. Doesn't touch `trip_stops`,
  /// `trip_interests`, or `trip_schedule_stops`; those come later once
  /// day-by-day scheduling is wired up. Returns the new trip's id.
  Future<String> createTrip({
    required String name,
    String? description,
    String? destination,
    String? startCity,
    String? startState,
    String? endCity,
    String? endState,
    DateTime? startDate,
    DateTime? endDate,
    String? startTime,
    String? endTime,
    required double totalBudget,
    required bool autoRecommend,
    String? transportMode,
    String accommodationMode = 'none',
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
            'start_city': startCity,
            'start_state': startState,
            'end_city': endCity,
            'end_state': endState,
            'start_date': startDate?.toIso8601String().split('T').first,
            'end_date': endDate?.toIso8601String().split('T').first,
            'start_time': startTime,
            'end_time': endTime,
            'created_by': _uid,
            'total_budget': totalBudget,
            'auto_recommend': autoRecommend,
            'transport_mode': transportMode,
            'accommodation_mode': accommodationMode,
          })
          .select()
          .single(),
    );
    return row['id'] as String;
  }

  /// Permanently removes [tripId] and everything under it — every child
  /// table (`trip_stops`, `trip_schedule_stops`, `trip_accommodations`,
  /// `trip_interests`, `trip_members`, etc.) references `trips (id) on
  /// delete cascade` (see schema.sql), so this one delete is enough.
  /// Used to roll back a trip [AiPlannerScreen] created but couldn't
  /// finish planning for (spec: nothing about a trip should persist
  /// until the AI Planner actually succeeds) — never called for a real,
  /// already-planned trip the traveler is done with.
  Future<void> deleteTrip(String tripId) async {
    await retryOnJwtClockSkew(
      () => _client.from('trips').delete().eq('id', tripId),
    );
  }

  /// Saves Create Trip's picked locations to `trip_stops` —
  /// [TripStopLocation.toInsertMap] carries every scheduling-relevant
  /// field (visitPurpose, category, opening periods, estimated visit
  /// duration, etc.), not just name/coordinates. Returns the saved rows,
  /// each now carrying a real `trip_stops.id` (needed to later reference
  /// a stop from `trip_accommodations`/`trip_schedule_stops`).
  Future<List<TripStopLocation>> addStops(
    String tripId,
    Iterable<TripStopLocation> stops,
  ) async {
    if (stops.isEmpty) return const [];
    final rows = await retryOnJwtClockSkew(
      () => _client.from('trip_stops').insert([
        for (final stop in stops) stop.toInsertMap(tripId),
      ]).select(),
    );
    return [for (final row in rows) TripStopLocation.fromMap(row)];
  }

  /// Permanently removes one stop from [tripId] — cascades to its
  /// `trip_schedule_stops`/`trip_accommodations` rows automatically (see
  /// schema.sql's `on delete cascade`), so Edit Schedule's "Remove from
  /// trip" doesn't need a separate schedule cleanup call; a
  /// `trips.start_location_stop_id`/`end_location_stop_id` pointing at
  /// this stop is set null rather than blocking the delete. Meant for a
  /// traveler's own visit stop — to *change* accommodation or the trip's
  /// start/end location, use the dedicated flows for those instead of
  /// deleting and re-adding.
  Future<void> deleteStop(String tripId, String stopId) async {
    await retryOnJwtClockSkew(
      () => _client
          .from('trip_stops')
          .delete()
          .eq('trip_id', tripId)
          .eq('id', stopId),
    );
  }

  /// Replaces `trip_interests` for [tripId] — Create Trip's "Interests"
  /// category chips, used by the auto-recommend flow.
  Future<void> setInterests(String tripId, Iterable<String> categories) async {
    await retryOnJwtClockSkew(
      () => _client.from('trip_interests').delete().eq('trip_id', tripId),
    );
    if (categories.isEmpty) return;
    await retryOnJwtClockSkew(
      () => _client.from('trip_interests').insert([
        for (final category in categories)
          {'trip_id': tripId, 'category': category},
      ]),
    );
  }

  Future<List<String>> getInterests(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_interests')
          .select('category')
          .eq('trip_id', tripId),
    );
    return [for (final row in rows) row['category'] as String];
  }

  /// Every night's accommodation anchor for [tripId], oldest night
  /// first — the [TripStopLocation] is joined in from `trip_stops` via
  /// `trip_accommodations.stop_id`. See [setAccommodations].
  Future<List<({DateTime nightDate, TripStopLocation stop})>> getAccommodations(
    String tripId,
  ) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_accommodations')
          .select('night_date, trip_stops(*)')
          .eq('trip_id', tripId)
          .order('night_date'),
    );
    return [
      for (final row in rows)
        (
          nightDate: DateTime.parse(row['night_date'] as String),
          stop: TripStopLocation.fromMap(
            row['trip_stops'] as Map<String, dynamic>,
          ),
        ),
    ];
  }

  /// Replaces every night's accommodation anchor for [tripId] with
  /// [nightsToStopId] (night date → `trip_stops.id`, which must already
  /// exist — save the stop via [addStops] first).
  Future<void> setAccommodations(
    String tripId,
    Map<DateTime, String> nightsToStopId,
  ) async {
    await retryOnJwtClockSkew(
      () => _client.from('trip_accommodations').delete().eq('trip_id', tripId),
    );
    if (nightsToStopId.isEmpty) return;
    await retryOnJwtClockSkew(
      () => _client.from('trip_accommodations').insert([
        for (final entry in nightsToStopId.entries)
          {
            'trip_id': tripId,
            'stop_id': entry.value,
            'night_date': entry.key.toIso8601String().split('T').first,
          },
      ]),
    );
  }

  /// Links [tripId]'s real Starting-From/Ending-At locations (spec
  /// §2.1/§16 — the coordinates the scheduling engine anchors Day 1's
  /// start / the last day's end to when no accommodation covers that
  /// side) to already-saved `trip_stops` rows — save the stop(s) via
  /// [addStops] first, same order as [setAccommodations]. Either id may
  /// be null to leave that side unset without touching the other.
  Future<void> setTripLocations(
    String tripId, {
    String? startStopId,
    String? endStopId,
  }) async {
    await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .update({
            'start_location_stop_id': ?startStopId,
            'end_location_stop_id': ?endStopId,
          })
          .eq('id', tripId),
    );
  }

  /// All trips the signed-in user is a member of (as organizer or plain
  /// member), newest first — backs the "My Trips" tab. Explicitly joined
  /// through `trip_members` rather than relying only on the
  /// `trips_select_members` RLS policy, so the "who can see this" rule
  /// is visible here too: every creator is added as `organizer` by the
  /// `on_trip_created` trigger, so this covers both cases with one join.
  Future<List<Trip>> myTrips() async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .select('*, trip_members!inner(user_id)')
          .eq('trip_members.user_id', _uid)
          .order('created_at', ascending: false),
    );
    return [for (final row in rows) Trip.fromMap(row)];
  }

  /// Current + upcoming trips the signed-in user *organizes* (not just
  /// belongs to) — backs "Add to Trip" on a place's details screen, where
  /// only an organizer is allowed to add a place. Past trips are excluded
  /// since there's nothing to add to anymore. Ongoing trip(s) always
  /// sort first, then upcoming trips nearest start date to farthest —
  /// the trip about to need this place soonest is the one worth seeing
  /// first, not just whichever was created most recently.
  Future<List<Trip>> organizerCurrentAndUpcomingTrips() async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .select('*, trip_members!inner(user_id, role)')
          .eq('trip_members.user_id', _uid)
          .eq('trip_members.role', 'organizer')
          .order('created_at', ascending: false),
    );
    final trips = [
      for (final row in rows) Trip.fromMap(row),
    ].where((trip) => trip.status != TripStatus.past).toList();
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

  /// Every stop saved to a trip, for [TripMapScreen] — was hardcoded
  /// dummy data before, so every trip showed the same 4 Penang landmarks
  /// regardless of [tripId].
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

  /// A trip's saved "quick" stops — places like a nearby 7-Eleven or
  /// pharmacy a traveler wants fast directions to, distinct from
  /// [getTripStops]'s itinerary stops. Each trip has its own independent
  /// list, backed by `trip_favorite_stops`.
  Future<List<TripStopLocation>> getFavoriteStops(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_favorite_stops')
          .select()
          .eq('trip_id', tripId)
          .order('created_at'),
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

  /// Fetches a trip's current name, for screens that only hold its id
  /// (Budget/Group screens no longer hardcode "Penang Adventure").
  Future<String> getTripName(String tripId) async {
    final row = await retryOnJwtClockSkew(
      () => _client.from('trips').select('name').eq('id', tripId).single(),
    );
    return row['name'] as String;
  }

  /// Fetches a full trip row, for entry points (Home dashboard, Saved
  /// Trips, Travel History) that still only resolve "the current trip"
  /// via [ensureDemoTrip] rather than holding a real [Trip] already.
  Future<Trip> getTrip(String tripId) async {
    final row = await retryOnJwtClockSkew(
      () => _client.from('trips').select().eq('id', tripId).single(),
    );
    return Trip.fromMap(row);
  }

  /// One database transaction; a stale revision fails without changing rows.
  /// The operation ID must be reused when retrying an uncertain response.
  Future<int> saveSchedule(
    String tripId,
    List<ScheduleWriteRow> rows, {
    required int expectedRevision,
    String? operationId,
    List<TripStopLocation> newStops = const [],
    Set<String> deletedStopIds = const {},
    bool recommendation = false,
    List<Map<String, dynamic>> days = const [],
  }) async {
    final params = {
      'p_trip_id': tripId,
      'p_expected_revision': expectedRevision,
      'p_operation_id': operationId ?? const Uuid().v4(),
      'p_rows': scheduleRowsToJson(rows),
      'p_new_stops': [
        for (final stop in newStops)
          {...stop.toInsertMap(tripId), 'id': stop.id},
      ],
      'p_deleted_stop_ids': deletedStopIds.toList(),
      'p_recommendation': recommendation,
      'p_days': days,
    };
    final revision = await retryOnJwtClockSkew(
      () => _client.rpc('commit_trip_schedule', params: params),
    );
    return revision as int;
  }

  /// Called only after planning has finished successfully in memory.
  Future<String> createPlannedTrip({
    required String tripId,
    required Map<String, dynamic> trip,
    required List<TripStopLocation> stops,
    required List<ScheduleWriteRow> rows,
    required Set<String> interests,
    required List<Map<String, dynamic>> days,
    required Map<DateTime, TripStopLocation> accommodationByNight,
  }) async {
    final result = await retryOnJwtClockSkew(
      () => _client.rpc(
        'create_planned_trip',
        params: {
          'p_trip_id': tripId,
          'p_trip': trip,
          'p_stops': [
            for (final stop in stops)
              {...stop.toInsertMap(tripId), 'id': stop.id},
          ],
          'p_rows': scheduleRowsToJson(rows),
          'p_interests': interests.toList(),
          'p_days': days,
          'p_accommodations': [
            for (final entry in accommodationByNight.entries)
              {
                'night_date': entry.key.toIso8601String().split('T').first,
                'stop_id': entry.value.id,
              },
          ],
        },
      ),
    );
    return result as String;
  }

  /// The persisted schedule for [tripId], oldest day/sequence first,
  /// each row's stop joined in from `trip_stops`. Empty until
  /// `TripSchedulerService.run` has saved one via [saveSchedule].
  Future<List<TripScheduleRow>> getSchedule(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_schedule_stops')
          .select(
            'day_number, sequence, is_hotel, scheduled_arrival, scheduled_visit_start, '
            'scheduled_departure, travel_mode, travel_minutes, trip_stops(*)',
          )
          .eq('trip_id', tripId)
          .order('day_number')
          .order('sequence'),
    );
    return [
      for (final row in rows)
        (
          dayNumber: row['day_number'] as int,
          sequence: row['sequence'] as int,
          stop: TripStopLocation.fromMap(
            row['trip_stops'] as Map<String, dynamic>,
          ),
          isHotel: row['is_hotel'] as bool,
          scheduledArrival: row['scheduled_arrival'] as String?,
          scheduledVisitStart: row['scheduled_visit_start'] as String?,
          scheduledDeparture: row['scheduled_departure'] as String?,
          travelMode: row['travel_mode'] as String?,
          travelMinutes: row['travel_minutes'] as int?,
        ),
    ];
  }

  Future<List<Map<String, dynamic>>> getScheduleDays(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_schedule_days')
          .select(
            '*, start_stop:trip_stops!start_stop_id(*), end_stop:trip_stops!end_stop_id(*)',
          )
          .eq('trip_id', tripId)
          .order('day_number'),
    );
    return rows;
  }

  Future<void> clearSchedule(String tripId) async {
    final trip = await getTrip(tripId);
    await saveSchedule(tripId, [], expectedRevision: trip.scheduleRevision);
  }

  /// Call on sign-out so a different account doesn't inherit the
  /// previous user's cached trip id.
  static void resetCache() {
    _cachedTripId = null;
    _inFlight = null;
  }
}

/// Formats a [DateTime]'s wall-clock time as `"HH:mm:ss"`, matching
/// `trip_schedule_stops.scheduled_arrival`/`scheduled_departure`'s
/// Postgres `time` column type — only the time-of-day matters, the
/// date part of [dt] is discarded.
String? _timeOfDayString(DateTime? dt) {
  if (dt == null) return null;
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
}
