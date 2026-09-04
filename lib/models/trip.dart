const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatShortDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

/// Where a trip sits relative to today, used to bucket the "My Trips"
/// list into Current / Upcoming / Past sections.
enum TripStatus { current, upcoming, past }

/// A trip owned (or joined) by the signed-in user, backed by `trips`.
/// [startDate]/[endDate] are nullable — a trip created without dates yet
/// (e.g. the auto-seeded demo trip) is treated as [TripStatus.upcoming].
class Trip {
  const Trip({
    required this.id,
    required this.name,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.totalBudget,
    required this.createdBy,
    required this.createdAt,
    this.startCity,
    this.endCity,
    this.startTime,
    this.endTime,
    this.transportMode,
    this.startLocationStopId,
    this.endLocationStopId,
    this.autoRecommend = true,
    this.scheduleRevision = 0,
  });

  final String id;
  final String name;
  final String destination;
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalBudget;
  final String createdBy;
  final DateTime createdAt;
  final String? startCity;
  final String? endCity;

  /// `trips.transport_mode`'s raw value ('walk' / 'drive' /
  /// 'public_transport' / 'mixed', or null for a trip that predates this
  /// column or never set it) — kept as the raw DB string here rather
  /// than the scheduling engine's `TravelMode` enum, same layering as
  /// [startCity]/[endCity]; see `TravelMode.fromDbValue` in
  /// `lib/utils/scheduling/travel_matrix.dart` for the parsed form the
  /// scheduler actually consumes.
  final String? transportMode;

  /// The traveler's daily start/end time (spec §2.1's "Daily Start
  /// Time"/"Daily End Time") — the same window every day of the trip,
  /// not just check-in/check-out on the first/last day (those are
  /// governed by accommodation anchors instead — see
  /// `lib/utils/scheduling/trip_day.dart`). Written by
  /// `TripService.createTrip` since Create Trip always collects both,
  /// but was never round-tripped back out of `trips` until the
  /// scheduling engine needed it — null only for a trip row saved
  /// before these columns existed.
  final ({int hour, int minute})? startTime;
  final ({int hour, int minute})? endTime;

  /// `trips.start_location_stop_id`/`end_location_stop_id` — the real,
  /// geocoded Starting-From/Ending-At place (spec §2.1/§16) saved as its
  /// own `trip_stops` row (see `CreateTripScreen._saveTripLocations`),
  /// not just the display-string [startCity]/[endCity]. Null when not
  /// set (predates this column, or the traveler's trip has no fixed
  /// start/end point). The scheduling engine resolves these ids against
  /// its already-fetched stop list rather than a separate query — see
  /// `TripSchedulerService.run`.
  final String? startLocationStopId;
  final String? endLocationStopId;

  /// `trips.auto_recommend` — Create Trip's "Auto-recommend more places"
  /// toggle. Was write-only until spec §36-47's nearby-recommendation
  /// pass existed to actually consult it (see `ai_planner_screen.dart`);
  /// defaults to the same `true` the DB column defaults to.
  final bool autoRecommend;
  final int scheduleRevision;

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      id: map['id'] as String,
      name: map['name'] as String,
      destination: (map['destination'] as String?) ?? '',
      startDate: map['start_date'] != null
          ? DateTime.parse(map['start_date'] as String)
          : null,
      endDate: map['end_date'] != null
          ? DateTime.parse(map['end_date'] as String)
          : null,
      totalBudget: (map['total_budget'] as num).toDouble(),
      createdBy: map['created_by'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      startCity: map['start_city'] as String?,
      endCity: map['end_city'] as String?,
      startTime: _parseTime(map['start_time']),
      endTime: _parseTime(map['end_time']),
      transportMode: map['transport_mode'] as String?,
      startLocationStopId: map['start_location_stop_id'] as String?,
      endLocationStopId: map['end_location_stop_id'] as String?,
      autoRecommend: map['auto_recommend'] as bool? ?? true,
      scheduleRevision: map['schedule_revision'] as int? ?? 0,
    );
  }

  /// Brief "Start → End" route (city names only, no state) — e.g.
  /// "George Town → Kuala Lumpur", collapsed to just "George Town" when
  /// both ends are the same city. Falls back to [destination], then null
  /// if neither city nor destination is set.
  String? get routeLabel {
    final start = startCity?.trim();
    final end = endCity?.trim();
    final hasStart = start != null && start.isNotEmpty;
    final hasEnd = end != null && end.isNotEmpty;
    if (hasStart && hasEnd) {
      return start == end ? start : '$start → $end';
    }
    if (hasStart) return start;
    if (hasEnd) return end;
    return destination.isEmpty ? null : destination;
  }

  TripStatus get status {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return TripStatus.upcoming;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (todayDate.isBefore(start)) return TripStatus.upcoming;
    if (todayDate.isAfter(end)) return TripStatus.past;
    return TripStatus.current;
  }

  /// e.g. "Aug 14 – Aug 16", or "Dates not set" if either date is missing.
  String get dateRangeLabel {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 'Dates not set';
    return '${_formatShortDate(start)} – ${_formatShortDate(end)}';
  }

  /// Trip length in days, inclusive of both endpoints; 0 if dates are unset.
  int get days {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 0;
    return end.difference(start).inDays + 1;
  }
}

/// Parses a Postgres `time` column (e.g. `"09:00:00"`) as returned by
/// Supabase — null for a missing/unparseable value rather than throwing,
/// since callers treat a null start/end time as "use a sensible default"
/// (see `buildTripDays`), not an error.
({int hour, int minute})? _parseTime(dynamic raw) {
  if (raw is! String) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return (hour: hour, minute: minute);
}
