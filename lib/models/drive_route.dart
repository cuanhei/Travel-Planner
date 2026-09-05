import 'package:latlong2/latlong.dart';

import '../utils/google_routes_parsing.dart';
import '../utils/polyline_codec.dart';

class DriveRoute {
  const DriveRoute({
    required this.duration,
    required this.distanceMeters,
    required this.polylinePoints,
  });

  final Duration duration;
  final int distanceMeters;
  final List<LatLng> polylinePoints;

  factory DriveRoute.fromJson(Map<String, dynamic> json) {
    final polyline =
        (json['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;
    return DriveRoute(
      duration: parseGoogleDuration(json['duration'] as String?),
      distanceMeters: (json['distanceMeters'] as num?)?.toInt() ?? 0,
      polylinePoints: decodePolyline(polyline ?? ''),
    );
  }
}
