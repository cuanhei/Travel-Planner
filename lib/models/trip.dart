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

enum TripStatus { current, upcoming, past }

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
    this.description,
    this.startLocationName,
    this.startAddress,
    this.startLatitude,
    this.startLongitude,
    this.endLocationName,
    this.endAddress,
    this.endLatitude,
    this.endLongitude,
  });

  final String id;
  final String name;
  final String? description;
  final String destination;
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalBudget;
  final String createdBy;
  final DateTime createdAt;
  final String? startLocationName;
  final String? startAddress;
  final double? startLatitude;
  final double? startLongitude;
  final String? endLocationName;
  final String? endAddress;
  final double? endLatitude;
  final double? endLongitude;

  factory Trip.fromMap(Map<String, dynamic> map) {
    return Trip(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
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
      startAddress: map['start_address'] as String?,
      startLatitude: (map['start_latitude'] as num?)?.toDouble(),
      startLongitude: (map['start_longitude'] as num?)?.toDouble(),
      endLocationName: map['end_location_name'] as String?,
      endAddress: map['end_address'] as String?,
      endLatitude: (map['end_latitude'] as num?)?.toDouble(),
      endLongitude: (map['end_longitude'] as num?)?.toDouble(),
    );
  }

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

  String get dateRangeLabel {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 'Dates not set';
    return '${_formatShortDate(start)} – ${_formatShortDate(end)}';
  }

  int get days {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 0;
    return end.difference(start).inDays + 1;
  }

  /// Calendar days from today until [startDate] (0 = starts today,
  /// negative = already started); null if [startDate] is unset.
  int? get daysUntilStart {
    final start = startDate;
    if (start == null) return null;
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final startDateOnly = DateTime(start.year, start.month, start.day);
    return startDateOnly.difference(todayDate).inDays;
  }
}
