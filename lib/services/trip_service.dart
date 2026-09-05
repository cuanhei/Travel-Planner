import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trip.dart';
import '../models/trip_schedule.dart';
import '../models/trip_schedule_input.dart';
import '../models/trip_stop_location.dart';
import 'supabase_config.dart';

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

  /// Bumped whenever a trip is created — [TripsTab] (and anywhere else
  /// that lists trips) listens to this instead of only reloading right
  /// after its own "Create Trip" push, so a trip created from a
  /// different entry point (Home dashboard, Add to Trip, ...) still
  /// shows up without the traveler needing to manually pull-to-refresh.
  /// Static because the trips list lives in a bottom-nav tab kept alive
  /// in an `IndexedStack` — it isn't re-pushed/popped when a trip is
  /// created elsewhere, so there's no navigation event for it to react
  /// to otherwise.
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
    // Deterministic when a user ends up in more than one trip (e.g. they
    // opened Budget/Group once before joining someone else's trip via
    // code) — always resolves to whichever trip they've belonged to
    // longest, so repeated calls never flip between trips.
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

  /// Inserts a new row into `trips` from the Create Trip form — trip
  /// details + travel information only. Doesn't touch `trip_stops` or
  /// `trip_schedule_stops`; those come later once day-by-day scheduling
  /// is wired up. Returns the new trip's id.
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

    /// "driving" or "transit" — the transport mode toggle above Create
    /// Trip's day tabs, applied to every travel leg in the trip.
    String transportMode = 'driving',

    /// One accommodation per night of the trip — index 0 is the first
    /// night (after day 1), index 1 the second, and so on. A trip
    /// spanning N days has N-1 nights, so this is empty for a single-day
    /// trip. Every entry must be non-null; validated by the caller (the
    /// Create Trip form) before this is called.
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

  /// Persists Create Trip's full day-by-day timeline — one row per day
  /// tab (`trip_days`), one row per scheduled stop with its computed
  /// arrival/end time and weather flag (`trip_stops`), and one row per
  /// travel leg actually shown (`trip_travel_segments`). Called once,
  /// right after [createTrip] returns [tripId] — there's no partial-save/
  /// resume flow yet, so this always writes a trip's entire schedule in
  /// one call.
  ///
  /// Insert order matters: stops must exist before segments, since a
  /// `legKind: TripLegKind.stop` segment's `to_stop_id` is resolved from
  /// the just-inserted stops' ids (matched by `day_number` + `sequence` —
  /// a stop leg's own `sequence` is always the same as the stop it
  /// arrives at, so no separate correlation key is needed).
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

    // day_number/sequence -> the inserted trip_stops row's id, so a
    // 'stop' leg below can resolve its to_stop_id.
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

  /// Loads back everything [saveTripSchedule] wrote — every day tab,
  /// every scheduled stop (already-computed arrival/end time and weather
  /// flag included, not recomputed here), and every travel leg — for
  /// [DailyTimelineScreen]'s read-only view. A trip with no saved
  /// schedule yet (created before this existed, or [saveTripSchedule]
  /// was never called) comes back with an empty `days` list rather than
  /// throwing.
  Future<TripSchedule> getTripSchedule(String tripId) async {
    final tripRow = await retryOnJwtClockSkew(
      () => _client
          .from('trips')
          .select('transport_mode, start_time, end_time')
          .eq('id', tripId)
          .single(),
    );
    // `.order()` in this client defaults to descending (the opposite of
    // SQL's own default) — `ascending: true` is required here, otherwise
    // days/stops/legs all come back reversed (day N first, its stops in
    // reverse-add order), which also silently corrupts which leg gets
    // read as "the trailing leg to accommodation" (always `legs.last`).
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

  /// Organizer-only: replaces a single day's stops and travel legs (Edit
  /// Schedule only ever touches one day at a time — past days are locked
  /// client-side and never reach this) and, if given, its start-time
  /// override. Deletes that day's existing `trip_stops`/
  /// `trip_travel_segments` rows first since — unlike [saveTripSchedule]'s
  /// first-ever insert — this call replaces an already-saved day.
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

  /// Updates a trip's core details from the Edit Trip form — everything
  /// [createTrip] accepts except accommodations/times, which Edit Trip
  /// doesn't touch. Only the organizer can call this successfully; the
  /// `trips_update_organizer` RLS policy enforces that server-side too.
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

  /// Deletes a trip and (via `on delete cascade`) everything hanging off
  /// it — members, stops, accommodations, schedule, budget, chat, etc.
  /// Only the organizer can call this successfully; the
  /// `trips_delete_organizer` RLS policy enforces that server-side too.
  Future<void> deleteTrip(String tripId) async {
    await retryOnJwtClockSkew(
      () => _client.from('trips').delete().eq('id', tripId),
    );
    tripsChanged.value++;
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
    return _parseTrips(rows);
  }

  /// The first trip the signed-in user already belongs to — as organizer
  /// *or* plain member, same `trip_members` join as [myTrips] — whose
  /// dates clash with `[start, end]` (inclusive: a trip ending the day
  /// another starts still counts, matching `check_trip_date_conflict`'s
  /// server-side trigger). Null if none does. [excludeTripId] skips a
  /// trip against itself, for checking a date change on an already-
  /// existing trip rather than a brand-new one.
  ///
  /// This is Create Trip's client-side check — a friendlier, inline
  /// warning before ever hitting Save — but the database trigger is what
  /// actually enforces it; this call can't be the only guard against a
  /// race (two trips created back-to-back) or a bypassed client.
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

  /// Parses each row via [Trip.fromMap], skipping (and logging) any row
  /// that fails — one malformed/legacy row (e.g. missing a required
  /// column from before a migration backfilled it) shouldn't take down
  /// the whole My Trips list.
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

  /// How many travelers (organizer + members) belong to a trip — backs
  /// Trip Details' "Travelers" stat.
  Future<int> memberCount(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () =>
          _client.from('trip_members').select('user_id').eq('trip_id', tripId),
    );
    return rows.length;
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

  /// One-shot snapshot of every trip the signed-in user belongs to — the
  /// same membership as [watchMyTrips], but a single fetch rather than a
  /// live stream, for a one-off check (Join Trip's date-overlap
  /// validation) rather than something rendered on screen.
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

  /// Live list of a trip's stops (with their stored coordinates) — used by
  /// Emergency Contacts (Utilities) to show numbers for the trip's current
  /// stop, every stop already saved to this trip, nothing fetched from an
  /// external place-search API.
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

  /// How many times the signed-in user has actually visited [placeName] —
  /// the number of distinct trips they belong to, whose dates have already
  /// finished (see [Trip.status]), that include it as a stop. Each visit
  /// is worth one review: Community's "Add Review" (see `AddReviewScreen`)
  /// is gated on this being greater than [CommunityService.myReviewCount],
  /// so visiting a place again unlocks another review of it.
  ///
  /// Matches loosely (case-insensitive, either name containing the other)
  /// since a trip stop's name comes from geocoded place search (e.g. "Penang
  /// Hill, Air Itam, Penang") while Explore's destinations use a shorter
  /// catalog name ("Penang Hill") — an exact match would almost never hit.
  /// Multiple matching stops within the *same* trip only count as one
  /// visit — it's still a single occasion.
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

  /// Call on sign-out so a different account doesn't inherit the
  /// previous user's cached trip id.
  static void resetCache() {
    _cachedTripId = null;
    _inFlight = null;
  }
}
