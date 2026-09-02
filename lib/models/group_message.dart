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
  });

  final String id;
  final String tripId;
  final String userId;
  final String senderName;
  final int senderColor;

  /// Null for a media-only message (photo/video/voice note with
  /// nothing typed alongside it).
  final String? body;
  final ChatAttachment? attachment;
  final DateTime createdAt;

  /// Other members who have seen this message, and when — `user_id` ->
  /// `read_at`. Populated separately from `group_message_reads` (via
  /// [withReadBy]) since realtime streams don't support embedded joins.
  final Map<String, DateTime> readBy;

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
  );

  /// The latest time any member other than [viewerId] saw this message,
  /// or null if nobody besides them has yet — used to decide whether a
  /// sent message's tick should turn blue (and what time to show for
  /// "Seen").
  DateTime? seenAt(String viewerId) {
    DateTime? latest;
    for (final entry in readBy.entries) {
      if (entry.key == viewerId) continue;
      if (latest == null || entry.value.isAfter(latest)) latest = entry.value;
    }
    return latest;
  }
}
