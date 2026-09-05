/// Whether a place is spent mostly indoors, outdoors, both, or unknown
/// — used for weather-aware scheduling (e.g. steering an itinerary away
/// from an outdoor stop on a rain-forecast day).
enum PlaceEnvironment { indoor, outdoor, mixed, unknown }

/// Google Places type → [PlaceEnvironment], the same keys as
/// [estimatedVisitDurationMinutes] (see `visit_duration.dart`) but a
/// separate map since a type's typical visit length and its indoor/
/// outdoor nature are independent facts about it.
const Map<String, PlaceEnvironment> placeEnvironmentMap = {
  // Theme parks / attractions
  'amusement_park': PlaceEnvironment.mixed,
  'water_park': PlaceEnvironment.outdoor,
  'wildlife_park': PlaceEnvironment.outdoor,
  'zoo': PlaceEnvironment.outdoor,
  'aquarium': PlaceEnvironment.indoor,
  'tourist_attraction': PlaceEnvironment.unknown,

  // Culture
  'museum': PlaceEnvironment.indoor,
  'art_gallery': PlaceEnvironment.indoor,
  'historical_landmark': PlaceEnvironment.outdoor,
  'historical_place': PlaceEnvironment.mixed,
  'cultural_landmark': PlaceEnvironment.mixed,
  'visitor_center': PlaceEnvironment.indoor,

  // Nature
  'national_park': PlaceEnvironment.outdoor,
  'park': PlaceEnvironment.outdoor,
  'garden': PlaceEnvironment.outdoor,
  'beach': PlaceEnvironment.outdoor,
  'hiking_area': PlaceEnvironment.outdoor,

  // Shopping
  'shopping_mall': PlaceEnvironment.indoor,
  'market': PlaceEnvironment.mixed,
  'store': PlaceEnvironment.indoor,
  'gift_shop': PlaceEnvironment.indoor,

  // Food
  'restaurant': PlaceEnvironment.indoor,
  'cafe': PlaceEnvironment.indoor,
  'coffee_shop': PlaceEnvironment.indoor,
  'food_court': PlaceEnvironment.indoor,
  'bakery': PlaceEnvironment.indoor,

  // Religious
  'hindu_temple': PlaceEnvironment.mixed,
  'mosque': PlaceEnvironment.indoor,
  'church': PlaceEnvironment.indoor,
  'synagogue': PlaceEnvironment.indoor,

  // Entertainment
  'movie_theater': PlaceEnvironment.indoor,
  'performing_arts_theater': PlaceEnvironment.indoor,
  'bowling_alley': PlaceEnvironment.indoor,
  'casino': PlaceEnvironment.indoor,
  'night_club': PlaceEnvironment.indoor,

  // Sports
  'stadium': PlaceEnvironment.mixed,
  'sports_complex': PlaceEnvironment.mixed,
  'golf_course': PlaceEnvironment.outdoor,

  // Other
  'observation_deck': PlaceEnvironment.mixed,
  'monument': PlaceEnvironment.outdoor,
  'plaza': PlaceEnvironment.outdoor,
};

/// [PlaceEnvironment] for a place, preferring [primaryType] (Google's
/// single best classification) and falling back to the first entry in
/// [types] that [placeEnvironmentMap] recognizes. [PlaceEnvironment.unknown]
/// when neither resolves — always true for a Photon/OSM stop, which
/// carries no Google type data at all.
PlaceEnvironment getEnvironment(String? primaryType, List<String> types) {
  if (primaryType != null && placeEnvironmentMap.containsKey(primaryType)) {
    return placeEnvironmentMap[primaryType]!;
  }

  for (final type in types) {
    if (placeEnvironmentMap.containsKey(type)) {
      return placeEnvironmentMap[type]!;
    }
  }

  return PlaceEnvironment.unknown;
}
