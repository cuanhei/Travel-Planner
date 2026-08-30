import 'package:flutter/material.dart' show TimeOfDay, DateTimeRange;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/malaysia_city.dart';
import '../models/trip.dart';
import '../models/trip_stop_location.dart';
import 'schedule_builder.dart';
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
        {
          'trip_id': tripId,
          'label': entry.key,
          'planned_amount': entry.value,
        },
    ]);

    _cachedTripId = tripId;
    return tripId;
  }

  /// Saves a trip created via the Create Trip form — the trip row itself,
  /// every stop picked via the real map/search, every selected
  /// "auto-recommend" interest category, and — when [daySchedules] is
  /// given — the day-by-day timed schedule computed from the optimized
  /// route (see `buildDaySchedule`). Returns the new trip's id.
  ///
  /// [stops] should be every real stop regardless of whether a schedule
  /// was computed for them (e.g. it wasn't, because there was no start
  /// city to anchor a route to) — they're still saved as plain,
  /// unscheduled [trip_stops] rows in that case. When [daySchedules] is
  /// non-empty, [stops] is only used as the fallback if it *isn't* empty
  /// but [daySchedules] is (an inconsistent-looking call, but harmless).
  Future<String> createTrip({
    required String name,
    String? description,
    MalaysiaCity? startCity,
    MalaysiaCity? endCity,
    DateTimeRange? dateRange,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    required double totalBudget,
    required bool autoRecommend,
    required Set<String> interests,
    required List<TripStopLocation> stops,
    List<DaySchedule> daySchedules = const [],
  }) async {
    String? isoDate(DateTime? d) => d?.toIso8601String().split('T').first;
    String? isoTime(TimeOfDay? t) => t == null
        ? null
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    final trip = await _client
        .from('trips')
        .insert({
          'name': name,
          'description': description?.isEmpty ?? true ? null : description,
          'destination': endCity?.label ?? startCity?.label ?? '',
          'start_city': startCity?.city,
          'start_state': startCity?.state,
          'end_city': endCity?.city,
          'end_state': endCity?.state,
          'start_date': isoDate(dateRange?.start),
          'end_date': isoDate(dateRange?.end),
          'start_time': isoTime(dateRange == null ? null : startTime),
          'end_time': isoTime(dateRange == null ? null : endTime),
          'created_by': _uid,
          'total_budget': totalBudget,
          'auto_recommend': autoRecommend,
        })
        .select()
        .single();
    final tripId = trip['id'] as String;

    // Every unique physical stop referenced anywhere in the schedule (a
    // hotel reused across days is the same [TripStopLocation] instance —
    // see its value-based `==` — so it only gets one `trip_stops` row).
    final uniqueStops = <TripStopLocation>[];
    if (daySchedules.isNotEmpty) {
      final seen = <TripStopLocation>{};
      for (final day in daySchedules) {
        final hotel = day.hotel;
        if (hotel != null && seen.add(hotel)) uniqueStops.add(hotel);
        for (final scheduled in day.stops) {
          if (seen.add(scheduled.stop)) uniqueStops.add(scheduled.stop);
        }
      }
    } else {
      uniqueStops.addAll(stops);
    }

    final stopIds = <TripStopLocation, String>{};
    if (uniqueStops.isNotEmpty) {
      final inserted = await _client
          .from('trip_stops')
          .insert([
            for (final stop in uniqueStops)
              {
                'trip_id': tripId,
                'name': stop.name,
                'address': stop.address,
                'latitude': stop.latitude,
                'longitude': stop.longitude,
                'osm_id': stop.osmId,
                'category': stop.category,
              },
          ])
          .select();
      for (var i = 0; i < uniqueStops.length; i++) {
        stopIds[uniqueStops[i]] = inserted[i]['id'] as String;
      }
    }

    if (daySchedules.isNotEmpty) {
      final scheduleRows = <Map<String, dynamic>>[];
      for (final day in daySchedules) {
        final hotel = day.hotel;
        if (hotel != null) {
          scheduleRows.add({
            'trip_id': tripId,
            'stop_id': stopIds[hotel],
            'day_number': day.day,
            'sequence': 0,
            'is_hotel': true,
            'scheduled_departure': isoTime(day.startTime),
          });
        }
        for (var i = 0; i < day.stops.length; i++) {
          final scheduled = day.stops[i];
          scheduleRows.add({
            'trip_id': tripId,
            'stop_id': stopIds[scheduled.stop],
            'day_number': day.day,
            'sequence': i + 1,
            'is_hotel': false,
            'scheduled_arrival': isoTime(scheduled.arrival),
            'scheduled_departure': isoTime(scheduled.departure),
            'travel_mode': scheduled.travelFromPrevious?.mode,
            'travel_minutes': scheduled.travelFromPrevious?.durationMinutes,
          });
        }
      }
      if (scheduleRows.isNotEmpty) {
        await _client.from('trip_schedule_stops').insert(scheduleRows);
      }
    }

    if (interests.isNotEmpty) {
      await _client.from('trip_interests').insert([
        for (final category in interests)
          {'trip_id': tripId, 'category': category},
      ]);
    }

    return tripId;
  }

  /// Live list of every trip the signed-in user belongs to (as creator or
  /// invited member), for the "My Trips" tab.
  ///
  /// Filters explicitly via `trip_members` rather than trusting RLS alone
  /// to narrow a plain `trips` stream: `.stream()`'s realtime half
  /// broadcasts `postgres_changes` events, and relying on RLS to filter
  /// those (instead of passing an explicit `.eq()`, which Realtime
  /// enforces server-side regardless of policy state) risks a trip
  /// leaking into every signed-in user's list if RLS on `trips` is ever
  /// missing or misconfigured. Membership already covers "created by",
  /// too — the `on_trip_created` trigger adds the creator as organizer.
  Stream<List<Trip>> watchMyTrips() {
    return _client
        .from('trip_members')
        .stream(primaryKey: ['trip_id', 'user_id'])
        .eq('user_id', _uid)
        .asyncMap((memberRows) async {
          final tripIds = memberRows.map((row) => row['trip_id'] as String).toSet().toList();
          if (tripIds.isEmpty) return const <Trip>[];
          final rows = await _client
              .from('trips')
              .select()
              .inFilter('id', tripIds)
              .order('created_at', ascending: false);
          return rows.map(Trip.fromMap).toList();
        });
  }

  /// Call on sign-out so a different account doesn't inherit the
  /// previous user's cached trip id.
  static void resetCache() {
    _cachedTripId = null;
    _inFlight = null;
  }
}
