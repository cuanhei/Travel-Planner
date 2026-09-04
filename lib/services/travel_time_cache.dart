import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';
import 'route_service.dart';

/// Caches driving duration between pairs of [TripStopLocation]s, backed
/// by [RouteService.getDriveRoute] (Google Routes API, billed per call).
/// Shared by [GeographicAssignmentService] and [DayScheduleService],
/// both of which repeatedly ask about the same handful of anchor points
/// (a day's start/end anchor is often shared with its neighboring day).
class TravelTimeCache {
  TravelTimeCache({RouteService? routeService})
    : _routeService = routeService ?? RouteService();

  final RouteService _routeService;
  final Map<String, Duration> _cache = {};

  /// Driving duration between [from] and [to] — [Duration.zero] when
  /// they're the same real place, or when the route request fails,
  /// rather than letting one bad network call abort a larger computation
  /// that depends on many of these.
  Future<Duration> durationBetween(
    TripStopLocation from,
    TripStopLocation to,
  ) async {
    if (from == to) return Duration.zero;

    final key = _cacheKey(from, to);
    final cached = _cache[key];
    if (cached != null) return cached;

    Duration duration;
    try {
      final route = await _routeService.getDriveRoute(
        origin: LatLng(from.latitude, from.longitude),
        destination: LatLng(to.latitude, to.longitude),
      );
      duration = route?.duration ?? Duration.zero;
    } catch (_) {
      duration = Duration.zero;
    }
    _cache[key] = duration;
    return duration;
  }

  String _cacheKey(TripStopLocation from, TripStopLocation to) =>
      '${from.latitude},${from.longitude}|${to.latitude},${to.longitude}';
}
