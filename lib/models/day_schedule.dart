import 'trip_day.dart';
import 'trip_stop_location.dart';

/// One stop placed into a day's actual timeline — see [DaySchedule].
/// Everything here already passed the feasibility checks
/// [DayScheduleService] enforces: arrival at or before closing,
/// [visitStart] at or after opening, and [visitEnd] at or before
/// closing.
class ScheduledStop {
  const ScheduledStop({
    required this.stop,
    required this.travelMinutesFromPrevious,
    required this.arrival,
    required this.visitStart,
    required this.visitEnd,
  });

  final TripStopLocation stop;

  /// Driving minutes from whatever came right before this stop on the
  /// day's route — the day's start anchor, or the previous scheduled
  /// stop.
  final int travelMinutesFromPrevious;

  /// When travel actually lands here — may be earlier than [visitStart]
  /// if the traveler arrives before opening and has to wait.
  final DateTime arrival;

  final DateTime visitStart;
  final DateTime visitEnd;

  /// How long the traveler waits at [arrival] for the place to open, if
  /// at all.
  Duration get waitTime => visitStart.difference(arrival);
}

/// The feasible, timed schedule for one [TripDay] — built by
/// [DayScheduleService.scheduleDay].
class DaySchedule {
  const DaySchedule({
    required this.day,
    required this.scheduledStops,
    required this.unscheduledStops,
    required this.endArrival,
  });

  final TripDay day;

  /// In visit order, each with its actual arrival/visit-start/visit-end
  /// times.
  final List<ScheduledStop> scheduledStops;

  /// Candidates for this day that couldn't be fit into any stop order
  /// tried — not deleted, just not on this day's timeline (a "floating
  /// pool"). [DayScheduleService] doesn't retry these on a different
  /// day; that's a separate, larger pass than building one day's
  /// timeline.
  final List<TripStopLocation> unscheduledStops;

  /// When the day's route actually reaches [TripDay.endAnchor], after
  /// the last scheduled stop (or straight from the start anchor, if
  /// nothing was scheduled at all).
  final DateTime endArrival;
}
