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

  // ---- Expenses ---------------------------------------------------------

  Stream<List<Expense>> watchExpenses(String tripId) {
    return _client
        .from('expenses')
        .stream(primaryKey: ['id'])
        .eq('trip_id', tripId)
        .order('spent_at', ascending: false)
        .map((rows) => rows.map(Expense.fromMap).toList());
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

  Future<void> deleteExpense(String expenseId) async {
    await _client.from('expenses').delete().eq('id', expenseId);
  }

  // ---- Balances / splits ------------------------------------------------

  /// Every trip member's paid total (summed from [expenses]) and owed
  /// amount (from `trip_balances`, defaulting to 0 until the organizer
  /// sets it).
  Future<List<TripBalance>> getBalances(String tripId) async {
    final members = await _client
        .from('trip_members')
        .select('user_id, role, profiles!inner(display_name, avatar_color)')
        .eq('trip_id', tripId);

    final expenseRows = await _client
        .from('expenses')
        .select('user_id, amount')
        .eq('trip_id', tripId);
    final paidByUser = <String, double>{};
    for (final row in expenseRows as List) {
      final userId = row['user_id'] as String;
      final amount = (row['amount'] as num).toDouble();
      paidByUser.update(
        userId,
        (v) => v + amount,
        ifAbsent: () => amount,
      );
    }

    final balanceRows = await _client
        .from('trip_balances')
        .select('user_id, owes_amount')
        .eq('trip_id', tripId);
    final owesByUser = {
      for (final row in balanceRows as List)
        row['user_id'] as String: (row['owes_amount'] as num).toDouble(),
    };

    return (members as List).map((m) {
      final userId = m['user_id'] as String;
      final profile = m['profiles'] as Map<String, dynamic>;
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
