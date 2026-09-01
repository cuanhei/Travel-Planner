import 'package:flutter/material.dart';

/// A real, geocoded location picked for a trip stop — via Photon search,
/// a manual tap on the map, or the user's current GPS position. Distinct
/// from `trip_data.dart`'s `TripStop` (a scheduled itinerary entry with a
/// day/time) and from Explore's `Place` (curated attraction content) —
/// this is the raw place data needed to plot and re-find it later.
class TripStopLocation {
  const TripStopLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.id,
    this.osmId,
    this.category = 'Other',
  });

  /// `trip_stops.id` — null for a freshly-picked search/map result that
  /// hasn't been saved to a trip yet.
  final String? id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  /// OSM feature reference (e.g. "N123456"), when the source result came
  /// from OpenStreetMap data. Null for points with no OSM match.
  final String? osmId;

  /// Coarse category derived from the source's OSM tag (e.g. "Shopping",
  /// "Food", "Hotel", "Attraction") — see `PhotonService`. Defaults to
  /// "Other" for points with no recognizable tag, like a raw GPS drop.
  final String category;

  /// Icon representing [category], for chips, list tiles, and cards.
  IconData get categoryIcon => iconForCategory(category);

  factory TripStopLocation.fromMap(Map<String, dynamic> map) {
    return TripStopLocation(
      id: map['id'] as String,
      name: map['name'] as String,
      address: map['address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      osmId: map['osm_id'] as String?,
      category: (map['category'] as String?) ?? 'Other',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TripStopLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.osmId == osmId;

  @override
  int get hashCode => Object.hash(latitude, longitude, osmId);
}

/// Icon for a stop category label (see [TripStopLocation.category]) — a
/// standalone function so callers with just the category string (e.g. the
/// Create Trip "Interests" chips, built from whichever categories are
/// present among the picked stops) don't need a [TripStopLocation] instance.
IconData iconForCategory(String category) {
  switch (category) {
    case 'Shopping':
      return Icons.shopping_bag_rounded;
    case 'Food':
      return Icons.restaurant_rounded;
    case 'Hotel':
      return Icons.hotel_rounded;
    case 'Attraction':
      return Icons.attractions_rounded;
    case 'Nature':
      return Icons.terrain_rounded;
    case 'Beach':
      return Icons.beach_access_rounded;
    case 'Culture':
      return Icons.museum_rounded;
    case 'Transport':
      return Icons.directions_bus_filled_rounded;
    case 'Health':
      return Icons.local_hospital_rounded;
    case 'Finance':
      return Icons.account_balance_rounded;
    default:
      return Icons.location_pin;
  }
}
