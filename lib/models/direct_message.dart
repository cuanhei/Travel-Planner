import 'chat_attachment.dart';

/// A single message in a private 1:1 conversation between two members
/// of the same trip. Unlike [GroupMessage] this carries no sender
/// profile — a DM screen already knows who the other person is (it's
/// the member the conversation was opened with), so the only thing
/// worth knowing per-message is which of the two participants sent it.
class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.attachment,
  });

  final String id;
  final String tripId;
  final String senderId;
  final String recipientId;
  final String? body;
  final ChatAttachment? attachment;
  final DateTime createdAt;

  factory DirectMessage.fromMap(Map<String, dynamic> map) => DirectMessage(
    id: map['id'] as String,
    tripId: map['trip_id'] as String,
    senderId: map['sender_id'] as String,
    recipientId: map['recipient_id'] as String,
    body: map['body'] as String?,
    attachment: ChatAttachment.fromMap(map),
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}
