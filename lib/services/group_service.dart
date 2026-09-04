import 'dart:async';
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

  /// One-off display name lookup — used by the Expense Tracker's
  /// read-only detail view to show who logged an expense that isn't the
  /// viewer's own (and that they can't edit, so there's no [GroupMember]
  /// roster fetch already in hand to pull it from).
  Future<String?> getDisplayName(String userId) async {
    final row = await _client
        .from('profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    return row?['display_name'] as String?;
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

  /// The signed-in user's own nickname for [tripId] (null if they've
  /// never set one) — used to pre-fill Group Chat's "Change Nickname"
  /// dialog with what's currently showing.
  Future<String?> getMyNickname(String tripId) async {
    final row = await _client
        .from('trip_members')
        .select('nickname')
        .eq('trip_id', tripId)
        .eq('user_id', _uid)
        .maybeSingle();
    return row?['nickname'] as String?;
  }

  /// Sets (or, given an empty/blank string, clears) the signed-in
  /// user's nickname for [tripId]. Routed through an RPC rather than a
  /// direct table update so a member can never slip a `role` change
  /// through the same write.
  Future<void> setMyNickname({
    required String tripId,
    required String nickname,
  }) async {
    await _client.rpc(
      'set_my_trip_nickname',
      params: {'p_trip_id': tripId, 'p_nickname': nickname},
    );
  }

  // ---- Invite codes ---------------------------------------------------

  /// Organizer-only: generate a fresh 6-character invite code, valid
  /// for 1 minute.
  Future<String> generateInviteCode(String tripId) async {
    final code = List.generate(
      6,
      (_) => _inviteCodeChars[Random.secure().nextInt(_inviteCodeChars.length)],
    ).join();
    await _client.from('trip_invites').insert({
      'code': code,
      'trip_id': tripId,
      'created_by': _uid,
      // .toUtc() is load-bearing: a local (non-UTC) DateTime's
      // toIso8601String() has no timezone suffix, so Postgres parses it
      // in the DB session's timezone (UTC) as if it were already UTC —
      // for anyone east of UTC (e.g. UTC+8) that silently pushes the
      // stored expires_at hours into the future, so a code the app
      // shows as "expired" (by the device's correct local-time
      // countdown) was still accepted by request_to_join's
      // `expires_at > now()` check server-side.
      'expires_at': DateTime.now()
          .add(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String(),
    });
    return code;
  }

  /// Requester-side: submit an invite code. Throws if it's invalid,
  /// expired, or the caller is already a member.
  Future<void> requestToJoin(String code) async {
    await _client.rpc('request_to_join', params: {'p_code': code});
  }

  /// Resolves [code] to a trip id, but only if the caller is already a
  /// member of that trip — used to redirect someone straight to Trip
  /// Details when [requestToJoin] fails because they're already in.
  /// Returns null if the code doesn't map to a trip they're a member of.
  Future<String?> findMyTripByCode(String code) async {
    final result = await _client.rpc(
      'find_my_trip_by_code',
      params: {'p_code': code},
    );
    return result as String?;
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
  /// trip they've requested to join — so a requester can see the trip
  /// name/dates while pending, and the organizer's reason if rejected,
  /// without needing to be a trip member yet.
  ///
  /// An approved request whose `trip_members` row has since been
  /// deleted (the organizer removed them) is re-labelled `'removed'`
  /// here rather than left showing `'approved'` forever — the
  /// join-request row itself is never updated when a member is
  /// removed, so this has to be derived live from a second stream over
  /// the caller's own `trip_members` rows (which _does_ react to a
  /// realtime delete).
  Stream<List<MyJoinRequest>> watchMyRequests() {
    late final StreamController<List<MyJoinRequest>> controller;
    StreamSubscription? requestsSub;
    StreamSubscription? membersSub;
    List<Map<String, dynamic>>? latestRequests;
    Set<String>? latestMemberTripIds;

    Future<void> emit() async {
      final rows = latestRequests;
      final memberTripIds = latestMemberTripIds;
      // Wait for both streams' first snapshot before emitting anything,
      // otherwise every approved request would flash as "removed" for
      // the instant before the membership snapshot arrives.
      if (rows == null || memberTripIds == null) return;

      final tripIds = rows.map((r) => r['trip_id'] as String).toSet().toList();
      final tripById = <String, dynamic>{};
      if (tripIds.isNotEmpty) {
        final trips = await _client
            .from('trips')
            .select('id, name, destination, start_date, end_date')
            .inFilter('id', tripIds);
        for (final t in trips as List) {
          tripById[t['id'] as String] = t;
        }
      }
      if (controller.isClosed) return;
      controller.add(
        rows.map((r) {
          final status =
              r['status'] == 'approved' && !memberTripIds.contains(r['trip_id'])
              ? 'removed'
              : r['status'];
          return MyJoinRequest.fromMap({
            ...r,
            'status': status,
            'trips': tripById[r['trip_id']],
          });
        }).toList(),
      );
    }

    controller = StreamController<List<MyJoinRequest>>.broadcast(
      onListen: () {
        requestsSub = _client
            .from('trip_join_requests')
            .stream(primaryKey: ['id'])
            .eq('user_id', _uid)
            .order('created_at', ascending: false)
            .listen((rows) {
              latestRequests = rows;
              emit();
            });
        membersSub = _client
            .from('trip_members')
            .stream(primaryKey: ['trip_id', 'user_id'])
            .eq('user_id', _uid)
            .listen((rows) {
              latestMemberTripIds = rows
                  .map((r) => r['trip_id'] as String)
                  .toSet();
              emit();
            });
      },
      onCancel: () {
        requestsSub?.cancel();
        membersSub?.cancel();
      },
    );
    return controller.stream;
  }
}
