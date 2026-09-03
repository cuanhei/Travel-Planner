import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trip.dart';
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
          {'trip_id': tripId, 'label': entry.key, 'planned_amount': entry.value},
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
          })
          .select()
          .single(),
    );
    return row['id'] as String;
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
      () => _client
          .from('trip_favorite_stops')
          .delete()
          .eq('id', favoriteStopId),
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

  /// Call on sign-out so a different account doesn't inherit the
  /// previous user's cached trip id.
  static void resetCache() {
    _cachedTripId = null;
    _inFlight = null;
  }
}
