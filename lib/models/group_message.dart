import 'chat_attachment.dart';

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
    this.attachment,
    this.readBy = const {},
    this.reactions = const {},
  });

  final String id;
  final String tripId;
  final String userId;
  final String senderName;
  final int senderColor;

  /// Null for a media-only message (photo/video with nothing typed
  /// alongside it).
  final String? body;
  final ChatAttachment? attachment;
  final DateTime createdAt;

  /// Other members who have seen this message, and when — `user_id` ->
  /// `read_at`. Populated separately from `group_message_reads` (via
  /// [withReadBy]) since realtime streams don't support embedded joins.
  final Map<String, DateTime> readBy;

  /// Who reacted to this message and with which emoji — `user_id` ->
  /// emoji. Populated separately from `group_message_reactions` (via
  /// [withReactions]) for the same reason as [readBy].
  final Map<String, String> reactions;

  factory GroupMessage.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>;
    return GroupMessage(
      id: map['id'] as String,
      tripId: map['trip_id'] as String,
      userId: map['user_id'] as String,
      senderName: profile['display_name'] as String,
      senderColor: profile['avatar_color'] as int,
      body: map['body'] as String?,
      attachment: ChatAttachment.fromMap(map),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  GroupMessage withReadBy(Map<String, DateTime> readBy) => GroupMessage(
    id: id,
    tripId: tripId,
    userId: userId,
    senderName: senderName,
    senderColor: senderColor,
    body: body,
    attachment: attachment,
    createdAt: createdAt,
    readBy: readBy,
    reactions: reactions,
  );

  GroupMessage withReactions(Map<String, String> reactions) => GroupMessage(
    id: id,
    tripId: tripId,
    userId: userId,
    senderName: senderName,
    senderColor: senderColor,
    body: body,
    attachment: attachment,
    createdAt: createdAt,
    readBy: readBy,
    reactions: reactions,
  );

  /// Whether every id in [otherMemberIds] (the trip's other members) has
  /// read this message — WhatsApp-style group semantics: the tick only
  /// turns blue once *everyone* has seen it, not just one person.
  bool seenByAll(Iterable<String> otherMemberIds) =>
      otherMemberIds.every(readBy.containsKey);
}
