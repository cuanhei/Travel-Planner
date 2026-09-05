import 'trip_day.dart';
import 'trip_stop_location.dart';
import 'unscheduled_stop.dart';

class ScheduledStop {
  const ScheduledStop({
    required this.stop,
    required this.travelMinutesFromPrevious,
    required this.arrival,
    required this.visitStart,
    required this.visitEnd,
    this.hasWeatherConcern = false,
  });

  final TripStopLocation stop;

  final int travelMinutesFromPrevious;

  final DateTime arrival;

  final DateTime visitStart;
  final DateTime visitEnd;

  final bool hasWeatherConcern;

  Duration get waitTime => visitStart.difference(arrival);
}

class DaySchedule {
  const DaySchedule({
    required this.day,
    required this.scheduledStops,
    required this.unscheduledStops,
    required this.endArrival,
  });

  final TripDay day;

  final List<ScheduledStop> scheduledStops;

  final List<UnscheduledStop> unscheduledStops;

  final DateTime endArrival;
}
