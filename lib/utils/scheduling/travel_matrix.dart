import 'package:latlong2/latlong.dart';

import '../../models/trip_stop_location.dart';
import '../../services/route_service.dart';
import 'place_identity.dart';

/// How the traveler gets between stops — mirrors `trips.transport_mode`.
enum TravelMode {
  walk,
  drive,
  publicTransport;

  /// Parses `trips.transport_mode`'s raw column value — null (a trip
  /// created before this column existed, or one that simply never set
  /// it) and anything unrecognized (e.g. the DB's 'mixed', which this
  /// app doesn't yet have a per-leg mode strategy for — see
  /// `RouteServiceTravelMatrix`'s doc comment) both fall back to
  /// [drive], matching this class's pre-existing default.
  static TravelMode fromDbValue(String? value) => switch (value) {
    'walk' => TravelMode.walk,
    'public_transport' => TravelMode.publicTransport,
    _ => TravelMode.drive,
  };
}

/// Resolves travel time between two stops. An interface (rather than a
/// concrete class used directly) so the scheduling engine's day-
/// assignment/ordering code depends only on "give me a travel time",
/// not on how it's computed — see [RouteServiceTravelMatrix]'s doc
/// comment for why the current implementation fans out over
/// [RouteService]'s one-to-one `computeRoutes` rather than using
/// Google's many-to-many `computeRouteMatrix` endpoint.
abstract class TravelMatrixSource {
  /// Travel time from [from] to [to], or null if no route could be
  /// found (e.g. the API had nothing for that pair) — the scheduling
  /// engine treats a null travel time as "this pair can't be scored",
  /// not as zero minutes.
  Future<Duration?> travelTime(TripStopLocation from, TripStopLocation to);
}

/// [TravelMatrixSource] backed by [RouteService]'s existing one-to-one
/// `computeRoutes` calls, fanned out across every relevant pair and
/// cached per scheduling run (a trip's stop set doesn't change
/// mid-run, so there's no cross-run invalidation to handle). Google's
/// Routes API also has a purpose-built many-to-many
/// `computeRouteMatrix` endpoint that would need only one HTTP call
/// instead of N², but its availability under this project's API
/// key/billing tier is unverified — this fan-out approach works with
/// what's already confirmed enabled, and can be swapped in behind
/// [TravelMatrixSource] later without changing any calling code.
class RouteServiceTravelMatrix implements TravelMatrixSource {
  RouteServiceTravelMatrix({
    RouteService? routeService,
    this.travelMode = TravelMode.drive,
  }) : _routeService = routeService ?? RouteService();

  final RouteService _routeService;
  final TravelMode travelMode;

  final Map<String, Duration?> _cache = {};

  String _pairKey(TripStopLocation from, TripStopLocation to) =>
      '${from.latitude},${from.longitude}->${to.latitude},${to.longitude}';

  @override
  Future<Duration?> travelTime(
    TripStopLocation from,
    TripStopLocation to,
  ) async {
    if (!hasValidCoordinates(from) || !hasValidCoordinates(to)) return null;
    if (from.latitude == to.latitude && from.longitude == to.longitude) {
      return Duration.zero;
    }
    final key = _pairKey(from, to);
    if (_cache.containsKey(key)) return _cache[key];

    final origin = LatLng(from.latitude, from.longitude);
    final destination = LatLng(to.latitude, to.longitude);
    Duration? duration;
    try {
      switch (travelMode) {
        case TravelMode.drive:
          duration = (await _routeService.getDriveRoute(
            origin: origin,
            destination: destination,
          ))?.duration;
        case TravelMode.walk:
          duration = (await _routeService.getWalkingRoute(
            origin: origin,
            destination: destination,
          ))?.duration;
        case TravelMode.publicTransport:
          final routes = await _routeService.getTransitRoutes(
            origin: origin,
            destination: destination,
          );
          duration = routes.isEmpty ? null : routes.first.duration;
      }
    } catch (_) {
      duration = null;
    }
    // A failed lookup can recover when the user retries after reconnecting.
    if (duration != null) _cache[key] = duration;
    return duration;
  }

  /// Warms the cache for every ordered pair among [stops] before the
  /// day-assignment/ordering passes run, so they can call
  /// [travelTime] synchronously-fast (cache hit) instead of each
  /// awaiting a fresh HTTP call one pair at a time. Batches
  /// [concurrency] requests at once rather than firing all N² at
  /// once — a 15-stop trip is already 210 pairs.
  Future<void> precompute(
    List<TripStopLocation> stops, {
    int concurrency = 10,
  }) async {
    final pairs = <(TripStopLocation, TripStopLocation)>[
      for (final from in stops)
        for (final to in stops)
          if (from != to) (from, to),
    ];
    for (var i = 0; i < pairs.length; i += concurrency) {
      final batch = pairs.skip(i).take(concurrency);
      await Future.wait([for (final (from, to) in batch) travelTime(from, to)]);
    }
  }
}
