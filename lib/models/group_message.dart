import 'chat_attachment.dart';
import 'chat_reply_preview.dart';

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

  final String? body;
  final ChatAttachment? attachment;
  final DateTime createdAt;

  final Map<String, DateTime> readBy;

  final Map<String, String> reactions;

  final String? replyToId;
  final ChatReplyPreview? replyPreview;

  final DateTime? editedAt;

  final DateTime? deletedAt;
  bool get isDeleted => deletedAt != null;

  final List<String> mentionedUserIds;

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

  bool seenByAll(Iterable<String> otherMemberIds) =>
      otherMemberIds.every(readBy.containsKey);
}
