import 'package:flutter/foundation.dart';

import '../models/trip_day.dart';
import '../models/trip_stop_location.dart';
import 'route_service.dart';
import 'travel_time_cache.dart';

/// How much longer a day's start→end anchor trip becomes if [place] is
/// inserted along the way — `(start→place) + (place→end) - (start→end)`.
/// Lower is geographically cheaper; a detour near zero means the place
/// is essentially on the way already, while a large one means it's well
/// off that day's route.
class PlaceDayDetour {
  const PlaceDayDetour({
    required this.place,
    required this.dayNumber,
    required this.detour,
  });

  final TripStopLocation place;
  final int dayNumber;
  final Duration detour;
}

/// Figures out which day of the trip each candidate place geographically
/// belongs on — *before* any exact-time scheduling. Deliberately doesn't
/// just pick each place's nearest hotel: a long transfer day (e.g. KL
/// hotel → Penang hotel) has its own start→end baseline, and a place can
/// fit that day cheaply by sitting near the start, near the end, or
/// along the route between them, even if it isn't nearest to either
/// anchor in isolation. See [computeDetours].
class GeographicAssignmentService {
  GeographicAssignmentService({RouteService? routeService, TravelTimeCache? travelTimeCache})
    : _travelTimeCache = travelTimeCache ?? TravelTimeCache(routeService: routeService);

  final TravelTimeCache _travelTimeCache;

  /// Computes [PlaceDayDetour] for every (day, place) pair — one entry
  /// per combination, not yet assigned to anything. Each day's own
  /// start→end baseline is fetched once and reused for every place
  /// checked against that day.
  Future<List<PlaceDayDetour>> computeDetours({
    required List<TripDay> days,
    required List<TripStopLocation> places,
  }) async {
    final results = <PlaceDayDetour>[];
    for (final day in days) {
      final baseline = await _travelTimeCache.durationBetween(
        day.startAnchor,
        day.endAnchor,
      );
      for (final place in places) {
        final toPlace = await _travelTimeCache.durationBetween(
          day.startAnchor,
          place,
        );
        final fromPlace = await _travelTimeCache.durationBetween(
          place,
          day.endAnchor,
        );
        results.add(
          PlaceDayDetour(
            place: place,
            dayNumber: day.dayNumber,
            detour: toPlace + fromPlace - baseline,
          ),
        );
      }
    }
    return results;
  }

  /// Groups candidate places by whichever day fits them with the lowest
  /// detour (from [computeDetours]) — a nearest-fit geographic
  /// assignment, not a full scheduling pass: no per-day capacity limit
  /// and no exact times, just "which day does this place belong on".
  /// Ties go to the lowest-numbered day.
  Map<int, List<TripStopLocation>> assignPlacesToDays(
    List<PlaceDayDetour> detours,
  ) {
    final byPlace = <TripStopLocation, List<PlaceDayDetour>>{};
    for (final d in detours) {
      byPlace.putIfAbsent(d.place, () => []).add(d);
    }

    final assignment = <int, List<TripStopLocation>>{};
    for (final entry in byPlace.entries) {
      final best = entry.value.reduce(
        (a, b) =>
            b.detour < a.detour || (b.detour == a.detour && b.dayNumber < a.dayNumber)
                ? b
                : a,
      );
      assignment.putIfAbsent(best.dayNumber, () => []).add(entry.key);
      debugPrint(
        '[GeographicAssignment] ${entry.key.name} → Day ${best.dayNumber} '
        '(detour ${best.detour.inMinutes}m)',
      );
    }

    final dayNumbers = assignment.keys.toList()..sort();
    debugPrint('[GeographicAssignment] ===== Day clusters =====');
    for (final dayNumber in dayNumbers) {
      final names = assignment[dayNumber]!.map((p) => p.name).join(', ');
      debugPrint('[GeographicAssignment] Day $dayNumber: $names');
    }
    debugPrint('[GeographicAssignment] =========================');

    return assignment;
  }
}
