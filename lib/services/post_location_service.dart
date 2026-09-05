import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'photon_service.dart';

/// Resolves the poster's real current location to a short, human-readable
/// area name (e.g. "George Town", "Bayan Lepas", "Gelugor") for a
/// Community post's "IP: …" line. Despite the label — kept as-is from
/// when this showed a raw IP address (see `supabase/migrations/
/// 0026_post_ip_and_location_sharing.sql`) — it now resolves the
/// device's actual GPS position via [Geolocator] and reverse-geocodes it
/// with Photon, the same approach Weather uses to match a position to a
/// forecast area (`weather_service.dart`), rather than the much
/// coarser/less accurate location an IP address alone would imply.
///
/// Capture always happens at post time regardless of the poster's
/// Location Sharing setting; that setting only controls whether
/// `PostCard` later *displays* the resolved name or "Unknown" — see
/// `CommunityService.addPost`.
class PostLocationService {
  final _photon = PhotonService();

  /// Returns a short area name for the device's current GPS position, or
  /// `null` if location services/permission aren't available or the
  /// lookup otherwise fails — a post should still go through without one
  /// rather than blocking on this.
  Future<String?> resolveCurrentAreaName() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 8));

      final result = await _photon.reverseAdministrative(
        LatLng(position.latitude, position.longitude),
      );
      // Prefer the finer-grained district/suburb name (e.g. "Bayan
      // Lepas") over the whole city, falling back progressively to
      // whatever Photon's OSM data actually has for a sparsely-mapped
      // point.
      final name = result?.district ?? result?.city ?? result?.state;
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null;
    }
  }
}
