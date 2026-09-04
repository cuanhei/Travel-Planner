import 'trip_stop_location.dart';

/// Everything Create Trip collects, before any of it touches the
/// database — handed straight to `AiPlannerScreen`, which is the one
/// that actually creates the trip row (and everything under it) once
/// generation succeeds. Planning and automatic meal/accommodation searches
/// happen in memory. The complete trip is then inserted in one transaction.
class TripDraft {
  const TripDraft({
    required this.name,
    required this.description,
    required this.destination,
    required this.startCity,
    required this.endCity,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.totalBudget,
    required this.autoRecommend,
    required this.transportMode,
    required this.accommodationMode,
    required this.selectedStops,
    required this.selectedInterests,
    required this.accommodationByNight,
    required this.startLocation,
    required this.endLocation,
  });

  final String name;
  final String description;
  final String? destination;
  final String? startCity;
  final String? endCity;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Postgres `time` literals (`"HH:mm:ss"`), matching what
  /// `TripService.createTrip` already expects.
  final String startTime;
  final String endTime;

  final double totalBudget;
  final bool autoRecommend;
  final String transportMode;

  /// Matches `trips.accommodation_mode`'s check constraint: 'add_mine' /
  /// 'recommend' / 'skip'.
  final String accommodationMode;

  final Set<TripStopLocation> selectedStops;
  final Set<String> selectedInterests;

  /// Only populated when [accommodationMode] is 'add_mine' — see
  /// `CreateTripScreen`'s own doc comment on the field this came from.
  final Map<DateTime, TripStopLocation> accommodationByNight;

  final TripStopLocation? startLocation;
  final TripStopLocation? endLocation;
}
