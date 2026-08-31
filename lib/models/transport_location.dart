/// A real, Malaysia-only place picked from the Transport module's
/// location search — used for both the "Depart From" origin (GPS or
/// searched) and the destination search. The raw geocoded data needed to
/// later request a route between the two via the Route API. Distinct
/// from `TripStopLocation` (trip-planning stops) and Explore's `Place`
/// (curated attraction content).
class TransportLocation {
  const TransportLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String address;
  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is TransportLocation &&
      other.name == name &&
      other.address == address &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(name, address, latitude, longitude);
}
