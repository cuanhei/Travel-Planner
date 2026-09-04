import '../../models/trip_stop_location.dart';

/// Physical-place identity for recommendations, independent of visit IDs.
/// Repeated meal and accommodation visits may legitimately share this key.
String placeIdentity(TripStopLocation stop) {
  final googleId = stop.placeId?.trim();
  if (googleId != null && googleId.isNotEmpty) return 'google:$googleId';
  final osmId = stop.osmId?.trim();
  if (osmId != null && osmId.isNotEmpty) return 'osm:$osmId';
  return '${stop.name.trim().toLowerCase()}:'
      '${stop.latitude.toStringAsFixed(5)},${stop.longitude.toStringAsFixed(5)}';
}

bool hasValidCoordinates(TripStopLocation stop) =>
    stop.latitude.isFinite &&
    stop.longitude.isFinite &&
    stop.latitude >= -90 &&
    stop.latitude <= 90 &&
    stop.longitude >= -180 &&
    stop.longitude <= 180;
