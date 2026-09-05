enum PlaceEnvironment { indoor, outdoor, mixed, unknown }

const Map<String, PlaceEnvironment> placeEnvironmentMap = {
  'amusement_park': PlaceEnvironment.mixed,
  'water_park': PlaceEnvironment.outdoor,
  'wildlife_park': PlaceEnvironment.outdoor,
  'zoo': PlaceEnvironment.outdoor,
  'aquarium': PlaceEnvironment.indoor,
  'tourist_attraction': PlaceEnvironment.unknown,

  'museum': PlaceEnvironment.indoor,
  'art_gallery': PlaceEnvironment.indoor,
  'historical_landmark': PlaceEnvironment.outdoor,
  'historical_place': PlaceEnvironment.mixed,
  'cultural_landmark': PlaceEnvironment.mixed,
  'visitor_center': PlaceEnvironment.indoor,

  'national_park': PlaceEnvironment.outdoor,
  'park': PlaceEnvironment.outdoor,
  'garden': PlaceEnvironment.outdoor,
  'beach': PlaceEnvironment.outdoor,
  'hiking_area': PlaceEnvironment.outdoor,

  'shopping_mall': PlaceEnvironment.indoor,
  'market': PlaceEnvironment.mixed,
  'store': PlaceEnvironment.indoor,
  'gift_shop': PlaceEnvironment.indoor,

  'restaurant': PlaceEnvironment.indoor,
  'cafe': PlaceEnvironment.indoor,
  'coffee_shop': PlaceEnvironment.indoor,
  'food_court': PlaceEnvironment.indoor,
  'bakery': PlaceEnvironment.indoor,

  'hindu_temple': PlaceEnvironment.mixed,
  'mosque': PlaceEnvironment.indoor,
  'church': PlaceEnvironment.indoor,
  'synagogue': PlaceEnvironment.indoor,

  'movie_theater': PlaceEnvironment.indoor,
  'performing_arts_theater': PlaceEnvironment.indoor,
  'bowling_alley': PlaceEnvironment.indoor,
  'casino': PlaceEnvironment.indoor,
  'night_club': PlaceEnvironment.indoor,

  'stadium': PlaceEnvironment.mixed,
  'sports_complex': PlaceEnvironment.mixed,
  'golf_course': PlaceEnvironment.outdoor,

  'observation_deck': PlaceEnvironment.mixed,
  'monument': PlaceEnvironment.outdoor,
  'plaza': PlaceEnvironment.outdoor,
};

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
