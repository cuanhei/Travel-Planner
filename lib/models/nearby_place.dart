import 'package:flutter/material.dart';

/// A real place from Google Places API (New) Nearby Search — backs the
/// Explore tab's "Nearby Places" section. Distinct from the dummy
/// `Place` catalog Popular Destinations/Categories still use.
class NearbyPlace {
  const NearbyPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.primaryType,
    required this.photoUrl,
    required this.businessStatus,
    this.distanceKm,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  /// Google's coarse type string for this place (e.g. "restaurant",
  /// "tourist_attraction") — used only to pick [icon] here; not shown as
  /// text anywhere on the card.
  final String? primaryType;

  /// Ready-to-use `Image.network` URL for the place's first photo
  /// (already carries the API key), or null if Places returned none —
  /// callers fall back to the same gradient+icon placeholder the card
  /// always showed before this was wired to real data.
  final String? photoUrl;

  final String? businessStatus;

  /// Straight-line distance from the search center, in kilometers. Null
  /// until [withDistanceKm] sets it.
  final double? distanceKm;

  /// e.g. "1.2 km", or "—" if not yet computed.
  String get distanceLabel =>
      distanceKm == null ? '—' : '${distanceKm!.toStringAsFixed(1)} km';

  IconData get icon => _iconForPrimaryType(primaryType);

  NearbyPlace withDistanceKm(double km) => NearbyPlace(
    id: id,
    name: name,
    address: address,
    latitude: latitude,
    longitude: longitude,
    primaryType: primaryType,
    photoUrl: photoUrl,
    businessStatus: businessStatus,
    distanceKm: km,
  );

  factory NearbyPlace.fromJson(
    Map<String, dynamic> json, {
    required String apiKey,
    required int photoMaxWidthPx,
  }) {
    final displayName = json['displayName'] as Map<String, dynamic>?;
    final location = json['location'] as Map<String, dynamic>?;
    final photos = json['photos'] as List?;
    final firstPhotoName = (photos != null && photos.isNotEmpty)
        ? (photos.first as Map<String, dynamic>)['name'] as String?
        : null;
    return NearbyPlace(
      id: json['id'] as String,
      name: (displayName?['text'] as String?) ?? 'Unnamed place',
      address: (json['formattedAddress'] as String?) ?? '',
      latitude: (location?['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (location?['longitude'] as num?)?.toDouble() ?? 0,
      primaryType: json['primaryType'] as String?,
      photoUrl: firstPhotoName == null
          ? null
          : 'https://places.googleapis.com/v1/$firstPhotoName/media'
                '?maxWidthPx=$photoMaxWidthPx&key=$apiKey',
      businessStatus: json['businessStatus'] as String?,
    );
  }
}

IconData _iconForPrimaryType(String? type) {
  switch (type) {
    case 'restaurant':
    case 'cafe':
    case 'meal_takeaway':
    case 'bakery':
      return Icons.restaurant_rounded;
    case 'tourist_attraction':
    case 'point_of_interest':
      return Icons.attractions_rounded;
    case 'park':
    case 'national_park':
      return Icons.terrain_rounded;
    case 'shopping_mall':
    case 'store':
    case 'clothing_store':
      return Icons.shopping_bag_rounded;
    case 'museum':
    case 'art_gallery':
      return Icons.museum_rounded;
    case 'hotel':
    case 'lodging':
      return Icons.hotel_rounded;
    case 'beach':
      return Icons.beach_access_rounded;
    case 'night_club':
    case 'bar':
      return Icons.nightlife_rounded;
    case 'place_of_worship':
    case 'hindu_temple':
    case 'mosque':
    case 'church':
      return Icons.holiday_village_rounded;
    default:
      return Icons.place_rounded;
  }
}
