import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'photon_service.dart';

class PostLocationService {
  final _photon = PhotonService();

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

      final name = result?.district ?? result?.city ?? result?.state;
      return (name == null || name.isEmpty) ? null : name;
    } catch (_) {
      return null;
    }
  }
}
