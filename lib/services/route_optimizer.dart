import 'package:latlong2/latlong.dart';

import '../models/trip_stop_location.dart';

const Distance _distance = Distance();

/// Orders [stops] into a travel route using a nearest-neighbor heuristic:
/// starting at [start], repeatedly jump to whichever remaining stop is
/// closest (straight-line distance), until every stop is visited. Not a
/// true shortest-route solver (that's an NP-hard problem — exact for a
/// handful of stops, but this app's stop counts don't warrant it), but a
/// standard, cheap approximation that avoids obviously backtracking paths.
///
/// If [end] is given, the last leg from the final stop to it is not
/// factored into the ordering itself (nearest-neighbor is greedy stop by
/// stop) — [end] is purely the route's destination for callers to draw as
/// the final leg.
List<TripStopLocation> optimizeRoute({
  required LatLng start,
  required List<TripStopLocation> stops,
  LatLng? end,
}) {
  if (stops.length <= 1) return List.of(stops);

  final remaining = List<TripStopLocation>.of(stops);
  final ordered = <TripStopLocation>[];
  var current = start;

  while (remaining.isNotEmpty) {
    var nearestIndex = 0;
    var nearestDistance = double.infinity;
    for (var i = 0; i < remaining.length; i++) {
      final candidate = remaining[i];
      final d = _distance(
        current,
        LatLng(candidate.latitude, candidate.longitude),
      );
      if (d < nearestDistance) {
        nearestDistance = d;
        nearestIndex = i;
      }
    }
    final next = remaining.removeAt(nearestIndex);
    ordered.add(next);
    current = LatLng(next.latitude, next.longitude);
  }

  return ordered;
}

/// Total route length in kilometers: start → each stop in order → end (if
/// given). Useful for showing a "~42 km route" summary alongside the map.
double routeDistanceKm({
  required LatLng start,
  required List<TripStopLocation> orderedStops,
  LatLng? end,
}) {
  if (orderedStops.isEmpty) {
    return end == null ? 0 : _distance(start, end) / 1000;
  }
  var total = 0.0;
  var current = start;
  for (final stop in orderedStops) {
    final point = LatLng(stop.latitude, stop.longitude);
    total += _distance(current, point);
    current = point;
  }
  if (end != null) total += _distance(current, end);
  return total / 1000;
}

/// Rounds to a friendly precision for display, e.g. 42.3 km or 3.7 km.
double roundKm(double km) => (km * 10).roundToDouble() / 10;

/// One day's plan: a base hotel (when any hotel stop exists) and that
/// day's other stops, already ordered to start from the hotel.
class DayPlan {
  const DayPlan({required this.day, required this.hotel, required this.stops});

  /// 1-based day number.
  final int day;

  /// The hotel this day is based out of — null only when the trip has no
  /// hotel stop at all, in which case there's nothing to anchor days to.
  final TripStopLocation? hotel;

  /// This day's non-hotel stops, nearest-neighbor ordered starting from
  /// [hotel].
  final List<TripStopLocation> stops;
}

/// Splits [stops] across [dayCount] days, each based out of a hotel:
///
/// - Every day gets a hotel from among [stops]' `category == 'Hotel'`
///   entries. With as many (or more) hotels as days, each day gets a
///   different one; with fewer hotels than days, hotels repeat (e.g. one
///   hotel for a 3-day trip means all 3 days use that same hotel).
/// - Every other stop is assigned to whichever day's hotel it's closest
///   to (straight-line distance) — so a day's plan always stays near
///   that day's base — then ordered within the day via [optimizeRoute]
///   starting from the hotel.
///
/// If the trip has no hotel stop, stops are still sequenced into the
/// requested number of days. This preserves the trip's date range in the
/// schedule UI instead of collapsing a multi-day trip to a single tab.
List<DayPlan> planDays({
  required int dayCount,
  required List<TripStopLocation> stops,
}) {
  final hotels = stops.where((s) => s.category == 'Hotel').toList();

  if (hotels.isEmpty) {
    final days = dayCount < 1 ? 1 : dayCount;
    if (stops.isEmpty) {
      return List.generate(
        days,
        (index) => DayPlan(day: index + 1, hotel: null, stops: const []),
      );
    }
    final first = stops.first;
    final ordered = [
      first,
      ...optimizeRoute(
        start: LatLng(first.latitude, first.longitude),
        stops: stops.skip(1).toList(),
      ),
    ];
    // Slice the already-optimized path into contiguous, evenly-sized
    // chunks — one per day. Splitting by index % days would interleave
    // the route instead (day 1 getting stops 0, 3, 6, ...), destroying
    // the geographic ordering optimizeRoute just computed.
    final chunkSize = (ordered.length / days).ceil();
    return List.generate(days, (index) {
      final from = (index * chunkSize).clamp(0, ordered.length);
      final to = ((index + 1) * chunkSize).clamp(0, ordered.length);
      return DayPlan(day: index + 1, hotel: null, stops: ordered.sublist(from, to));
    });
  }

  final days = dayCount < 1 ? 1 : dayCount;
  final dayHotels = List.generate(days, (i) => hotels[i % hotels.length]);

  // Hotels beyond what's needed as a distinct day anchor (more hotels
  // than days) still need to appear somewhere — cluster them like any
  // other stop rather than dropping them.
  final consumed = hotels.length <= days ? hotels.length : days;
  final pool = [
    ...stops.where((s) => s.category != 'Hotel'),
    ...hotels.skip(consumed),
  ];

  final buckets = List.generate(days, (_) => <TripStopLocation>[]);
  for (final stop in pool) {
    final point = LatLng(stop.latitude, stop.longitude);
    var bestDay = 0;
    var bestDistance = double.infinity;
    for (var d = 0; d < days; d++) {
      final hotel = dayHotels[d];
      final dist = _distance(point, LatLng(hotel.latitude, hotel.longitude));
      if (dist < bestDistance) {
        bestDistance = dist;
        bestDay = d;
      }
    }
    buckets[bestDay].add(stop);
  }

  return List.generate(days, (d) {
    final hotel = dayHotels[d];
    final ordered = optimizeRoute(
      start: LatLng(hotel.latitude, hotel.longitude),
      stops: buckets[d],
    );
    return DayPlan(day: d + 1, hotel: hotel, stops: ordered);
  });
}
