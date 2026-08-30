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
/// Carries the organizer's [reason] when [status] is `'rejected'`.
class MyJoinRequest {
  const MyJoinRequest({
    required this.id,
    required this.status,
    required this.reason,
    required this.createdAt,
  });

  final String id;
  final String status;
  final String? reason;
  final DateTime createdAt;

  factory MyJoinRequest.fromMap(Map<String, dynamic> map) {
    return MyJoinRequest(
      id: map['id'] as String,
      status: map['status'] as String,
      reason: map['reason'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
