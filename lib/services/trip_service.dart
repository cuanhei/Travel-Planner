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
