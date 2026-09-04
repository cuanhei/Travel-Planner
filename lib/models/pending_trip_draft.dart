import 'package:flutter/material.dart';

import 'trip_stop_location.dart';

/// Everything Create Trip has collected but not yet written to the
/// database — carried to [OptimizedItineraryScreen] (see that file) so
/// the trip is only actually created once the traveler reviews the
/// generated itinerary and taps its own "Save Trip" button, not the
/// moment "Plan My Trip" is tapped.
class PendingTripDraft {
  const PendingTripDraft({
    required this.startLocation,
    required this.endLocation,
    required this.accommodations,
    required this.dateRange,
    required this.startTime,
    required this.endTime,
    required this.totalBudget,
  });

  final TripStopLocation? startLocation;
  final TripStopLocation? endLocation;

  /// One per night of the trip, in order — already validated non-null
  /// for every required night by Create Trip before this draft exists.
  final List<TripStopLocation> accommodations;

  final DateTimeRange? dateRange;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final double totalBudget;
}
