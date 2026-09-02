import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_attachment.dart';
import '../models/direct_message.dart';
import 'chat_media_service.dart';
import 'supabase_config.dart';

/// Backend for private 1:1 messaging between two members of the same
/// trip — started from a member's tile in the Group Travel dashboard.
class DirectMessageService {
  DirectMessageService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;
  final _media = ChatMediaService();

  String get _uid => _client.auth.currentUser!.id;

  /// One conversation's messages, oldest first. RLS already restricts
  /// `direct_messages` rows to ones the caller sends or receives, but a
  /// realtime `.stream()` filter can only express a flat AND of
  /// equality checks — not "sender=me AND recipient=them, OR the
  /// reverse" — so this streams every DM row from [tripId] the caller
  /// is party to (across all their conversations in that trip) and
  /// narrows it down to just [otherUserId] client-side.
  Stream<List<DirectMessage>> watchConversation({
    required String tripId,
    required String otherUserId,
  }) {
    final myUid = _uid;
    return _client
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at', ascending: true)
        .map(
          (rows) => rows
              .where(
                (r) =>
                    (r['sender_id'] == myUid &&
                        r['recipient_id'] == otherUserId) ||
                    (r['sender_id'] == otherUserId &&
                        r['recipient_id'] == myUid),
              )
              .map(DirectMessage.fromMap)
              .toList(),
        );
  }

  Future<void> sendMessage({
    required String tripId,
    required String recipientId,
    String? body,
    ChatAttachment? attachment,
  }) async {
    final trimmed = body?.trim();
    if ((trimmed == null || trimmed.isEmpty) && attachment == null) return;
    await _client.from('direct_messages').insert({
      'trip_id': tripId,
      'sender_id': _uid,
      'recipient_id': recipientId,
      if (trimmed != null && trimmed.isNotEmpty) 'body': trimmed,
      if (attachment != null) ...attachment.toInsertMap(),
    });
  }

  Future<String> uploadAttachment({
    required String tripId,
    required Uint8List bytes,
    required String fileExt,
    required String contentType,
  }) {
    return _media.upload(
      tripId: tripId,
      bytes: bytes,
      fileExt: fileExt,
      contentType: contentType,
    );
  }

  /// Every DM the signed-in user has sent or received in [tripId],
  /// across all of their conversations there — RLS already limits this
  /// to their own rows. The Personal Message inbox groups it by the
  /// other participant to show a preview + unread count per member.
  Stream<List<DirectMessage>> watchAllMyMessages(String tripId) {
    return _client
        .from('direct_messages')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map(DirectMessage.fromMap).toList());
  }

  /// The signed-in user's "read up to" marker for every conversation
  /// they have in [tripId] — `other_user_id` -> `last_read_at`.
  Stream<Map<String, DateTime>> watchAllLastRead(String tripId) {
    return _client
        .from('direct_message_reads')
        .stream(primaryKey: ['trip_id', 'user_id', 'other_user_id'])
        .eq('trip_id', tripId)
        .eq('user_id', _uid)
        .map(
          (rows) => {
            for (final r in rows)
              r['other_user_id'] as String: DateTime.parse(
                r['last_read_at'] as String,
              ),
          },
        );
  }

  /// Marks the conversation with [otherUserId] as read as of now — call
  /// whenever [DirectChatScreen] is open and showing its messages.
  Future<void> markConversationRead({
    required String tripId,
    required String otherUserId,
  }) async {
    await _client.from('direct_message_reads').upsert({
      'trip_id': tripId,
      'user_id': _uid,
      'other_user_id': otherUserId,
      'last_read_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'trip_id,user_id,other_user_id');
  }
}
