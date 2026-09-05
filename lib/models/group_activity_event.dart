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

  final String eventType;
  final String userId;
  final String displayName;
  final int avatarColor;
  final DateTime createdAt;

  bool get isJoined => eventType == 'joined';

  String get message => isJoined
      ? '$displayName joined the group'
      : '$displayName left the group';

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
