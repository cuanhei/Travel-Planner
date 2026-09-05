import 'package:flutter/material.dart';

import 'nearby_place.dart';
import 'place_environment.dart';
import 'visit_duration.dart';

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

  /// Google's unique Place ID (from Places' `id` field), when the source
  /// result came from Google Places. Distinct from [id] (this app's own
  /// `trip_stops.id`) — used to detect the traveler re-picking the same
  /// real-world place (even if [latitude]/[longitude] drift slightly
  /// between two searches) and to refetch fresh place details later.
  /// Null for Photon/OSM results, which have no Google identifier.
  final String? placeId;

  /// Coarse category derived from the source's OSM tag (Photon) or
  /// `primaryType` (Google Places) — e.g. "Shopping", "Food", "Hotel",
  /// "Attraction". Defaults to "Other" for points with no recognizable
  /// type, like a raw GPS drop.
  final String category;

  /// Google's raw `primaryType` (e.g. "tourist_attraction",
  /// "shopping_mall") — the single most-specific type tag Places
  /// assigns, kept alongside [category] (this app's coarser bucket
  /// derived from it) since downstream logic (visit-duration estimates,
  /// etc.) may want Google's own classification directly. Null for
  /// Photon/OSM results.
  final String? primaryType;

  /// Every Google Places type tag (e.g. `["restaurant", "food",
  /// "point_of_interest"]`) — finer-grained than [category] when that
  /// single bucket isn't enough (e.g. estimating visit duration). Empty
  /// for Photon/OSM results.
  final List<String> types;

  /// Google's `businessStatus` (`OPERATIONAL`, `CLOSED_TEMPORARILY`, or
  /// `CLOSED_PERMANENTLY`) — whether the place is still in business at
  /// all, separate from [openNow] (open *right now* vs. open *ever
  /// again*). Null for Photon/OSM results, which don't report this.
  final String? businessStatus;

  /// One line per weekday (e.g. "Monday: 9:00 AM – 6:00 PM", or
  /// "Sunday: Closed") from Google Places' `regularOpeningHours` — the
  /// place's normal schedule. Only ever set for a Google-sourced stop
  /// (see [fromNearbyPlace]); null for Photon/OSM results, which carry
  /// no opening-hours data.
  final List<String>? regularOpeningHours;

  /// Machine-readable open/close windows behind [regularOpeningHours] —
  /// for scheduling logic (e.g. flagging a stop that'll be closed by the
  /// time the itinerary reaches it), not just displaying hours as text.
  final List<OpeningHoursPeriod>? regularOpeningHoursPeriods;

  /// Same shape as [regularOpeningHours] but from `currentOpeningHours`
  /// — accounts for near-term exceptions (public holiday closures, etc.)
  /// rather than just the typical weekly schedule.
  final List<String>? currentOpeningHours;

  /// Machine-readable equivalent of [currentOpeningHours].
  final List<OpeningHoursPeriod>? currentOpeningHoursPeriods;

  /// Whether the place is open right now, per Google. Null if unknown or
  /// not a Google-sourced stop.
  final bool? openNow;

  /// [currentOpeningHours] if present (more specific — reflects today's
  /// actual exceptions), else the fallback [regularOpeningHours].
  List<String>? get openingHours => currentOpeningHours ?? regularOpeningHours;

  /// [currentOpeningHoursPeriods] if present, else [regularOpeningHoursPeriods].
  List<OpeningHoursPeriod>? get openingHoursPeriods =>
      currentOpeningHoursPeriods ?? regularOpeningHoursPeriods;

  /// Icon representing [category], for chips, list tiles, and cards.
  IconData get categoryIcon => iconForCategory(category);

  /// Estimated minutes a traveler spends here (see [estimateVisitDuration])
  /// — used to work out how many stops reasonably fit in a day. Falls
  /// back to [defaultVisitDurationMinutes] for a Photon/OSM stop, which
  /// carries no [primaryType]/[types] at all.
  int get estimatedVisitMinutes => estimateVisitDuration(primaryType, types);

  /// Indoor/outdoor/mixed/unknown (see [getEnvironment]) — for
  /// weather-aware scheduling, e.g. steering a rain-forecast day away
  /// from outdoor stops. [PlaceEnvironment.unknown] for a Photon/OSM
  /// stop, which carries no [primaryType]/[types] at all.
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

  /// Converts a Google Places API (New) result — from the same
  /// [GooglePlacesService] backing Explore's Nearby Places — into a stop
  /// for Create Trip's location picker, carrying name/coordinates,
  /// [category]/[types]/[businessStatus], and opening-hours data (both
  /// display strings and machine-readable [OpeningHoursPeriod]s) that
  /// Photon never had.
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

  /// True for a Google result that's just a geocoded address/administrative
  /// area (a street, a postal code, a locality boundary, ...) rather than
  /// an actual visitable place — e.g. searching "Komtar" can surface a
  /// bare `[premise, street_address]` result alongside the real Komtar
  /// tower. Useless for trip planning (no [businessStatus], no opening
  /// hours), so results like this should be filtered out of search
  /// results in favor of an actual POI/business/attraction. Always false
  /// for a Photon/OSM result ([types] is empty, not address-only).
  bool get isAddressOnly =>
      types.isNotEmpty && types.every(_addressOnlyTypes.contains);

  /// Same real-world place as [other]? Prefers Google's [placeId] when
  /// both sides have one (stable even if the coordinates drift slightly
  /// between two searches); falls back to coordinates + [osmId]
  /// otherwise — used to prevent adding the same stop twice.
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

/// Google Places type tags that describe a geocoded address/administrative
/// area rather than a visitable place — a result whose [TripStopLocation.types]
/// are *entirely* drawn from this set (see [TripStopLocation.isAddressOnly])
/// carries no [TripStopLocation.businessStatus] or opening hours and isn't
/// useful as a trip stop.
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
/// standalone function so callers with just the category string don't need
/// a [TripStopLocation] instance.
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
