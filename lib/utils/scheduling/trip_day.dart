import '../../models/trip_stop_location.dart';
import '../../models/weather_forecast.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// One calendar day of a trip's schedule — the unit the scheduling
/// engine assigns stops to (spec §3). Built once per scheduling run by
/// [buildTripDays], then filled in by `day_assignment.dart` and ordered
/// by `day_ordering.dart`.
class TripDay {
  TripDay({
    required this.date,
    required this.dailyStart,
    required this.dailyEnd,
    this.startAnchor,
    this.endAnchor,
    this.recommendationOrigin,
    this.weatherAvailable = false,
    this.weatherForecast,
    List<TripStopLocation>? assignedStops,
  }) : assignedStops = assignedStops ?? [];

  final DateTime date;

  /// The traveler's daily start/end time (spec §2.1), applied to
  /// [date] — the *same* window every day of the trip; check-in/
  /// check-out constraints live in [startAnchor]/[endAnchor] instead,
  /// not here.
  final DateTime dailyStart;
  final DateTime dailyEnd;

  /// Where the day starts/ends — the trip's own start/end location on
  /// the first/last day, or the previous/next night's accommodation
  /// stop otherwise (spec §16). Null means no fixed constraint that
  /// side of the day — a hotel isn't mandatory for the optimizer to
  /// work (spec §17).
  final TripStopLocation? startAnchor;
  final TripStopLocation? endAnchor;

  /// Explicit fallback for days without a hotel. Kept separate so the UI can
  /// describe it as an assumed starting point rather than a booked stay.
  final TripStopLocation? recommendationOrigin;
  TripStopLocation? get routeOrigin =>
      startAnchor ?? endAnchor ?? recommendationOrigin;

  TripDay copyWithStops(Iterable<TripStopLocation> stops) => TripDay(
    date: date,
    dailyStart: dailyStart,
    dailyEnd: dailyEnd,
    startAnchor: startAnchor,
    endAnchor: endAnchor,
    recommendationOrigin: recommendationOrigin,
    weatherAvailable: weatherAvailable,
    weatherForecast: weatherForecast,
    assignedStops: stops.toList(),
  );

  /// Whether a weather forecast exists for [date] — see spec §12: this
  /// is checked per trip day, never assumed for a day outside the
  /// forecast window.
  final bool weatherAvailable;
  final WeatherForecast? weatherForecast;

  /// Stops assigned to this day — insertion order until
  /// `day_ordering.dart` has run, visiting order afterward. Mutated in
  /// place by the scheduling engine (a plain field, not `final`-list-
  /// then-copy, since day assignment/ordering both need to add/reorder
  /// stops on an already-built [TripDay] rather than rebuilding it).
  final List<TripStopLocation> assignedStops;

  Duration get availableDuration => dailyEnd.difference(dailyStart);

  @override
  String toString() =>
      'TripDay(${date.toIso8601String().split('T').first}, '
      '${assignedStops.length} stops)';
}

/// Enumerates every date from [startDate] to [endDate] (inclusive) into
/// a [TripDay], chaining accommodation anchors per spec §16: day N
/// starts where night N-1's accommodation was (or [tripStartLocation]
/// on the first day) and ends at night N's accommodation (or
/// [tripEndLocation] on the last day). [accommodationByNight] may be
/// empty or partial — every anchor field then stays null for the
/// corresponding day/side, and the rest of the engine must still work
/// (spec §17: accommodation is never mandatory).
///
/// [dailyStartTime]/[dailyEndTime] default to 09:00/18:00 (this app's
/// own Create Trip form default) when a trip predates these columns.
List<TripDay> buildTripDays({
  required DateTime startDate,
  required DateTime endDate,
  ({int hour, int minute})? dailyStartTime,
  ({int hour, int minute})? dailyEndTime,
  Map<DateTime, TripStopLocation> accommodationByNight = const {},
  TripStopLocation? tripStartLocation,
  TripStopLocation? tripEndLocation,
  Map<DateTime, WeatherForecast> weatherByDate = const {},
}) {
  final start = _dateOnly(startDate);
  final end = _dateOnly(endDate);
  if (end.isBefore(start)) return const [];

  final startTime = dailyStartTime ?? (hour: 9, minute: 0);
  final endTime = dailyEndTime ?? (hour: 18, minute: 0);

  final days = <TripDay>[];
  var date = start;
  while (!date.isAfter(end)) {
    final isFirstDay = date.isAtSameMomentAs(start);
    final isLastDay = date.isAtSameMomentAs(end);
    final previousNight = _dateOnly(date.subtract(const Duration(days: 1)));

    days.add(
      TripDay(
        date: date,
        dailyStart: DateTime(
          date.year,
          date.month,
          date.day,
          startTime.hour,
          startTime.minute,
        ),
        dailyEnd: DateTime(
          date.year,
          date.month,
          date.day,
          endTime.hour,
          endTime.minute,
        ),
        startAnchor: isFirstDay
            ? tripStartLocation
            : accommodationByNight[previousNight],
        endAnchor: isLastDay ? tripEndLocation : accommodationByNight[date],
        recommendationOrigin: tripStartLocation ?? tripEndLocation,
        weatherAvailable: weatherByDate.containsKey(date),
        weatherForecast: weatherByDate[date],
      ),
    );
    date = date.add(const Duration(days: 1));
  }
  return days;
}
