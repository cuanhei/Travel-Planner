import 'package:latlong2/latlong.dart';

import '../../models/nearby_place.dart';
import '../../models/trip_stop_location.dart';
import '../../services/google_places_service.dart';
import 'place_identity.dart';

/// spec §4's "Recommend accommodation" option: the traveler asked the
/// app to pick a place to stay rather than adding their own, so search
/// real lodging near the trip and suggest the best-looking one —
/// [TripStopLocation.fromNearbyPlace] already infers
/// `visitPurpose = accommodation` for a lodging-typed result (see
/// [TripStopLocation.category]'s mapping), so nothing extra needs
/// tagging on the way out.
///
/// [nearStops] should be the traveler's own selected places (spec §6's
/// priority stops) when there are any — accommodation is centered on
/// where the trip actually happens, not an arbitrary point. Falls back
/// to [fallbackCenter] (the trip's Starting-From location) only when
/// [nearStops] is empty, and returns null when there's nowhere at all
/// to search near, no lodging is found, or the Places lookup fails
/// (network/quota) — a failed suggestion here should never block trip
/// creation, just leave accommodation unset for the traveler to add
/// manually later.
Future<TripStopLocation?> findRecommendedAccommodation({
  required List<TripStopLocation> nearStops,
  TripStopLocation? fallbackCenter,
  GooglePlacesService? placesService,
}) async {
  final points = nearStops.isNotEmpty
      ? nearStops
      : (fallbackCenter != null
            ? [fallbackCenter]
            : const <TripStopLocation>[]);
  if (points.isEmpty || points.any((p) => !hasValidCoordinates(p))) return null;

  final centerLat =
      points.map((s) => s.latitude).reduce((a, b) => a + b) / points.length;
  final centerLng =
      points.map((s) => s.longitude).reduce((a, b) => a + b) / points.length;

  final places = placesService ?? GooglePlacesService();
  List<NearbyPlace> found;
  try {
    found = await places.nearbySearch(
      center: LatLng(centerLat, centerLng),
      includedTypes: const {'lodging'},
    );
  } catch (_) {
    return null;
  }

  final candidates =
      found
          .where(
            (p) =>
                hasValidCoordinates(TripStopLocation.fromNearbyPlace(p)) &&
                TripStopLocation.fromNearbyPlace(p).category == 'Hotel' &&
                p.businessStatus != 'CLOSED_PERMANENTLY' &&
                p.businessStatus != 'CLOSED_TEMPORARILY',
          )
          .toList()
        ..sort((a, b) {
          final byRating = (b.rating ?? 0).compareTo(a.rating ?? 0);
          if (byRating != 0) return byRating;
          return (b.userRatingCount ?? 0).compareTo(a.userRatingCount ?? 0);
        });
  if (candidates.isEmpty) return null;

  return TripStopLocation.fromNearbyPlace(candidates.first);
}
