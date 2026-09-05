import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';
import 'route_service.dart';

class TravelTimeCache {
  TravelTimeCache({RouteService? routeService})
    : _routeService = routeService ?? RouteService();

  final RouteService _routeService;
  final Map<String, Duration> _cache = {};

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
