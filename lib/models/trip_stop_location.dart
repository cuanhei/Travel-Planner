import 'package:flutter/material.dart';

import 'nearby_place.dart';
import 'opening_period.dart';

/// Why a stop was added to a trip — independent of [TripStopLocation.category]:
/// the same category='Hotel' stop can be [accommodation] (the overnight
/// stay) or [meal] (picked just for its buffet). Drives the scheduling
/// engine's day-assignment/anchor logic; category alone never does.
enum VisitPurpose {
  accommodation,
  meal,
  attraction,
  shopping,
  transport,
  other;

  /// Matches `trip_stops.visit_purpose`'s check constraint values.
  String get value => name;

  static VisitPurpose fromValue(String? value) => VisitPurpose.values
      .firstWhere((v) => v.value == value, orElse: () => VisitPurpose.other);

  /// Sensible starting guess from [category] — always user-adjustable
  /// afterward (e.g. a hotel picked for its dinner buffet should become
  /// [meal], not stay [accommodation]).
  static VisitPurpose forCategory(String category) => switch (category) {
    'Hotel' => VisitPurpose.accommodation,
    'Food' => VisitPurpose.meal,
    'Shopping' => VisitPurpose.shopping,
    'Transport' => VisitPurpose.transport,
    'Nature' || 'Beach' || 'Culture' => VisitPurpose.attraction,
    _ => VisitPurpose.other,
  };
}

/// Which meal a stop covers — only meaningful when
/// [TripStopLocation.visitPurpose] is [VisitPurpose.meal].
enum MealType {
  breakfast,
  lunch,
  dinner,
  snack;

  String get value => name;

  static MealType? fromValue(String? value) {
    for (final v in MealType.values) {
      if (v.value == value) return v;
    }
    return null;
  }
}

/// Whether a stop is sheltered from weather — only consulted by the
/// scheduling engine on trip days that actually have a weather forecast
/// (see `WeatherService.getForecastWindowForPosition`); irrelevant, and
/// never scored, on days with none.
enum EnvironmentType {
  indoor,
  outdoor,
  mixed;

  String get value => name;

  static EnvironmentType? fromValue(String? value) {
    for (final v in EnvironmentType.values) {
      if (v.value == value) return v;
    }
    return null;
  }

  /// Sensible starting guess from [category] — always user-adjustable.
  static EnvironmentType forCategory(String category) => switch (category) {
    'Nature' || 'Beach' => EnvironmentType.outdoor,
    'Culture' ||
    'Shopping' ||
    'Food' ||
    'Hotel' ||
    'Health' ||
    'Finance' => EnvironmentType.indoor,
    _ => EnvironmentType.mixed,
  };
}

/// Default visit-length guess per [TripStopLocation.category], in
/// minutes — mirrors the spec's category defaults (spec §9); always
/// user-adjustable per stop afterward.
const _defaultVisitDurationMinutes = {
  'Shopping': 120,
  'Food': 75,
  'Hotel': 60,
  'Nature': 120,
  'Beach': 120,
  'Culture': 90,
  'Transport': 30,
  'Health': 45,
  'Finance': 20,
  'Other': 60,
};

int _defaultVisitDurationFor(String category) =>
    _defaultVisitDurationMinutes[category] ?? 60;

/// A real, geocoded location picked for a trip stop — via Photon search,
/// Google Places search (Create Trip's stop picker), a manual tap on the
/// map, or the user's current GPS position. Distinct from
/// `trip_data.dart`'s `TripStop` (a scheduled itinerary entry with a
/// day/time) and from Explore's `Place` (curated attraction content) —
/// this is the raw place data needed to plot and re-find it later, and
/// (once [visitPurpose]/[estimatedVisitDurationMinutes]/[openingPeriods]
/// are set) the canonical input to the trip-scheduling engine.
class TripStopLocation {
  TripStopLocation({
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
    this.placeId,
    this.rating,
    this.userRatingCount,
    this.businessStatus,
    this.openingPeriods,
    VisitPurpose? visitPurpose,
    this.mealType,
    EnvironmentType? environmentType,
    int? estimatedVisitDurationMinutes,
  }) : visitPurpose = visitPurpose ?? VisitPurpose.forCategory(category),
       environmentType =
           environmentType ?? EnvironmentType.forCategory(category),
       estimatedVisitDurationMinutes =
           estimatedVisitDurationMinutes ?? _defaultVisitDurationFor(category);

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

  /// Google's Place id — lets a saved stop's hours/status be refreshed
  /// later, and (unlike the `(lat,lng,osmId)` equality below, which two
  /// distinct Google-sourced places at the same coordinates would both
  /// satisfy) is the real dedup key for Google-sourced stops.
  final String? placeId;

  /// Google's 1.0–5.0 average rating, or null.
  final double? rating;
  final int? userRatingCount;

  /// Google's `businessStatus` (e.g. `OPERATIONAL`, `CLOSED_TEMPORARILY`,
  /// `CLOSED_PERMANENTLY`) at the time this stop was added.
  final String? businessStatus;

  /// Structured, machine-checkable open/close windows (see
  /// [OpeningPeriod]) — the scheduling engine's actual validation input,
  /// as opposed to [openingHours]'s display strings. Preferring
  /// `currentOpeningHours`' periods over `regularOpeningHours`' at the
  /// point a stop is added (see [fromNearbyPlace]) — same preference as
  /// [openingHours] — since this is a point-in-time snapshot, not a
  /// live-synced value.
  final List<OpeningPeriod>? openingPeriods;

  /// Why this stop was added — see [VisitPurpose]. Always set (defaults
  /// from [category] via [VisitPurpose.forCategory] if not given
  /// explicitly), and always user-adjustable afterward.
  final VisitPurpose visitPurpose;

  /// Set only when [visitPurpose] is [VisitPurpose.meal].
  final MealType? mealType;

  /// See [EnvironmentType]. Always set (category-defaulted), consulted
  /// by the scheduling engine only on weather-aware trip days.
  final EnvironmentType environmentType;

  /// How long a visit here is expected to take, in minutes — a
  /// category-keyed default (see [_defaultVisitDurationFor]) unless the
  /// traveler adjusts it.
  final int estimatedVisitDurationMinutes;

  /// Icon representing [category], for chips, list tiles, and cards.
  IconData get categoryIcon => iconForCategory(category);

  /// Overrides [visitPurpose]/[mealType] (and optionally
  /// [estimatedVisitDurationMinutes]) on an otherwise-unchanged copy —
  /// used to tag a raw Google Places search result (e.g. a restaurant
  /// found for spec §10's meal planning, or a hotel found for spec §4's
  /// "Recommend accommodation") with the specific role it's being
  /// scheduled for, since [fromNearbyPlace] only ever infers a generic
  /// default from [category].
  TripStopLocation copyWith({
    String? id,
    VisitPurpose? visitPurpose,
    MealType? mealType,
    int? estimatedVisitDurationMinutes,
  }) {
    return TripStopLocation(
      id: id ?? this.id,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      osmId: osmId,
      category: category,
      regularOpeningHours: regularOpeningHours,
      currentOpeningHours: currentOpeningHours,
      openNow: openNow,
      placeId: placeId,
      rating: rating,
      userRatingCount: userRatingCount,
      businessStatus: businessStatus,
      openingPeriods: openingPeriods,
      visitPurpose: visitPurpose ?? this.visitPurpose,
      mealType: mealType ?? this.mealType,
      environmentType: environmentType,
      estimatedVisitDurationMinutes:
          estimatedVisitDurationMinutes ?? this.estimatedVisitDurationMinutes,
    );
  }

  factory TripStopLocation.fromMap(Map<String, dynamic> map) {
    final category = (map['category'] as String?) ?? 'Other';
    final periodsJson = map['opening_periods'] as List?;
    return TripStopLocation(
      id: map['id'] as String,
      name: map['name'] as String,
      address: map['address'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      osmId: map['osm_id'] as String?,
      category: category,
      placeId: map['place_id'] as String?,
      rating: (map['rating'] as num?)?.toDouble(),
      userRatingCount: map['user_rating_count'] as int?,
      businessStatus: map['business_status'] as String?,
      openingPeriods: periodsJson == null
          ? null
          : [
              for (final p in periodsJson)
                OpeningPeriod.fromJson(p as Map<String, dynamic>),
            ],
      visitPurpose: VisitPurpose.fromValue(map['visit_purpose'] as String?),
      mealType: MealType.fromValue(map['meal_type'] as String?),
      environmentType: EnvironmentType.fromValue(
        map['environment_type'] as String?,
      ),
      estimatedVisitDurationMinutes:
          map['estimated_visit_duration_minutes'] as int? ??
          _defaultVisitDurationFor(category),
    );
  }

  /// The subset of fields `TripService.addStops` inserts into
  /// `trip_stops` — deliberately excludes [id]/[regularOpeningHours]/
  /// [currentOpeningHours]/[openNow] (the display-string hours aren't
  /// stored; only [openingPeriods], the structured form, is).
  Map<String, dynamic> toInsertMap(String tripId) => {
    'trip_id': tripId,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
    'osm_id': osmId,
    'category': category,
    'place_id': placeId,
    'visit_purpose': visitPurpose.value,
    'meal_type': mealType?.value,
    'environment_type': environmentType.value,
    'estimated_visit_duration_minutes': estimatedVisitDurationMinutes,
    'rating': rating,
    'user_rating_count': userRatingCount,
    'business_status': businessStatus,
    'opening_periods': openingPeriods?.map((p) => p.toJson()).toList(),
  };

  /// Converts a Google Places API (New) result — from the same
  /// [GooglePlacesService] backing Explore's Nearby Places — into a stop
  /// for Create Trip's location picker, carrying name/coordinates plus
  /// [category] (mapped from Google's `primaryType`) and every
  /// scheduling-relevant field Photon never had.
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
      placeId: place.id,
      rating: place.rating,
      userRatingCount: place.userRatingCount,
      businessStatus: place.businessStatus,
      openingPeriods: place.openingPeriods,
    );
  }

  String get _identity => id != null
      ? 'visit:$id'
      : placeId != null
      ? 'place:$placeId'
      : osmId != null
      ? 'osm:$osmId'
      : '${name.trim().toLowerCase()}:$latitude,$longitude';

  @override
  bool operator ==(Object other) =>
      other is TripStopLocation && other._identity == _identity;

  @override
  int get hashCode => _identity.hashCode;
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
