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

class TripInvitePreview {
  const TripInvitePreview({
    required this.tripId,
    required this.name,
    required this.destination,
    required this.startDate,
    required this.endDate,
  });

  factory TripInvitePreview.fromMap(Map<String, dynamic> map) =>
      TripInvitePreview(
        tripId: map['trip_id'] as String,
        name: map['name'] as String,
        destination: (map['destination'] as String?) ?? '',
        startDate: map['start_date'] != null
            ? DateTime.parse(map['start_date'] as String)
            : null,
        endDate: map['end_date'] != null
            ? DateTime.parse(map['end_date'] as String)
            : null,
      );

  final String tripId;
  final String name;
  final String destination;
  final DateTime? startDate;
  final DateTime? endDate;

  String get dateRangeLabel {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 'Dates not set';
    return '${_formatShortDate(start)} – ${_formatShortDate(end)}';
  }
}
