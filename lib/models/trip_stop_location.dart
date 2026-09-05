import 'package:flutter/material.dart';

import 'nearby_place.dart';
import 'place_environment.dart';
import 'visit_duration.dart';

class TripStopLocation {
  const TripStopLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.id,
    this.osmId,
    this.placeId,
    this.category = 'Other',
    this.primaryType,
    this.types = const [],
    this.businessStatus,
    this.regularOpeningHours,
    this.regularOpeningHoursPeriods,
    this.currentOpeningHours,
    this.currentOpeningHoursPeriods,
    this.openNow,
  });

  final String? id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  final String? osmId;

  final String? placeId;

  final String category;

  final String? primaryType;

  final List<String> types;

  final String? businessStatus;

  final List<String>? regularOpeningHours;

  final List<OpeningHoursPeriod>? regularOpeningHoursPeriods;

  final List<String>? currentOpeningHours;

  final List<OpeningHoursPeriod>? currentOpeningHoursPeriods;

  final bool? openNow;

  List<String>? get openingHours => currentOpeningHours ?? regularOpeningHours;

  List<OpeningHoursPeriod>? get openingHoursPeriods =>
      currentOpeningHoursPeriods ?? regularOpeningHoursPeriods;

  IconData get categoryIcon => iconForCategory(category);

  int get estimatedVisitMinutes => estimateVisitDuration(primaryType, types);

  PlaceEnvironment get environment => getEnvironment(primaryType, types);

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

  factory TripStopLocation.fromNearbyPlace(NearbyPlace place) {
    return TripStopLocation(
      placeId: place.id,
      name: place.name,
      address: place.address,
      latitude: place.latitude,
      longitude: place.longitude,
      category: _categoryForGoogleType(place.primaryType),
      primaryType: place.primaryType,
      types: place.types,
      businessStatus: place.businessStatus,
      regularOpeningHours: place.regularOpeningHours,
      regularOpeningHoursPeriods: place.regularOpeningHoursPeriods,
      currentOpeningHours: place.currentOpeningHours,
      currentOpeningHoursPeriods: place.currentOpeningHoursPeriods,
      openNow: place.openNow,
    );
  }

  bool get isAddressOnly =>
      types.isNotEmpty && types.every(_addressOnlyTypes.contains);

  @override
  bool operator ==(Object other) =>
      other is TripStopLocation &&
      (placeId != null && other.placeId != null
          ? other.placeId == placeId
          : other.latitude == latitude &&
                other.longitude == longitude &&
                other.osmId == osmId);

  @override
  int get hashCode =>
      placeId?.hashCode ?? Object.hash(latitude, longitude, osmId);
}

const _addressOnlyTypes = {
  'premise',
  'subpremise',
  'street_address',
  'street_number',
  'route',
  'intersection',
  'locality',
  'sublocality',
  'sublocality_level_1',
  'sublocality_level_2',
  'sublocality_level_3',
  'sublocality_level_4',
  'sublocality_level_5',
  'neighborhood',
  'postal_code',
  'postal_town',
  'administrative_area_level_1',
  'administrative_area_level_2',
  'administrative_area_level_3',
  'administrative_area_level_4',
  'administrative_area_level_5',
  'country',
  'plus_code',
};

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
