const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    this.startLocationName,
    this.endLocationName,
  });

  final String id;
  final String name;
  final String destination;
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalBudget;
  final String createdBy;
  final DateTime createdAt;
  final String? startLocationName;
  final String? endLocationName;

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
      startLocationName: map['start_location_name'] as String?,
      endLocationName: map['end_location_name'] as String?,
    );
  }

  /// Brief "Start → End" route — e.g. "George Town Ferry Terminal → KLCC",
  /// collapsed to just the start when both ends are the same location.
  /// Falls back to [destination], then null if neither location nor
  /// destination is set.
  String? get routeLabel {
    final start = startLocationName?.trim();
    final end = endLocationName?.trim();
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
