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

/// A pending (or decided) request to join a trip via invite code,
/// backed by `trip_join_requests`.
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

/// The signed-in user's own join request, as seen from the requester's
/// side — no profile join needed since it's their own name/avatar.
/// Carries the organizer's [reason] when [status] is `'rejected'`, and
/// the trip's own name/destination/dates so the requester can tell which
/// trip a pending or decided request is actually for.
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

  /// Trip fields are null until [GroupService.watchMyRequests] resolves
  /// them in a second query (Realtime streams can't embed joins).
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

  /// e.g. "Aug 14 – Aug 16", or "Dates not set" if the trip hasn't
  /// scheduled them yet (or hasn't resolved over the wire).
  String get dateRangeLabel {
    final start = startDate;
    final end = endDate;
    if (start == null || end == null) return 'Dates not set';
    return '${_formatShortDate(start)} – ${_formatShortDate(end)}';
  }
}
