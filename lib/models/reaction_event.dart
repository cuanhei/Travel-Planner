class ReactionEvent {
  const ReactionEvent({
    required this.messageId,
    required this.userId,
    required this.emoji,
    required this.createdAt,
  });

  factory ReactionEvent.fromMap(Map<String, dynamic> map) => ReactionEvent(
    messageId: map['message_id'] as String,
    userId: map['user_id'] as String,
    emoji: map['emoji'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  final String messageId;
  final String userId;
  final String emoji;
  final DateTime createdAt;
}
