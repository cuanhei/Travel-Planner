import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/poll.dart';
import 'supabase_config.dart';

class PollService {
  PollService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  Future<List<Poll>> _fetchPolls(String tripId) async {
    final pollRows = await _client
        .from('polls')
        .select()
        .eq('trip_id', tripId)
        .order('created_at');
    if ((pollRows as List).isEmpty) return [];

    final pollIds = pollRows.map((r) => r['id'] as String).toList();
    final optionRows = await _client
        .from('poll_options')
        .select()
        .inFilter('poll_id', pollIds)
        .order('position');
    final voteRows = await _client
        .from('poll_votes')
        .select('poll_id, option_id, user_id')
        .inFilter('poll_id', pollIds);

    final voteCountByOption = <String, int>{};
    final myVoteByPoll = <String, String>{};
    for (final v in voteRows as List) {
      final optionId = v['option_id'] as String;
      voteCountByOption.update(optionId, (c) => c + 1, ifAbsent: () => 1);
      if (v['user_id'] == _uid) {
        myVoteByPoll[v['poll_id'] as String] = optionId;
      }
    }

    final optionsByPoll = <String, List<PollOptionData>>{};
    for (final o in optionRows as List) {
      final pollId = o['poll_id'] as String;
      optionsByPoll
          .putIfAbsent(pollId, () => [])
          .add(
            PollOptionData(
              id: o['id'] as String,
              label: o['label'] as String,
              position: o['position'] as int,
              voteCount: voteCountByOption[o['id']] ?? 0,
            ),
          );
    }

    return pollRows.map((p) {
      final id = p['id'] as String;
      return Poll(
        id: id,
        tripId: p['trip_id'] as String,
        question: p['question'] as String,
        createdBy: p['created_by'] as String,
        createdAt: DateTime.parse(p['created_at'] as String),
        options: optionsByPoll[id] ?? const [],
        votedOptionId: myVoteByPoll[id],
      );
    }).toList();
  }

  Stream<List<Poll>> watchPolls(String tripId) {
    late final StreamController<List<Poll>> controller;
    late final RealtimeChannel channel;

    Future<void> refresh() async {
      if (controller.isClosed) return;
      controller.add(await _fetchPolls(tripId));
    }

    controller = StreamController<List<Poll>>.broadcast(
      onListen: () {
        channel = _client
            .channel('polls-$tripId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'polls',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'trip_id',
                value: tripId,
              ),
              callback: (_) => refresh(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'poll_options',
              callback: (_) => refresh(),
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'poll_votes',
              callback: (_) => refresh(),
            )
            .subscribe();
        refresh();
      },
      onCancel: () => _client.removeChannel(channel),
    );

    return controller.stream;
  }

  Future<String> createPoll({
    required String tripId,
    required String question,
    required List<String> optionLabels,
  }) async {
    final pollRow = await _client
        .from('polls')
        .insert({'trip_id': tripId, 'question': question, 'created_by': _uid})
        .select()
        .single();
    final pollId = pollRow['id'] as String;
    await _client.from('poll_options').insert([
      for (var i = 0; i < optionLabels.length; i++)
        {'poll_id': pollId, 'label': optionLabels[i], 'position': i},
    ]);
    return pollId;
  }

  Future<void> updatePoll({
    required String pollId,
    required String question,
    required List<String> optionLabels,
  }) async {
    await _client.from('polls').update({'question': question}).eq('id', pollId);

    final existing = await _client
        .from('poll_options')
        .select('id')
        .eq('poll_id', pollId)
        .order('position');
    final existingIds = (existing as List)
        .map((r) => r['id'] as String)
        .toList();

    final steps = existingIds.length > optionLabels.length
        ? existingIds.length
        : optionLabels.length;
    for (var i = 0; i < steps; i++) {
      final hasExisting = i < existingIds.length;
      final hasNew = i < optionLabels.length;
      if (hasExisting && hasNew) {
        await _client
            .from('poll_options')
            .update({'label': optionLabels[i]})
            .eq('id', existingIds[i]);
      } else if (hasNew) {
        await _client.from('poll_options').insert({
          'poll_id': pollId,
          'label': optionLabels[i],
          'position': i,
        });
      } else {
        await _client.from('poll_options').delete().eq('id', existingIds[i]);
      }
    }
  }

  Future<void> deletePoll(String pollId) async {
    await _client.from('polls').delete().eq('id', pollId);
  }

  Future<void> vote({required String pollId, required String optionId}) async {
    await _client.from('poll_votes').upsert({
      'poll_id': pollId,
      'option_id': optionId,
      'user_id': _uid,
      'voted_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'poll_id,user_id');
  }
}
