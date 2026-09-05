/// Rough time (in minutes) a traveler spends at a place, keyed by Google
/// Places type — used to estimate how many stops reasonably fit in a
/// day and to pad travel-time gaps between them. Deliberately coarse;
/// how long any one traveler actually spends varies a lot.
const Map<String, int> estimatedVisitDurationMinutes = {
  // Theme parks / major attractions
  'amusement_park': 360, // 6h
  'water_park': 360, // 6h
  'wildlife_park': 300, // 5h
  'zoo': 240, // 4h
  'aquarium': 180, // 3h

  // Culture / sightseeing
  'museum': 120, // 2h
  'art_gallery': 90, // 1.5h
  'historical_landmark': 90, // 1.5h
  'historical_place': 90,
  'cultural_landmark': 90,
  'tourist_attraction': 120, // 2h
  'visitor_center': 60,

  // Nature
  'national_park': 240, // 4h
  'park': 120, // 2h
  'garden': 90,
  'beach': 180, // 3h
  'hiking_area': 180,

  // Shopping
  'shopping_mall': 180, // 3h
  'market': 120,
  'store': 60,
  'gift_shop': 45,

  // Food
  'restaurant': 90, // 1.5h
  'cafe': 60,
  'coffee_shop': 60,
  'food_court': 60,
  'bakery': 30,

  // Religious places
  'hindu_temple': 60,
  'mosque': 60,
  'church': 60,
  'synagogue': 60,

  // Entertainment
  'movie_theater': 150,
  'performing_arts_theater': 150,
  'bowling_alley': 120,
  'casino': 180,
  'night_club': 180,

  // Sports
  'stadium': 120,
  'sports_complex': 120,
  'golf_course': 240,

  // General
  'observation_deck': 60,
  'monument': 45,
  'plaza': 60,
};

/// Default when neither [primaryType] nor anything in [types] matches
/// [estimatedVisitDurationMinutes] — a generic "quick stop" guess.
/// Always the result for a Photon/OSM stop, which carries no Google type
/// data at all.
const defaultVisitDurationMinutes = 90;

/// Estimated minutes a traveler spends at a place. Prefers [primaryType]
/// (Google's single best classification for the place) since [types]
/// often mixes several tags of very different scale — e.g. Sunway
/// Lagoon carries `wildlife_park`, `water_park`, `amusement_park`,
/// `park`, `zoo`, and `tourist_attraction` all at once. Blindly taking
/// the first of those that matches [estimatedVisitDurationMinutes] could
/// land on `park` (120 min) purely because of list order, badly
/// underestimating an all-day theme park. So when [primaryType] doesn't
/// resolve it, the fallback instead takes the *longest* estimate among
/// every matching entry in [types] — the place's most immersive facet
/// should dominate the estimate, not whichever tag happened to sort
/// first.
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
