/// A single group-chat message, joined from `group_messages` + `profiles`.
class GroupMessage {
  const GroupMessage({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.senderName,
    required this.senderColor,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String userId;
  final String senderName;
  final int senderColor;
  final String body;
  final DateTime createdAt;

  factory GroupMessage.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return GroupMessage(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      userId: map['user_id'] as String,
      senderName: profile['display_name'] as String,
      senderColor: profile['avatar_color'] as int,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
