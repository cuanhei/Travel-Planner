const Map<String, int> estimatedVisitDurationMinutes = {
  'amusement_park': 360,
  'water_park': 360,
  'wildlife_park': 300,
  'zoo': 240,
  'aquarium': 180,

  'museum': 120,
  'art_gallery': 90,
  'historical_landmark': 90,
  'historical_place': 90,
  'cultural_landmark': 90,
  'tourist_attraction': 120,
  'visitor_center': 60,

  'national_park': 240,
  'park': 120,
  'garden': 90,
  'beach': 180,
  'hiking_area': 180,

  'shopping_mall': 180,
  'market': 120,
  'store': 60,
  'gift_shop': 45,

  'restaurant': 90,
  'cafe': 60,
  'coffee_shop': 60,
  'food_court': 60,
  'bakery': 30,

  'hindu_temple': 60,
  'mosque': 60,
  'church': 60,
  'synagogue': 60,

  'movie_theater': 150,
  'performing_arts_theater': 150,
  'bowling_alley': 120,
  'casino': 180,
  'night_club': 180,

  'stadium': 120,
  'sports_complex': 120,
  'golf_course': 240,

  'observation_deck': 60,
  'monument': 45,
  'plaza': 60,
};

const defaultVisitDurationMinutes = 90;

int estimateVisitDuration(String? primaryType, List<String> types) {
  if (primaryType != null) {
    final duration = estimatedVisitDurationMinutes[primaryType];
    if (duration != null) return duration;
  }

  int? longest;
  for (final type in types) {
    final duration = estimatedVisitDurationMinutes[type];
    if (duration != null && (longest == null || duration > longest)) {
      longest = duration;
    }
  }
  return longest ?? defaultVisitDurationMinutes;
}
