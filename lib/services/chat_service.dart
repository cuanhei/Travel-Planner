import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_attachment.dart';
import '../models/group_message.dart';
import 'chat_media_service.dart';
import 'supabase_config.dart';

/// Backend for the trip's group chat.
class ChatService {
  ChatService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;
  final _media = ChatMediaService();

  String get _uid => _client.auth.currentUser!.id;

  Stream<List<GroupMessage>> watchMessages(String tripId) {
    return _client
        .from('group_messages')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        // Oldest-first: `order()` defaults to descending, which put the
        // newest message at the top of the plain top-to-bottom ListView.
        .order('created_at', ascending: true)
        .asyncMap((rows) async {
          final userIds = rows
              .map((r) => r['user_id'] as String)
              .toSet()
              .toList();
          if (userIds.isEmpty) return <GroupMessage>[];
          final profiles = await _client
              .from('profiles')
              .select('id, display_name, avatar_color')
              .inFilter('id', userIds);
          final profileById = {
            for (final p in profiles as List) p['id'] as String: p,
          };
          // Nicknames are per-trip (trip_members.nickname), not part of
          // the profile — a sender's Group Chat name prefers their own
          // nickname for this trip when they've set one. Best-effort:
          // if this lookup fails (e.g. migration 0016 not applied yet
          // on this database), messages should still show with their
          // plain profile name rather than the whole chat going blank.
          var nicknameByUserId = <String, String>{};
          try {
            final members = await _client
                .from('trip_members')
                .select('user_id, nickname')
                .eq('trip_id', tripId)
                .inFilter('user_id', userIds);
            nicknameByUserId = {
              for (final m in members as List)
                if (m['nickname'] != null)
                  m['user_id'] as String: m['nickname'] as String,
            };
          } catch (_) {
            // Fall through with no nicknames resolved.
          }
          return rows.where((r) => profileById.containsKey(r['user_id'])).map((
            r,
          ) {
            final userId = r['user_id'] as String;
            final profile = profileById[userId]!;
            // Explicitly typed: an untyped `{...profile, if (...) ...}`
            // literal infers as Map<dynamic, dynamic> here (the `if`
            // collection-element defeats the spread's own Map<String,
            // dynamic> type), which then fails GroupMessage.fromMap's
            // `as Map<String, dynamic>` cast on every single message.
            final mergedProfile = <String, dynamic>{
              ...profile,
              if (nicknameByUserId[userId] != null)
                'display_name': nicknameByUserId[userId],
            };
            return GroupMessage.fromMap({...r, 'profiles': mergedProfile});
          }).toList();
        });
  }

  Future<void> sendMessage({
    required String tripId,
    String? body,
    ChatAttachment? attachment,
  }) async {
    final trimmed = body?.trim();
    if ((trimmed == null || trimmed.isEmpty) && attachment == null) return;
    await _client.from('group_messages').insert({
      'trip_id': tripId,
      'user_id': _uid,
      if (trimmed != null && trimmed.isNotEmpty) 'body': trimmed,
      if (attachment != null) ...attachment.toInsertMap(),
    });
  }

  /// Uploads a photo/video/voice-note file for this trip's chat and
  /// returns its public URL, ready to pass into [sendMessage] as part
  /// of a [ChatAttachment].
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

  Future<void> deleteMessage(String messageId) async {
    await _client.from('group_messages').delete().eq('id', messageId);
  }

  /// Live read receipts for every message in [tripId], grouped by
  /// message id then by the member who read it. A separate stream
  /// (rather than embedded in [watchMessages]) since realtime streams
  /// don't support joins and the two update independently anyway.
  Stream<Map<String, Map<String, DateTime>>> watchReadReceipts(String tripId) {
    return _client
        .from('group_message_reads')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('trip_id', tripId)
        .map((rows) {
          final byMessage = <String, Map<String, DateTime>>{};
          for (final r in rows) {
            final messageId = r['message_id'] as String;
            byMessage.putIfAbsent(messageId, () => {})[r['user_id'] as String] =
                DateTime.parse(r['read_at'] as String);
          }
          return byMessage;
        });
  }

  /// Records that the signed-in member has now seen each of
  /// [messageIds] — safe to call repeatedly (e.g. every time the chat's
  /// message list changes while the screen is open); already-read
  /// messages are silently skipped rather than overwriting `read_at`.
  Future<void> markMessagesRead({
    required String tripId,
    required List<String> messageIds,
  }) async {
    if (messageIds.isEmpty) return;
    await _client
        .from('group_message_reads')
        .upsert(
          [
            for (final id in messageIds)
              {'message_id': id, 'trip_id': tripId, 'user_id': _uid},
          ],
          onConflict: 'message_id,user_id',
          ignoreDuplicates: true,
        );
  }
}
