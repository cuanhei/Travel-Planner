import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/budget_category.dart';
import '../models/expense.dart';
import '../models/trip_balance.dart';
import '../models/trip_settlement.dart';
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

  /// [_expenseDeletions]/[_categoryDeletions] only cover the deleting
  /// client's own connection — other members watching the same trip
  /// still depend on the realtime DELETE event alone, which in practice
  /// isn't reliably reaching every filtered `.stream()` subscriber (even
  /// with full replica identity set). This broadcast channel is a
  /// belt-and-suspenders push: [deleteCategory] announces on it, and
  /// every open [watchCategories]/[watchExpenses] for that trip — on
  /// every client — refetches the moment they hear it, regardless of
  /// whether the underlying postgres_changes delete event ever arrives.
  static String _budgetChangesTopic(String tripId) => 'budget-changes:$tripId';

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

  /// See [_expenseDeletions] — same reasoning, but for categories: fired
  /// right after this client deletes one via [deleteCategory], so
  /// [watchCategories] refetches immediately instead of depending on the
  /// realtime DELETE event alone.
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
      // `.stream()` keeps its own internal row cache, patched
      // incrementally from realtime events, and re-derives its emitted
      // list from that cache on every event. If the DELETE for a row
      // never reached this subscription (the known gap this refetch is
      // already working around), the cache still holds it — and the
      // *next* insert/update would resurrect it right back into view
      // by recomputing from that stale cache. Tearing down and
      // resubscribing forces a fresh baseline SELECT so it can't.
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

  /// Organizer-only: permanently delete [label]'s planned budget and
  /// every expense logged under it for this trip — enforced server-side
  /// by `delete_budget_category` (security definer, checks
  /// [isOrganizer]-equivalent itself), not just by hiding the button.
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
    // Tell every other client watching this trip's budget to refetch
    // right now — see _budgetChangesTopic for why this can't rely on the
    // realtime DELETE event alone. Fire-and-forget: a member who misses
    // this (offline, channel still joining) still catches up next time
    // their own stream reconnects or they reopen the screen. The channel
    // is only opened to send this one message, so remove it right after
    // instead of leaking an unjoined entry in the client's channel list.
    final broadcastChannel = _client.channel(_budgetChangesTopic(tripId));
    unawaited(
      broadcastChannel
          .sendBroadcastMessage(event: 'category_deleted', payload: {})
          .whenComplete(() => _client.removeChannel(broadcastChannel)),
    );
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
    RealtimeChannel? broadcastChannel;

    void resubscribeRealtime() {
      realtimeSub?.cancel();
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
      // `.stream()` keeps its own internal row cache, patched
      // incrementally from realtime events, and re-derives its emitted
      // list from that cache on every event. If the DELETE for a row
      // never reached this subscription (the known gap this refetch is
      // already working around), the cache still holds it — and the
      // *next* insert/update (e.g. logging a new expense right after a
      // category delete) would resurrect it right back into view by
      // recomputing from that stale cache, double-counting its amount.
      // Tearing down and resubscribing forces a fresh baseline SELECT
      // so it can't.
      if (!controller.isClosed) resubscribeRealtime();
    }

    controller = StreamController<List<Expense>>.broadcast(
      onListen: () {
        resubscribeRealtime();
        deletionSub = _expenseDeletions.stream
            .where((id) => id == tripId)
            .listen((_) => refetch());
        // Expenses are also bulk-deleted from delete_budget_category(),
        // not just single-expense deletes — that category's broadcast
        // needs to refetch this stream too.
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
    // Always written (unlike addExpense's default-empty [photoUrls]) —
    // the edit sheet always knows the full current photo set (kept,
    // added to, or removed from), so this fully replaces what's stored.
    List<String> photoUrls = const [],
  }) async {
    await _client
        .from('expenses')
        .update({
          'title': title,
          'category': category,
          'amount': amount,
          'stop_place': stopPlace,
          'photo_urls': photoUrls,
        })
        .eq('id', expenseId);
  }

  /// Uploads one receipt photo for an expense being logged in [tripId]
  /// and returns its public URL to add to the expense row's
  /// `photo_urls`. Keyed by trip (not expense id, since a brand-new
  /// expense doesn't have one yet at upload time) plus a timestamp and a
  /// random suffix, so uploading several photos back to back — possibly
  /// within the same millisecond — never collides.
  Future<String> uploadExpensePhoto({
    required String tripId,
    required Uint8List bytes,
    required String fileExt,
  }) async {
    // Avoid Random().nextInt(1 << 32): shifting a Dart int by 32 doesn't
    // behave the same on the web (dart2js/wasm) as on the VM, and can
    // come out as 0 there — nextInt(0) then throws a RangeError. Staying
    // well under 2^31 sidesteps that entirely while still giving plenty
    // of entropy to avoid a same-millisecond filename collision.
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

  /// Every trip member's paid total, summed from [expenses] — the
  /// Expense Split screen derives each person's fair share and the
  /// settle-up plan from these totals directly.
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

  /// See [_categoryDeletions] — same reasoning, for settlement undos:
  /// fired right after this client deletes one via [deleteSettlement].
  static final _settlementDeletions = StreamController<String>.broadcast();

  /// Every recorded real-world payment for [tripId] — Expense Split
  /// nets these against each member's (paid - fair share) balance
  /// before computing the settle-up plan.
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
      // See watchCategories/watchExpenses — rebuilds the underlying
      // stream's own row cache so a missed DELETE event can't resurrect
      // an undone settlement on the next insert.
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

  /// Records that [fromUserId] paid [toUserId] [amount] outside the app
  /// (cash, bank transfer, ...) to settle part of the even split.
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

  /// Undo — the recorder or the organizer only (enforced by RLS too).
  Future<void> deleteSettlement(String id, {required String tripId}) async {
    await _client.from('trip_settlements').delete().eq('id', id);
    _settlementDeletions.add(tripId);
  }
}
