import 'trip_stop_location.dart';

class UnscheduledStop {
  const UnscheduledStop({required this.stop, required this.reason});

  final TripStopLocation stop;

  final String reason;

  @override
  bool operator ==(Object other) =>
      other is UnscheduledStop && other.stop == stop;

  @override
  int get hashCode => stop.hashCode;
}
