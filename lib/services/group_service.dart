import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group_member.dart';
import '../models/join_request.dart';
import 'supabase_config.dart';

const _inviteCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Backend for the Group module: member roster, invite codes, and the
/// request-to-join / approve-or-reject flow.
class GroupService {
  GroupService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Whether the signed-in user is this trip's organizer. A cheap
  /// one-shot check rather than a stream — role never changes after a
  /// trip's created (no promote/demote flow exists), so realtime isn't
  /// needed here. Used by Budget screens to gate organizer-only actions
  /// (editing the total budget) client-side, matching what RLS already
  /// enforces server-side.
  Future<bool> isOrganizer(String tripId) async {
    final row = await _client
        .from('trip_members')
        .select('role')
        .eq('trip_id', tripId)
        .eq('user_id', _uid)
        .maybeSingle();
    return row?['role'] == 'organizer';
  }

  // ---- Members ------------------------------------------------------

  Stream<List<GroupMember>> watchMembers(String tripId) {
    return _client
        .from('trip_members')
        .stream(primaryKey: ['trip_id', 'user_id'])
        .eq('trip_id', tripId)
        .order('joined_at')
        .asyncMap((rows) async {
          // Realtime streams don't support embedded joins, so resolve
          // profiles in a second query.
          final userIds = rows.map((r) => r['user_id'] as String).toList();
          if (userIds.isEmpty) return <GroupMember>[];
          final profiles = await _client
              .from('profiles')
              .select('id, display_name, avatar_color')
              .inFilter('id', userIds);
          final profileById = {
            for (final p in profiles as List) p['id'] as String: p,
          };
          return rows
              .where((r) => profileById.containsKey(r['user_id']))
              .map(
                (r) => GroupMember.fromMap({
                  ...r,
                  'profiles': profileById[r['user_id']],
                }),
              )
              .toList();
        });
  }

  Future<void> removeMember({
    required String tripId,
    required String userId,
  }) async {
    await _client
        .from('trip_members')
        .delete()
        .eq('trip_id', tripId)
        .eq('user_id', userId);
  }

  // ---- Invite codes ---------------------------------------------------

  /// Organizer-only: generate a fresh 6-character invite code, valid
  /// for 24 hours.
  Future<String> generateInviteCode(String tripId) async {
    final code = List.generate(
      6,
      (_) => _inviteCodeChars[Random.secure().nextInt(_inviteCodeChars.length)],
    ).join();
    await _client.from('trip_invites').insert({
      'code': code,
      'trip_id': tripId,
      'created_by': _uid,
      'expires_at': DateTime.now()
          .add(const Duration(hours: 24))
          .toIso8601String(),
    });
    return code;
  }

  /// Requester-side: submit an invite code. Throws if it's invalid,
  /// expired, or the caller is already a member.
  Future<void> requestToJoin(String code) async {
    await _client.rpc('request_to_join', params: {'p_code': code});
  }

  Stream<List<JoinRequest>> watchJoinRequests(String tripId) {
    // Filtered only by trip_id (immutable) rather than also `status`:
    // Realtime evaluates postgres_changes filters against a row's *new*
    // state, so an update that moves a row's status away from 'pending'
    // would otherwise never match the filter and the client would never
    // hear about it — the row would linger as "pending" in the UI until
    // the screen re-subscribes. Pending-only filtering happens below,
    // client-side, once decided rows are actually delivered.
    return _client
        .from('trip_join_requests')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at')
        .asyncMap((rows) async {
          final pending = rows.where((r) => r['status'] == 'pending').toList();
          final userIds = pending.map((r) => r['user_id'] as String).toList();
          if (userIds.isEmpty) return <JoinRequest>[];
          final profiles = await _client
              .from('profiles')
              .select('id, display_name, avatar_color')
              .inFilter('id', userIds);
          final profileById = {
            for (final p in profiles as List) p['id'] as String: p,
          };
          return pending
              .where((r) => profileById.containsKey(r['user_id']))
              .map(
                (r) => JoinRequest.fromMap({
                  ...r,
                  'profiles': profileById[r['user_id']],
                }),
              )
              .toList();
        });
  }

  /// Organizer-only: approve or reject a pending join request. [reason]
  /// is shown back to the requester when rejecting (ignored on approval).
  Future<void> decideJoinRequest({
    required String requestId,
    required bool approve,
    String? reason,
  }) async {
    await _client.rpc(
      'decide_join_request',
      params: {
        'p_request_id': requestId,
        'p_approve': approve,
        'p_reason': approve ? null : reason,
      },
    );
  }

  /// Live list of the signed-in user's own join requests, across every
  /// trip they've requested to join — so a rejected requester can see
  /// the organizer's reason without needing to be a trip member.
  Stream<List<MyJoinRequest>> watchMyRequests() {
    return _client
        .from('trip_join_requests')
        .stream(primaryKey: ['id'])
        .eq('user_id', _uid)
        .order('created_at', ascending: false)
        .map((rows) => rows.map(MyJoinRequest.fromMap).toList());
  }
}
