import 'chat_attachment.dart';
import 'chat_reply_preview.dart';

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
    this.replyToId,
    this.replyPreview,
    this.editedAt,
    this.deletedAt,
    this.mentionedUserIds = const [],
    this.pinnedAt,
  });

  final String id;
  final String tripId;
  final String userId;
  final String senderName;
  final int senderColor;

  /// Null for a media-only message (photo/video with nothing typed
  /// alongside it), or a deleted one.
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

  /// Members mentioned in [body] via `@Name` — set at send time from the
  /// composer's mention picker, not parsed from the text itself.
  final List<String> mentionedUserIds;

  /// Set while this is the trip's pinned message (only one at a time).
  final DateTime? pinnedAt;
  bool get isPinned => pinnedAt != null;

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
      replyToId: map['reply_to_id'] as String?,
      editedAt: map['edited_at'] != null
          ? DateTime.parse(map['edited_at'] as String)
          : null,
      deletedAt: map['deleted_at'] != null
          ? DateTime.parse(map['deleted_at'] as String)
          : null,
      mentionedUserIds:
          (map['mentioned_user_ids'] as List?)?.cast<String>() ?? const [],
      pinnedAt: map['pinned_at'] != null
          ? DateTime.parse(map['pinned_at'] as String)
          : null,
    );
  }

  GroupMessage _copyWith({
    Map<String, DateTime>? readBy,
    Map<String, String>? reactions,
    ChatReplyPreview? replyPreview,
  }) => GroupMessage(
    id: id,
    tripId: tripId,
    userId: userId,
    senderName: senderName,
    senderColor: senderColor,
    body: body,
    attachment: attachment,
    createdAt: createdAt,
    readBy: readBy ?? this.readBy,
    reactions: reactions ?? this.reactions,
    replyToId: replyToId,
    replyPreview: replyPreview ?? this.replyPreview,
    editedAt: editedAt,
    deletedAt: deletedAt,
    mentionedUserIds: mentionedUserIds,
    pinnedAt: pinnedAt,
  );

  GroupMessage withReadBy(Map<String, DateTime> readBy) =>
      _copyWith(readBy: readBy);

  GroupMessage withReactions(Map<String, String> reactions) =>
      _copyWith(reactions: reactions);

  GroupMessage withReplyPreview(ChatReplyPreview? preview) =>
      _copyWith(replyPreview: preview);

  /// Whether every id in [otherMemberIds] (the trip's other members) has
  /// read this message — WhatsApp-style group semantics: the tick only
  /// turns blue once *everyone* has seen it, not just one person.
  bool seenByAll(Iterable<String> otherMemberIds) =>
      otherMemberIds.every(readBy.containsKey);
}
