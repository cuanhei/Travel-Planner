/// One entry in a trip's activity feed (`trip_activity_log`) — currently
/// just membership changes, shown as WhatsApp-style inline system
/// messages in Group Chat and listed in full from its "History" screen.
class GroupActivityEvent {
  const GroupActivityEvent({
    required this.id,
    required this.eventType,
    required this.userId,
    required this.displayName,
    required this.avatarColor,
    required this.createdAt,
  });

  final String id;

  /// 'joined' or 'left'.
  final String eventType;
  final String userId;
  final String displayName;
  final int avatarColor;
  final DateTime createdAt;

  bool get isJoined => eventType == 'joined';

  /// e.g. "Alex joined the group" / "Alex left the group".
  String get message =>
      isJoined ? '$displayName joined the group' : '$displayName left the group';

  factory GroupActivityEvent.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;
    return GroupActivityEvent(
      id: map['id'] as String,
      eventType: map['event_type'] as String,
      userId: map['user_id'] as String,
      displayName: (profile?['display_name'] as String?) ?? 'Someone',
      avatarColor: (profile?['avatar_color'] as int?) ?? 0xFF9E9E9E,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
