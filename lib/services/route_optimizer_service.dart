import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';
import 'route_service.dart';

/// Greedy nearest-next-stop route ordering for a single day's stops,
/// bounded by that day's own starting point and ending point — e.g. Day
/// 1's trip starting location through its accommodation for the night, or
/// a later day's previous-night accommodation through the trip's ending
/// location on the last day. Deliberately simple (per the trip-planning
/// spec: "do not implement an unnecessarily complex route optimization
/// algorithm") — this reorders stops for travel efficiency only; weather
/// suitability and opening-hours fit are handled elsewhere and aren't
/// considered here.
class RouteOptimizerService {
  RouteOptimizerService({RouteService? routeService})
    : _routeService = routeService ?? RouteService();

  final RouteService _routeService;

  /// Reorders [stops] into a greedy nearest-neighbor path: starting from
  /// [origin] (the day's starting location or previous night's
  /// accommodation), repeatedly travel to whichever remaining stop is
  /// closest by real travel time (not straight-line distance), until
  /// none are left. [destination] (that day's own accommodation, or the
  /// trip's ending location on the last day) isn't itself reordered or
  /// inserted into the result — it's only used to break a tie when two
  /// remaining stops are otherwise equally close, preferring whichever
  /// one leaves a shorter final leg to it. Pass `useTransit: true` to
  /// query [RouteService.getTransitRoutes] instead of
  /// [RouteService.getDriveRoute] for every candidate leg, matching
  /// whichever transport mode the day's timeline is using.
  ///
  /// Returns [stops] unchanged (a copy) if there are 0 or 1 of them —
  /// nothing to reorder. A stop the API couldn't compute *any* travel
  /// time to/from (a request failure) is treated as unreachable and
  /// appended in its original relative order at the very end, after
  /// every stop that could be measured, rather than silently dropped.
  Future<List<TripStopLocation>> optimize({
    required TripStopLocation origin,
    required List<TripStopLocation> stops,
    TripStopLocation? destination,
    bool useTransit = false,
  }) async {
    if (stops.length <= 1) return List.of(stops);

    final remaining = List<TripStopLocation>.of(stops);
    final ordered = <TripStopLocation>[];
    final unreachable = <TripStopLocation>[];
    var current = origin;

    while (remaining.isNotEmpty) {
      TripStopLocation? best;
      Duration? bestDuration;
      Duration? bestToDestination;

      for (final candidate in remaining) {
        final duration = await _travelTime(current, candidate, useTransit);
        if (duration == null) continue;

        if (bestDuration == null || duration < bestDuration) {
          best = candidate;
          bestDuration = duration;
          bestToDestination = null;
          continue;
        }

        // Tie (to the same rounded duration isn't checked — only an
        // exact match, which mainly matters when two stops are right
        // next to each other) — prefer whichever leaves a shorter final
        // leg to the day's destination, when there is one.
        if (duration == bestDuration && destination != null) {
          bestToDestination ??= await _travelTime(best!, destination, useTransit);
          final candidateToDestination = await _travelTime(candidate, destination, useTransit);
          if (candidateToDestination != null &&
              (bestToDestination == null || candidateToDestination < bestToDestination)) {
            best = candidate;
            bestToDestination = candidateToDestination;
          }
        }
      }

      if (best == null) {
        // Nothing remaining had a computable travel time from `current` at
        // all (every request failed) — stop trying to order what's left
        // and just append it in its original order.
        unreachable.addAll(remaining);
        break;
      }

      ordered.add(best);
      remaining.remove(best);
      current = best;
    }

    return [...ordered, ...unreachable];
  }

  Future<Duration?> _travelTime(
    TripStopLocation from,
    TripStopLocation to,
    bool useTransit,
  ) async {
    final origin = LatLng(from.latitude, from.longitude);
    final destination = LatLng(to.latitude, to.longitude);
    try {
      if (useTransit) {
        final routes = await _routeService.getTransitRoutes(
          origin: origin,
          destination: destination,
        );
        return routes.isEmpty ? null : routes.first.duration;
      }
      final route = await _routeService.getDriveRoute(
        origin: origin,
        destination: destination,
      );
      return route?.duration;
    } catch (_) {
      return null;
    }
  }
}
