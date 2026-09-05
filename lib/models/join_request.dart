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

class JoinRequest {
  const JoinRequest({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String userId;
  final String displayName;
  final int avatarColor;
  final String status;
  final DateTime createdAt;

  factory JoinRequest.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return JoinRequest(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      userId: map['user_id'] as String,
      displayName: profile['display_name'] as String,
      avatarColor: profile['avatar_color'] as int,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class MyJoinRequest {
  const MyJoinRequest({
    required this.id,
    required this.tripId,
    required this.tripName,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.reason,
    required this.createdAt,
    required this.decidedAt,
  });

  final String id;
  final String tripId;
  final String? tripName;
  final String? destination;
  final DateTime? startDate;
  final DateTime? endDate;
  final String status;
  final String? reason;
  final DateTime createdAt;
  final DateTime? decidedAt;

  factory MyJoinRequest.fromMap(Map<String, dynamic> map) {
    final trip = map['trips'] as Map<String, dynamic>?;
    return MyJoinRequest(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      tripName: trip?['name'] as String?,
      destination: trip?['destination'] as String?,
      startDate: trip?['start_date'] != null
          ? DateTime.parse(trip!['start_date'] as String)
          : null,
      endDate: trip?['end_date'] != null
          ? DateTime.parse(trip!['end_date'] as String)
          : null,
      status: map['status'] as String,
      reason: map['reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      decidedAt: map['decided_at'] != null
          ? DateTime.parse(map['decided_at'] as String)
          : null,
    );
  }

  String get dateRangeLabel {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 'Dates not set';
    return '${_formatShortDate(start)} – ${_formatShortDate(end)}';
  }
}
