/// The kind of media a chat message can carry instead of (or alongside)
/// text — shared by [GroupMessage] and `DirectMessage`.
enum ChatAttachmentType { image, video }

/// A photo or video attached to a chat message.
class ChatAttachment {
  const ChatAttachment({required this.type, required this.url});

  final ChatAttachmentType type;
  final String url;

  /// Reads `attachment_type`/`attachment_url` off a raw message row, or
  /// null if the message carries no attachment (a plain text message).
  static ChatAttachment? fromMap(Map<String, dynamic> map) {
    final rawType = map['attachment_type'] as String?;
    final url = map['attachment_url'] as String?;
    if (rawType == null || url == null) return null;
    final type = ChatAttachmentType.values.where((t) => t.name == rawType);
    if (type.isEmpty) return null;
    return ChatAttachment(type: type.first, url: url);
  }

  Map<String, dynamic> toInsertMap() => {
    'attachment_type': type.name,
    'attachment_url': url,
  };
}
