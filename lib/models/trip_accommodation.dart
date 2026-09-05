/// Where a trip's traveler(s) stay on one specific night, backed by
/// `trip_accommodations`. [nightNumber] is 1-indexed — night 1 is the
/// night after day 1, so an N-day trip has nights 1..N-1.
class TripAccommodation {
  const TripAccommodation({
    required this.id,
    required this.tripId,
    required this.nightNumber,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String tripId;
  final int nightNumber;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  factory TripAccommodation.fromMap(Map<String, dynamic> map) {
    return TripAccommodation(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      nightNumber: map['night_number'] as int,
      name: map['name'] as String,
      address: map['address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
    );
  }
}
