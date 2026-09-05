enum ChatAttachmentType { image, video }

class ChatAttachment {
  const ChatAttachment({required this.type, required this.url});

  final ChatAttachmentType type;
  final String url;

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
