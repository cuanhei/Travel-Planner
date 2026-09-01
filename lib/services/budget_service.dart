import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/budget_category.dart';
import '../models/expense.dart';
import '../models/trip_balance.dart';
import 'supabase_config.dart';

/// Backend for the Budget module: total budget, category planning,
/// expense logging, and per-member balances/splits for one trip.
class BudgetService {
  BudgetService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String get _uid => _client.auth.currentUser!.id;

  /// Fires a tripId right after this client deletes an expense for that
  /// trip. Supabase Realtime's `postgres_changes` filters (here,
  /// `trip_id = ...`) are evaluated against a DELETE event's replica
  /// identity columns, which by default is just the primary key — so a
  /// filtered DELETE can silently never reach a subscriber even with
  /// `expenses replica identity full` set (migration 0008), depending on
  /// how promptly that took effect for the deleting client's own
  /// connection. Every open [watchExpenses] stream for that trip listens
  /// on this and does an immediate manual re-fetch, so the deleting
  /// client's own UI always reflects it right away regardless of
  /// whether the realtime broadcast ever arrives. `static` so it's
  /// shared across every `BudgetService` instance (each screen creates
  /// its own).
  static final _expenseDeletions = StreamController<String>.broadcast();

  // ---- Total budget -------------------------------------------------

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

  // ---- Categories -----------------------------------------------------

  Stream<List<BudgetCategoryData>> watchCategories(String tripId) {
    return _client
        .from('budget_categories')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at')
        .map((rows) => rows.map(BudgetCategoryData.fromMap).toList());
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

  // ---- Stops --------------------------------------------------------------

  /// Live list of stop names for a trip, for the Expense Tracker's
  /// "Where were you?" tagging chips.
  Stream<List<String>> watchStopNames(String tripId) {
    return _client
        .from('trip_stops')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('created_at')
        .map((rows) => rows.map((r) => r['name'] as String).toList());
  }

  // ---- Expenses ---------------------------------------------------------

  Stream<List<Expense>> watchExpenses(String tripId) {
    late StreamController<List<Expense>> controller;
    StreamSubscription<List<Expense>>? realtimeSub;
    StreamSubscription<String>? deletionSub;

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
    }

    controller = StreamController<List<Expense>>.broadcast(
      onListen: () {
        // Ordered by created_at (not spent_at) so newly-added expenses
        // always land at the top: spent_at is a date-only column, so
        // two expenses logged the same day would tie and sort
        // unpredictably.
        realtimeSub = _client
            .from('expenses')
            .stream(primaryKey: ['id'])
            .eq('trip_id', tripId)
            .order('created_at', ascending: false)
            .map((rows) => rows.map(Expense.fromMap).toList())
            .listen(controller.add, onError: controller.addError);
        deletionSub = _expenseDeletions.stream
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

  Future<Expense> addExpense({
    required String tripId,
    required String title,
    required String category,
    required double amount,
    required DateTime spentAt,
    String? stopPlace,
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
  }) async {
    await _client
        .from('expenses')
        .update({
          'title': title,
          'category': category,
          'amount': amount,
          'stop_place': stopPlace,
        })
        .eq('id', expenseId);
  }

  Future<void> deleteExpense(String expenseId, {required String tripId}) async {
    // Plain delete() with no .select() returns success even when RLS
    // silently blocks it (0 rows affected, no error) — request the
    // deleted row back so a blocked delete surfaces as a real failure
    // instead of the sheet just closing with nothing actually removed.
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

  // ---- Balances / splits ------------------------------------------------

  /// Every trip member's paid total (summed from [expenses]) and owed
  /// amount (from `trip_balances`, defaulting to 0 until the organizer
  /// sets it).
  Future<List<TripBalance>> getBalances(String tripId) async {
    final members = await _client
        .from('trip_members')
        .select('user_id, role')
        .eq('trip_id', tripId);
    final userIds = (members as List)
        .map((m) => m['user_id'] as String)
        .toList();
    if (userIds.isEmpty) return [];

    // trip_members.user_id and profiles.id both reference auth.users but
    // not each other, so there's no FK path for PostgREST to embed
    // profiles automatically (matches GroupService.watchMembers) — fetch
    // separately and merge client-side instead.
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
        .eq('trip_id', tripId);
    final paidByUser = <String, double>{};
    for (final row in expenseRows as List) {
      final userId = row['user_id'] as String;
      final amount = (row['amount'] as num).toDouble();
      paidByUser.update(userId, (v) => v + amount, ifAbsent: () => amount);
    }

    final balanceRows = await _client
        .from('trip_balances')
        .select('user_id, owes_amount')
        .eq('trip_id', tripId);
    final owesByUser = {
      for (final row in balanceRows as List)
        row['user_id'] as String: (row['owes_amount'] as num).toDouble(),
    };

    return members.where((m) => profileById.containsKey(m['user_id'])).map((m) {
      final userId = m['user_id'] as String;
      final profile = profileById[userId]!;
      return TripBalance(
        userId: userId,
        displayName: profile['display_name'] as String,
        avatarColor: profile['avatar_color'] as int,
        isOrganizer: m['role'] == 'organizer',
        paid: paidByUser[userId] ?? 0,
        owes: owesByUser[userId] ?? 0,
      );
    }).toList();
  }

  /// Organizer-only: set how much [userId] still owes.
  Future<void> setOwedAmount({
    required String tripId,
    required String userId,
    required double amount,
  }) async {
    await _client.from('trip_balances').upsert({
      'trip_id': tripId,
      'user_id': userId,
      'owes_amount': amount,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'trip_id,user_id');
  }
}
