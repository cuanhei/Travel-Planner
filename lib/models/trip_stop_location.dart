import 'package:flutter/material.dart';

import 'nearby_place.dart';

/// A real, geocoded location picked for a trip stop — via Photon search,
/// Google Places search (Create Trip's stop picker), a manual tap on the
/// map, or the user's current GPS position. Distinct from
/// `trip_data.dart`'s `TripStop` (a scheduled itinerary entry with a
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
    this.regularOpeningHours,
    this.currentOpeningHours,
    this.openNow,
  });

  /// `trip_stops.id` — null for a freshly-picked search/map result that
  /// hasn't been saved to a trip yet.
  final String? id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  /// OSM feature reference (e.g. "N123456"), when the source result came
  /// from OpenStreetMap data. Null for points with no OSM match — always
  /// null for a Google Places result (see [fromNearbyPlace]).
  final String? osmId;

  /// Coarse category derived from the source's OSM tag (Photon) or
  /// `primaryType` (Google Places) — e.g. "Shopping", "Food", "Hotel",
  /// "Attraction". Defaults to "Other" for points with no recognizable
  /// type, like a raw GPS drop.
  final String category;

  /// One line per weekday (e.g. "Monday: 9:00 AM – 6:00 PM", or
  /// "Sunday: Closed") from Google Places' `regularOpeningHours` — the
  /// place's normal schedule. Only ever set for a Google-sourced stop
  /// (see [fromNearbyPlace]); null for Photon/OSM results, which carry
  /// no opening-hours data.
  final List<String>? regularOpeningHours;

  /// Same shape as [regularOpeningHours] but from `currentOpeningHours`
  /// — accounts for near-term exceptions (public holiday closures, etc.)
  /// rather than just the typical weekly schedule.
  final List<String>? currentOpeningHours;

  /// Whether the place is open right now, per Google. Null if unknown or
  /// not a Google-sourced stop.
  final bool? openNow;

  /// [currentOpeningHours] if present (more specific — reflects today's
  /// actual exceptions), else the fallback [regularOpeningHours].
  List<String>? get openingHours => currentOpeningHours ?? regularOpeningHours;

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

  /// Converts a Google Places API (New) result — from the same
  /// [GooglePlacesService] backing Explore's Nearby Places — into a stop
  /// for Create Trip's location picker, carrying name/coordinates plus
  /// [category] (mapped from Google's `primaryType`) and opening-hours
  /// data Photon never had.
  factory TripStopLocation.fromNearbyPlace(NearbyPlace place) {
    return TripStopLocation(
      name: place.name,
      address: place.address,
      latitude: place.latitude,
      longitude: place.longitude,
      category: _categoryForGoogleType(place.primaryType),
      regularOpeningHours: place.regularOpeningHours,
      currentOpeningHours: place.currentOpeningHours,
      openNow: place.openNow,
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

/// Maps Google Places' `primaryType` to the same coarse category labels
/// [PhotonService]'s OSM-tag mapping produces, so a stop's [categoryIcon]
/// (and any category-based logic downstream) works identically regardless
/// of which search backend found it.
String _categoryForGoogleType(String? type) {
  switch (type) {
    case 'shopping_mall':
    case 'store':
    case 'clothing_store':
    case 'department_store':
    case 'supermarket':
    case 'convenience_store':
    case 'shoe_store':
    case 'jewelry_store':
    case 'book_store':
    case 'market':
      return 'Shopping';
    case 'restaurant':
    case 'cafe':
    case 'bakery':
    case 'meal_takeaway':
    case 'meal_delivery':
    case 'food_court':
    case 'ice_cream_shop':
    case 'fast_food_restaurant':
    case 'bar':
    case 'pub':
      return 'Food';
    case 'park':
    case 'national_park':
    case 'garden':
    case 'hiking_area':
    case 'zoo':
    case 'aquarium':
    case 'wildlife_park':
      return 'Nature';
    case 'beach':
      return 'Beach';
    case 'museum':
    case 'art_museum':
    case 'history_museum':
    case 'art_gallery':
    case 'tourist_attraction':
    case 'historical_landmark':
    case 'historical_place':
    case 'cultural_landmark':
    case 'performing_arts_theater':
    case 'monument':
    case 'place_of_worship':
    case 'hindu_temple':
    case 'mosque':
    case 'church':
    case 'synagogue':
      return 'Culture';
    case 'hotel':
    case 'lodging':
    case 'guest_house':
    case 'hostel':
    case 'motel':
      return 'Hotel';
    case 'hospital':
    case 'clinic':
    case 'pharmacy':
    case 'doctor':
    case 'dentist':
      return 'Health';
    case 'bank':
    case 'atm':
      return 'Finance';
    case 'bus_station':
    case 'train_station':
    case 'subway_station':
    case 'transit_station':
    case 'light_rail_station':
    case 'airport':
      return 'Transport';
    default:
      return 'Other';
  }
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
