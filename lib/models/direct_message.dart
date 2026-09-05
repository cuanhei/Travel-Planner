import 'chat_attachment.dart';
import 'chat_reply_preview.dart';

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

  /// Who reacted to this message and with which emoji — `user_id` ->
  /// emoji. Populated separately from `direct_message_reactions` (via
  /// [withReactions]) since realtime streams don't support joins.
  final Map<String, String> reactions;

  /// The message this one is replying to, if any. [replyPreview] is
  /// filled in separately (via [withReplyPreview]) since a realtime
  /// stream can't embed the quoted message's own content.
  final String? replyToId;
  final ChatReplyPreview? replyPreview;

  /// Set when the sender has edited this message's body.
  final DateTime? editedAt;

  /// Set when the sender deleted this message for everyone — [body] and
  /// [attachment] are cleared server-side once this is set, so the UI
  /// shows a placeholder instead of the original content.
  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;

  /// Set while this is the conversation's pinned message (only one at a
  /// time).
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
