import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/group_activity_event.dart';
import '../models/group_member.dart';
import '../models/join_request.dart';
import '../models/trip_invite_preview.dart';
import 'supabase_config.dart';

const _inviteCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

class GroupService {
  GroupService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<bool> isOrganizer(String tripId) async {
    final row = await _client
        .from('trip_members')
        .select('role')
        .eq('trip_id', tripId)
        .eq('user_id', _uid)
        .maybeSingle();
    return row?['role'] == 'organizer';
  }

  Future<String?> getDisplayName(String userId) async {
    final row = await _client
        .from('profiles')
        .select('display_name')
        .eq('id', userId)
        .maybeSingle();
    return row?['display_name'] as String?;
  }

  Stream<List<GroupMember>> watchMembers(String tripId) {
    return _client
        .from('trip_members')
        .stream(primaryKey: ['trip_id', 'user_id'])
        .eq('trip_id', tripId)
        .order('joined_at')
        .asyncMap((rows) async {
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

  Stream<List<GroupActivityEvent>> watchActivityLog(String tripId) {
    return _client
        .from('trip_activity_log')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at', ascending: false)
        .asyncMap((rows) async {
          final userIds = rows
              .map((r) => r['user_id'] as String)
              .toSet()
              .toList();
          if (userIds.isEmpty) return <GroupActivityEvent>[];
          final profiles = await _client
              .from('profiles')
              .select('id, display_name, avatar_color')
              .inFilter('id', userIds);
          final profileById = {
            for (final p in profiles as List) p['id'] as String: p,
          };
          return rows
              .map(
                (r) => GroupActivityEvent.fromMap({
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

  Future<String?> getMyNickname(String tripId) async {
    final row = await _client
        .from('trip_members')
        .select('nickname')
        .eq('trip_id', tripId)
        .eq('user_id', _uid)
        .maybeSingle();
    return row?['nickname'] as String?;
  }

  Future<void> setMyNickname({
    required String tripId,
    required String nickname,
  }) async {
    await _client.rpc(
      'set_my_trip_nickname',
      params: {'p_trip_id': tripId, 'p_nickname': nickname},
    );
  }

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
          .add(const Duration(minutes: 1))
          .toUtc()
          .toIso8601String(),
    });
    return code;
  }

  Future<void> requestToJoin(String code) async {
    await _client.rpc('request_to_join', params: {'p_code': code});
  }

  Future<String?> findMyTripByCode(String code) async {
    final result = await _client.rpc(
      'find_my_trip_by_code',
      params: {'p_code': code},
    );
    return result as String?;
  }

  Future<TripInvitePreview?> getTripPreviewByCode(String code) async {
    final rows = await _client.rpc(
      'get_trip_preview_by_code',
      params: {'p_code': code},
    );
    final list = rows as List;
    if (list.isEmpty) return null;
    return TripInvitePreview.fromMap(list.first as Map<String, dynamic>);
  }

  Stream<List<JoinRequest>> watchJoinRequests(String tripId) {
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

  Stream<List<MyJoinRequest>> watchMyRequests() {
    late final StreamController<List<MyJoinRequest>> controller;
    StreamSubscription? requestsSub;
    StreamSubscription? membersSub;
    List<Map<String, dynamic>>? latestRequests;
    Set<String>? latestMemberTripIds;

    Future<void> emit() async {
      final rows = latestRequests;
      final memberTripIds = latestMemberTripIds;

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
