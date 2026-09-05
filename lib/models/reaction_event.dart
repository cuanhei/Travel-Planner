/// One reaction row as it actually happened — who reacted, with what,
/// on which message, and when. Separate from the `messageId -> (userId
/// -> emoji)` shape [ChatService.watchReactions] / [DirectMessageService
/// .watchReactions] expose for rendering reaction pills: this one keeps
/// `createdAt`, needed to tell a reaction that's genuinely new from one
/// that already existed the last time it was checked.
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
