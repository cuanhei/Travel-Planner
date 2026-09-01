import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/trip.dart';
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
    final membership = await _client
        .from('trip_members')
        .select('trip_id')
        .eq('user_id', _uid)
        .order('joined_at')
        .limit(1)
        .maybeSingle();
    if (membership != null) {
      final tripId = membership['trip_id'] as String;
      _cachedTripId = tripId;
      return tripId;
    }

    final today = DateTime.now();
    final trip = await _client
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
        .single();
    final tripId = trip['id'] as String;

    await _client.from('budget_categories').insert([
      for (final entry in _defaultCategoryPlan.entries)
        {'trip_id': tripId, 'label': entry.key, 'planned_amount': entry.value},
    ]);

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
    final session = _client.auth.currentSession;
    debugPrint(
      'createTrip: uid=$_uid session=${session != null} '
      'expired=${session?.isExpired}',
    );
    final row = await _client
        .from('trips')
        .insert({
          'name': name,
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
        .single();
    return row['id'] as String;
  }

  /// All trips the signed-in user is a member of (as organizer or plain
  /// member), newest first — backs the "My Trips" tab. Explicitly joined
  /// through `trip_members` rather than relying only on the
  /// `trips_select_members` RLS policy, so the "who can see this" rule
  /// is visible here too: every creator is added as `organizer` by the
  /// `on_trip_created` trigger, so this covers both cases with one join.
  Future<List<Trip>> myTrips() async {
    final rows = await _client
        .from('trips')
        .select('*, trip_members!inner(user_id)')
        .eq('trip_members.user_id', _uid)
        .order('created_at', ascending: false);
    return [for (final row in rows) Trip.fromMap(row)];
  }

  /// Fetches a trip's current name, for screens that only hold its id
  /// (Budget/Group screens no longer hardcode "Penang Adventure").
  Future<String> getTripName(String tripId) async {
    final row = await _client
        .from('trips')
        .select('name')
        .eq('id', tripId)
        .single();
    return row['name'] as String;
  }

  /// Fetches a full trip row, for entry points (Home dashboard, Saved
  /// Trips, Travel History) that still only resolve "the current trip"
  /// via [ensureDemoTrip] rather than holding a real [Trip] already.
  Future<Trip> getTrip(String tripId) async {
    final row = await _client.from('trips').select().eq('id', tripId).single();
    return Trip.fromMap(row);
  }

  /// Call on sign-out so a different account doesn't inherit the
  /// previous user's cached trip id.
  static void resetCache() {
    _cachedTripId = null;
    _inFlight = null;
  }
}
