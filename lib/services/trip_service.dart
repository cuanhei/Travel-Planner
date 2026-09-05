import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trip.dart';
import '../models/trip_accommodation.dart';
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
          {'trip_id': tripId, 'label': entry.key, 'planned_amount': entry.value},
      ]),
    );

    _cachedTripId = tripId;
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

    return tripId;
  }

  /// Every night's accommodation for a trip, ordered by [night_number] —
  /// backs Trip Details' itinerary view.
  Future<List<TripAccommodation>> tripAccommodations(String tripId) async {
    final rows = await retryOnJwtClockSkew(
      () => _client
          .from('trip_accommodations')
          .select()
          .eq('trip_id', tripId)
          .order('night_number'),
    );
    return [for (final row in rows) TripAccommodation.fromMap(row)];
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
