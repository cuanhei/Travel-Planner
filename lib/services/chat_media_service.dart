import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

/// Uploads a chat attachment (photo/video/voice note) to the shared
/// `chat-media` storage bucket — used by both [ChatService] (group
/// chat) and `DirectMessageService`, which otherwise have nothing else
/// in common worth merging into one class.
class ChatMediaService {
  ChatMediaService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<String> upload({
    required String tripId,
    required Uint8List bytes,
    required String fileExt,
    required String contentType,
  }) async {
    // See budget_service.dart's uploadExpensePhoto for why this avoids
    // Random().nextInt(1 << 32).
    final suffix = Random().nextInt(1000000000).toRadixString(36);
    final path =
        '$tripId/${_uid}_${DateTime.now().millisecondsSinceEpoch}_$suffix.$fileExt';
    await _client.storage
        .from('chat-media')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return _client.storage.from('chat-media').getPublicUrl(path);
  }
}
