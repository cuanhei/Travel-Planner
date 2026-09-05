import 'trip_stop_location.dart';

/// One calendar day of a trip's itinerary *skeleton* — the day's start
/// and end anchors, built from the trip's overall start/end point and
/// each night's accommodation, before any attraction is clustered or
/// scheduled onto it. See [buildTripDays].
///
/// For an N-day trip: day 1 starts at the overall trip start and ends at
/// night 1's hotel; day 2 starts at night 1's hotel and ends at night
/// 2's hotel; ...; the final day starts at the last night's hotel and
/// ends at the overall trip end. A single-day trip (no nights) simply
/// starts and ends at the overall start/end, with no hotel anchor at
/// all.
class TripDay {
  const TripDay({
    required this.dayNumber,
    required this.date,
    required this.startAnchor,
    required this.startIsOverallStart,
    required this.endAnchor,
    required this.endIsOverallEnd,
    this.scheduledStops = const [],
  });

  /// 1-indexed.
  final int dayNumber;
  final DateTime date;

  final TripStopLocation startAnchor;

  /// True when [startAnchor] is the trip's overall starting point (only
  /// ever day 1) rather than the hotel from the previous night.
  final bool startIsOverallStart;

  final TripStopLocation endAnchor;

  /// True when [endAnchor] is the trip's overall ending point (only ever
  /// the final day) rather than that night's hotel.
  final bool endIsOverallEnd;

  /// Attractions clustered and ordered onto this day — empty until
  /// scheduling runs; [buildTripDays] only produces the day skeleton
  /// (anchors), never the stops within it.
  final List<TripStopLocation> scheduledStops;
}
