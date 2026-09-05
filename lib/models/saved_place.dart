import 'nearby_place.dart';

class SavedPlace {
  const SavedPlace({
    required this.id,
    required this.userId,
    required this.placeId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.primaryType,
    required this.photoUrl,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String placeId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String? primaryType;
  final String? photoUrl;
  final DateTime createdAt;

  factory SavedPlace.fromMap(Map<String, dynamic> map) {
    return SavedPlace(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      placeId: map['place_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String? ?? '',
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      primaryType: map['primary_type'] as String?,
      photoUrl: map['photo_url'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  NearbyPlace toNearbyPlace() => NearbyPlace(
    id: placeId,
    name: name,
    address: address,
    latitude: latitude,
    longitude: longitude,
    primaryType: primaryType,
    types: const [],
    photoUrl: photoUrl,
    businessStatus: null,
    editorialSummary: null,
    priceLevel: null,
    priceRangeLabel: null,
    regularOpeningHours: null,
    regularOpeningHoursPeriods: null,
    currentOpeningHours: null,
    currentOpeningHoursPeriods: null,
    openNow: null,
  );
}
