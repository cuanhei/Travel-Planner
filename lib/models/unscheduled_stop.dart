import 'trip_stop_location.dart';

/// A candidate that didn't end up on a day's timeline, plus why — see
/// `DaySchedule.unscheduledStops`. Never deleted outright; kept so the
/// traveler (or a later gap-filling/retry pass) can see exactly what was
/// tried and why it didn't fit, rather than silently vanishing.
class UnscheduledStop {
  const UnscheduledStop({required this.stop, required this.reason});

  final TripStopLocation stop;

  /// Human-readable explanation — e.g. "Closed on this day", "Arrives
  /// after closing", "Outdoor stop conflicts with forecast weather".
  final String reason;

  /// Identity is by [stop] alone (ignoring [reason]) — lets a
  /// cross-day/cross-stage pass ask "was this stop already unscheduled
  /// before, regardless of the reason text" via plain list/set
  /// membership.
  @override
  bool operator ==(Object other) =>
      other is UnscheduledStop && other.stop == stop;

  @override
  int get hashCode => stop.hashCode;
}
