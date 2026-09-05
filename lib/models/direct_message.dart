import 'chat_attachment.dart';
import 'chat_reply_preview.dart';

class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.recipientId,
    required this.body,
    required this.createdAt,
    this.attachment,
    this.reactions = const {},
    this.replyToId,
    this.replyPreview,
    this.editedAt,
    this.deletedAt,
    this.pinnedAt,
  });

  final String id;
  final String tripId;
  final String senderId;
  final String recipientId;
  final String? body;
  final ChatAttachment? attachment;
  final DateTime createdAt;

  final Map<String, String> reactions;

  final String? replyToId;
  final ChatReplyPreview? replyPreview;

  final DateTime? editedAt;

  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;

  final DateTime? pinnedAt;
  bool get isPinned => pinnedAt != null;

  factory DirectMessage.fromMap(Map<String, dynamic> map) => DirectMessage(
    id: map['id'] as String,
    tripId: map['trip_id'] as String,
    senderId: map['sender_id'] as String,
    recipientId: map['recipient_id'] as String,
    body: map['body'] as String?,
    attachment: ChatAttachment.fromMap(map),
    createdAt: DateTime.parse(map['created_at'] as String),
    replyToId: map['reply_to_id'] as String?,
    editedAt: map['edited_at'] != null
        ? DateTime.parse(map['edited_at'] as String)
        : null,
    deletedAt: map['deleted_at'] != null
        ? DateTime.parse(map['deleted_at'] as String)
        : null,
    pinnedAt: map['pinned_at'] != null
        ? DateTime.parse(map['pinned_at'] as String)
        : null,
  );

  DirectMessage _copyWith({
    Map<String, String>? reactions,
    ChatReplyPreview? replyPreview,
  }) => DirectMessage(
    id: id,
    tripId: tripId,
    senderId: senderId,
    recipientId: recipientId,
    body: body,
    createdAt: createdAt,
    attachment: attachment,
    reactions: reactions ?? this.reactions,
    replyToId: replyToId,
    replyPreview: replyPreview ?? this.replyPreview,
    editedAt: editedAt,
    deletedAt: deletedAt,
    pinnedAt: pinnedAt,
  );

  DirectMessage withReactions(Map<String, String> reactions) =>
      _copyWith(reactions: reactions);

  DirectMessage withReplyPreview(ChatReplyPreview? preview) =>
      _copyWith(replyPreview: preview);
}
