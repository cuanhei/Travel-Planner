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

  /// [otherUserId]'s own "read up to" marker for *their* conversation
  /// with the signed-in user — i.e. whether (and when) they've seen the
  /// messages the signed-in user sent them. This is their row, not the
  /// caller's, so it relies on direct_message_reads' select policy
  /// covering both participants (migration 0017).
  Stream<DateTime?> watchTheirLastRead({
    required String tripId,
    required String otherUserId,
  }) {
    final myUid = _uid;
    return _client
        .from('direct_message_reads')
        .stream(primaryKey: ['trip_id', 'user_id', 'other_user_id'])
        .eq('trip_id', tripId)
        .eq('user_id', otherUserId)
        .eq('other_user_id', myUid)
        .map(
          (rows) => rows.isEmpty
              ? null
              : DateTime.parse(rows.first['last_read_at'] as String),
        );
  }

  /// Every reaction on a DM the signed-in user can see (i.e. is
  /// sender/recipient of), across the whole trip — grouped by message
  /// id then by the member who reacted. [DirectChatScreen] narrows this
  /// down to just its own conversation's message ids, the same way
  /// [watchConversation] narrows [watchAllMyMessages].
  Stream<Map<String, Map<String, String>>> watchReactions(String tripId) {
    return _client
        .from('direct_message_reactions')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('trip_id', tripId)
        .map((rows) {
          final byMessage = <String, Map<String, String>>{};
          for (final r in rows) {
            byMessage.putIfAbsent(r['message_id'] as String, () => {})[r['user_id']
                    as String] =
                r['emoji'] as String;
          }
          return byMessage;
        });
  }

  /// Sets (replacing any previous one) the signed-in member's reaction
  /// on [messageId].
  Future<void> setReaction({
    required String tripId,
    required String messageId,
    required String emoji,
  }) async {
    await _client.from('direct_message_reactions').upsert({
      'message_id': messageId,
      'trip_id': tripId,
      'user_id': _uid,
      'emoji': emoji,
    }, onConflict: 'message_id,user_id');
  }

  /// Removes the signed-in member's reaction on [messageId], if any.
  Future<void> removeReaction(String messageId) async {
    await _client
        .from('direct_message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', _uid);
  }
}
