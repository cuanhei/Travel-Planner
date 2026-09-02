import '../models/transport_location.dart';
import 'photon_service.dart';

/// Malaysia-restricted, search-as-you-type location lookup shared by the
/// Transport module's "Depart From" and "Destination" fields. A thin
/// adapter over [PhotonService] — reuses its Photon query, Malaysia
/// bounding box, and strict `countrycode == 'MY'` filtering, but returns
/// the lighter [TransportLocation] shape instead of trip-stop data.
class TransportLocationService {
  TransportLocationService([PhotonService? photonService])
      : _photon = photonService ?? PhotonService();

  final PhotonService _photon;

  Future<List<TransportLocation>> search(String query) async {
    final results = await _photon.search(query);
    return [
      for (final stop in results)
        TransportLocation(
          name: stop.name,
          address: stop.address,
          latitude: stop.latitude,
          longitude: stop.longitude,
        ),
    ];
  }
}
