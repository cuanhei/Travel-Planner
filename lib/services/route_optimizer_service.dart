import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';
import 'route_service.dart';

class RouteOptimizerService {
  RouteOptimizerService({RouteService? routeService})
    : _routeService = routeService ?? RouteService();

  final RouteService _routeService;

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

        if (duration == bestDuration && destination != null) {
          bestToDestination ??= await _travelTime(
            best!,
            destination,
            useTransit,
          );
          final candidateToDestination = await _travelTime(
            candidate,
            destination,
            useTransit,
          );
          if (candidateToDestination != null &&
              (bestToDestination == null ||
                  candidateToDestination < bestToDestination)) {
            best = candidate;
            bestToDestination = candidateToDestination;
          }
        }
      }

      if (best == null) {
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
