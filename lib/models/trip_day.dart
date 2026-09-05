import 'trip_stop_location.dart';

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

  final int dayNumber;
  final DateTime date;

  final TripStopLocation startAnchor;

  final bool startIsOverallStart;

  final TripStopLocation endAnchor;

  final bool endIsOverallEnd;

  final List<TripStopLocation> scheduledStops;
}
