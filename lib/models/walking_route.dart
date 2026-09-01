import 'package:latlong2/latlong.dart';

import '../utils/google_routes_parsing.dart';
import '../utils/polyline_codec.dart';

/// A single ad-hoc walking route between two points — used only to
/// reroute a live navigation's current WALK segment (e.g. the traveler
/// strayed from the expected path) via Google Routes API with
/// `travelMode: "WALK"`. Not part of trip planning/search, so it's kept
/// separate from [TransitRoute] rather than folded into it.
class WalkingRoute {
  const WalkingRoute({
    required this.duration,
    required this.distanceMeters,
    required this.polylinePoints,
  });

  final Duration duration;
  final int distanceMeters;
  final List<LatLng> polylinePoints;

  factory WalkingRoute.fromJson(Map<String, dynamic> json) {
    final polyline =
        (json['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;
    return WalkingRoute(
      duration: parseGoogleDuration(json['duration'] as String?),
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      polylinePoints: decodePolyline(polyline ?? ''),
    );
  }
}
