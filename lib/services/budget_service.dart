import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/budget_category.dart';
import '../models/expense.dart';
import '../models/trip_balance.dart';
import '../models/trip_settlement.dart';
import 'supabase_config.dart';

class BudgetService {
  BudgetService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  static final _expenseDeletions = StreamController<String>.broadcast();

  static String _budgetChangesTopic(String tripId) => 'budget-changes:$tripId';

  Future<double> getTotalBudget(String tripId) async {
    final row = await _client
        .from('trips')
        .select('total_budget')
        .eq('id', tripId)
        .single();
    return (row['total_budget'] as num).toDouble();
  }

  Future<void> setTotalBudget(String tripId, double amount) async {
    await _client
        .from('trips')
        .update({'total_budget': amount})
        .eq('id', tripId);
  }

  Stream<double> watchTotalBudget(String tripId) {
    return _client
        .from('trips')
        .stream(primaryKey: ['id'])
        .eq('id', tripId)
        .map((rows) => (rows.first['total_budget'] as num).toDouble());
  }

  static final _categoryDeletions = StreamController<String>.broadcast();

  Stream<List<BudgetCategoryData>> watchCategories(String tripId) {
    late StreamController<List<BudgetCategoryData>> controller;
    StreamSubscription<List<BudgetCategoryData>>? realtimeSub;
    StreamSubscription<String>? deletionSub;
    RealtimeChannel? broadcastChannel;

    void resubscribeRealtime() {
      realtimeSub?.cancel();
      realtimeSub = _client
          .from('budget_categories')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .order('created_at')
          .map((rows) => rows.map(BudgetCategoryData.fromMap).toList())
          .listen(controller.add, onError: controller.addError);
    }

    Future<void> refetch() async {
      if (controller.isClosed) return;
      try {
        final rows = await _client
            .from('budget_categories')
            .select()
            .eq('trip_id', tripId)
            .order('created_at');
        if (!controller.isClosed) {
          controller.add(rows.map(BudgetCategoryData.fromMap).toList());
        }
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      }

      if (!controller.isClosed) resubscribeRealtime();
    }

    controller = StreamController<List<BudgetCategoryData>>.broadcast(
      onListen: () {
        resubscribeRealtime();
        deletionSub = _categoryDeletions.stream
            .where((id) => id == tripId)
            .listen((_) => refetch());
        broadcastChannel =
            _client
                .channel(_budgetChangesTopic(tripId))
                .onBroadcast(
                  event: 'category_deleted',
                  callback: (_) => refetch(),
                )
              ..subscribe();
      },
      onCancel: () {
        realtimeSub?.cancel();
        deletionSub?.cancel();
        final channel = broadcastChannel;
        if (channel != null) _client.removeChannel(channel);
      },
    );

    return controller.stream;
  }

  Future<void> upsertCategory({
    required String tripId,
    required String label,
    required double plannedAmount,
  }) async {
    await _client.from('budget_categories').upsert({
      'trip_id': tripId,
      'label': label,
      'planned_amount': plannedAmount,
    }, onConflict: 'trip_id,label');
  }

  Future<void> deleteCategory({
    required String tripId,
    required String label,
  }) async {
    await _client.rpc(
      'delete_budget_category',
      params: {'p_trip_id': tripId, 'p_label': label},
    );
    _expenseDeletions.add(tripId);
    _categoryDeletions.add(tripId);

    final broadcastChannel = _client.channel(_budgetChangesTopic(tripId));
    unawaited(
      broadcastChannel
          .sendBroadcastMessage(event: 'category_deleted', payload: {})
          .whenComplete(() => _client.removeChannel(broadcastChannel)),
    );
  }

  Stream<List<String>> watchStopNames(String tripId) {
    return _client
        .from('trip_stops')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at')
        .map((rows) => rows.map((r) => r['name'] as String).toList());
  }

  Stream<List<Expense>> watchExpenses(String tripId) {
    late StreamController<List<Expense>> controller;
    StreamSubscription<List<Expense>>? realtimeSub;
    StreamSubscription<String>? deletionSub;
    RealtimeChannel? broadcastChannel;

    void resubscribeRealtime() {
      realtimeSub?.cancel();

      realtimeSub = _client
          .from('expenses')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(Expense.fromMap).toList())
          .listen(controller.add, onError: controller.addError);
    }

    Future<void> refetch() async {
      if (controller.isClosed) return;
      try {
        final rows = await _client
            .from('expenses')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false);
        if (!controller.isClosed) {
          controller.add(rows.map(Expense.fromMap).toList());
        }
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      }

      if (!controller.isClosed) resubscribeRealtime();
    }

    controller = StreamController<List<Expense>>.broadcast(
      onListen: () {
        resubscribeRealtime();
        deletionSub = _expenseDeletions.stream
            .where((id) => id == tripId)
            .listen((_) => refetch());

        broadcastChannel =
            _client
                .channel(_budgetChangesTopic(tripId))
                .onBroadcast(
                  event: 'category_deleted',
                  callback: (_) => refetch(),
                )
              ..subscribe();
      },
      onCancel: () {
        realtimeSub?.cancel();
        deletionSub?.cancel();
        final channel = broadcastChannel;
        if (channel != null) _client.removeChannel(channel);
      },
    );

    return controller.stream;
  }

  Future<Expense> addExpense({
    required String tripId,
    required String title,
    required String category,
    required double amount,
    required DateTime spentAt,
    String? stopPlace,
    List<String> photoUrls = const [],
    bool isShared = true,
  }) async {
    final row = await _client
        .from('expenses')
        .insert(
          Expense(
            id: '',
            tripId: tripId,
            userId: _uid,
            title: title,
            category: category,
            amount: amount,
            spentAt: spentAt,
            createdAt: spentAt,
            stopPlace: stopPlace,
            photoUrls: photoUrls,
            isShared: isShared,
          ).toInsertMap(),
        )
        .select()
        .single();
    return Expense.fromMap(row);
  }

  Future<void> updateExpense(
    String expenseId, {
    required String title,
    required String category,
    required double amount,
    String? stopPlace,

    List<String> photoUrls = const [],
    bool isShared = true,
  }) async {
    await _client
        .from('expenses')
        .update({
          'title': title,
          'category': category,
          'amount': amount,
          'stop_place': stopPlace,
          'photo_urls': photoUrls,
          'is_shared': isShared,
        })
        .eq('id', expenseId);
  }

  Future<String> uploadExpensePhoto({
    required String tripId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    final suffix = Random().nextInt(1000000000).toRadixString(36);
    final path =
        '$tripId/${_uid}_${DateTime.now().millisecondsSinceEpoch}_$suffix.$fileExt';
    await _client.storage
        .from('expense-photos')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _photoContentType(fileExt),
            upsert: false,
          ),
        );
    return _client.storage.from('expense-photos').getPublicUrl(path);
  }

  static String _photoContentType(String fileExt) {
    switch (fileExt.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> deleteExpense(String expenseId, {required String tripId}) async {
    final deleted = await _client
        .from('expenses')
        .delete()
        .eq('id', expenseId)
        .select();
    if (deleted.isEmpty) {
      throw Exception('Could not delete this expense — check your permission.');
    }
    _expenseDeletions.add(tripId);
  }

  Future<double> getPersonalExpensesTotal(String tripId) async {
    final rows = await _client
        .from('expenses')
        .select('amount')
        .eq('trip_id', tripId)
        .eq('is_shared', false)
        .eq('user_id', _uid);
    return (rows as List).fold<double>(
      0,
      (sum, r) => sum + (r['amount'] as num).toDouble(),
    );
  }

  Future<List<TripBalance>> getBalances(String tripId) async {
    final members = await _client
        .from('trip_members')
        .select('user_id, role')
        .eq('trip_id', tripId);
    final userIds = (members as List)
        .map((m) => m['user_id'] as String)
        .toList();
    if (userIds.isEmpty) return [];

    final profiles = await _client
        .from('profiles')
        .select('id, display_name, avatar_color')
        .inFilter('id', userIds);
    final profileById = {
      for (final p in profiles as List) p['id'] as String: p,
    };

    final expenseRows = await _client
        .from('expenses')
        .select('user_id, amount')
        .eq('trip_id', tripId)
        .eq('is_shared', true);
    final paidByUser = <String, double>{};
    for (final row in expenseRows as List) {
      final userId = row['user_id'] as String;
      final amount = (row['amount'] as num).toDouble();
      paidByUser.update(userId, (v) => v + amount, ifAbsent: () => amount);
    }

    return members.where((m) => profileById.containsKey(m['user_id'])).map((m) {
      final userId = m['user_id'] as String;
      final profile = profileById[userId]!;
      return TripBalance(
        userId: userId,
        displayName: profile['display_name'] as String,
        avatarColor: profile['avatar_color'] as int,
        isOrganizer: m['role'] == 'organizer',
        paid: paidByUser[userId] ?? 0,
      );
    }).toList();
  }

  static final _settlementDeletions = StreamController<String>.broadcast();

  Stream<List<TripSettlement>> watchSettlements(String tripId) {
    late StreamController<List<TripSettlement>> controller;
    StreamSubscription<List<TripSettlement>>? realtimeSub;
    StreamSubscription<String>? deletionSub;

    void resubscribeRealtime() {
      realtimeSub?.cancel();
      realtimeSub = _client
          .from('trip_settlements')
          .stream(primaryKey: ['id'])
          .eq('trip_id', tripId)
          .order('created_at', ascending: false)
          .map((rows) => rows.map(TripSettlement.fromMap).toList())
          .listen(controller.add, onError: controller.addError);
    }

    Future<void> refetch() async {
      if (controller.isClosed) return;
      try {
        final rows = await _client
            .from('trip_settlements')
            .select()
            .eq('trip_id', tripId)
            .order('created_at', ascending: false);
        if (!controller.isClosed) {
          controller.add(rows.map(TripSettlement.fromMap).toList());
        }
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      }

      if (!controller.isClosed) resubscribeRealtime();
    }

    controller = StreamController<List<TripSettlement>>.broadcast(
      onListen: () {
        resubscribeRealtime();
        deletionSub = _settlementDeletions.stream
            .where((id) => id == tripId)
            .listen((_) => refetch());
      },
      onCancel: () {
        realtimeSub?.cancel();
        deletionSub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<void> recordSettlement({
    required String tripId,
    required String fromUserId,
    required String toUserId,
    required double amount,
  }) async {
    await _client.from('trip_settlements').insert({
      'trip_id': tripId,
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'amount': amount,
      'created_by': _uid,
    });
  }

  Future<void> deleteSettlement(String id, {required String tripId}) async {
    await _client.from('trip_settlements').delete().eq('id', id);
    _settlementDeletions.add(tripId);
  }
}
