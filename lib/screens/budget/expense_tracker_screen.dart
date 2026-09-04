import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/expense.dart';
import '../../services/budget_service.dart';
import '../../services/group_service.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'budget_planner_screen.dart'
    show
        BudgetCategory,
        budgetCategories,
        categoryVisuals,
        formatAmount,
        translatedCategoryLabel;

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatShortDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

const _calcOperators = {'+', '−', '×', '÷'};

/// Evaluates a calculator-style expression typed via the amount field's
/// on-screen keypad, e.g. "13+12" -> 25 or "100×2−5" -> 195 (standard
/// ×/÷-before-+/− precedence, left to right within each). Returns null
/// if it can't be parsed (empty, a leading/trailing/doubled operator,
/// or division by zero).
double? _evaluateExpression(String input) {
  final expr = input.trim();
  if (expr.isEmpty) return null;

  final tokens = <String>[];
  final buffer = StringBuffer();
  for (final ch in expr.split('')) {
    if (_calcOperators.contains(ch)) {
      if (buffer.isEmpty) return null;
      tokens.add(buffer.toString());
      tokens.add(ch);
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  if (buffer.isEmpty) return null;
  tokens.add(buffer.toString());

  final first = double.tryParse(tokens[0]);
  if (first == null) return null;

  // First pass: × and ÷, left to right.
  final reduced = <Object>[first];
  var i = 1;
  while (i < tokens.length - 1) {
    final op = tokens[i];
    final operand = double.tryParse(tokens[i + 1]);
    if (operand == null) return null;
    if (op == '×' || op == '÷') {
      if (op == '÷' && operand == 0) return null;
      final last = reduced.removeLast() as double;
      reduced.add(op == '×' ? last * operand : last / operand);
    } else {
      reduced.add(op);
      reduced.add(operand);
    }
    i += 2;
  }

  // Second pass: + and −, left to right.
  var result = reduced[0] as double;
  var j = 1;
  while (j < reduced.length - 1) {
    final op = reduced[j] as String;
    final operand = reduced[j + 1] as double;
    result = op == '+' ? result + operand : result - operand;
    j += 2;
  }
  return result;
}

/// Applies one calculator keypad tap to [controller]'s text: digits and
/// `.` append (guarding against a second `.` within the current
/// number), an operator appends (or replaces a trailing operator rather
/// than stacking two), `⌫` deletes the last character, `C` clears, and
/// `=` evaluates the expression in place.
void _applyCalculatorKey(TextEditingController controller, String key) {
  final text = controller.text;

  if (key == 'C') {
    controller.clear();
    return;
  }
  if (key == '⌫') {
    if (text.isNotEmpty) {
      controller.text = text.substring(0, text.length - 1);
    }
    return;
  }
  if (key == '=') {
    final result = _evaluateExpression(text);
    if (result != null) controller.text = formatAmount(result);
    return;
  }
  if (_calcOperators.contains(key)) {
    if (text.isEmpty) return;
    final lastChar = text[text.length - 1];
    controller.text = _calcOperators.contains(lastChar)
        ? text.substring(0, text.length - 1) + key
        : text + key;
    return;
  }
  if (key == '.') {
    final lastOpIndex = text.split('').lastIndexWhere(_calcOperators.contains);
    if (text.substring(lastOpIndex + 1).contains('.')) return;
  }
  controller.text = text + key;
}

/// Handles a physical-keyboard edit to the amount field: normalizes the
/// ASCII operators a keyboard actually types (`* / -`) to the keypad's
/// symbols (`× ÷ −`) so both entry paths produce the exact same
/// expression text, and evaluates immediately if the just-typed
/// character was `=` (e.g. typing "13+12=").
void _handleAmountTyped(TextEditingController controller, String value) {
  final normalized = value
      .replaceAll('*', '×')
      .replaceAll('/', '÷')
      .replaceAll('-', '−');

  if (normalized.endsWith('=')) {
    final expr = normalized.substring(0, normalized.length - 1);
    final result = _evaluateExpression(expr);
    controller.text = result != null ? formatAmount(result) : expr;
    return;
  }

  if (normalized != value) {
    final selection = controller.selection;
    controller.value = controller.value.copyWith(
      text: normalized,
      selection: selection,
    );
  }
}

/// Live running log of trip expenses, backed by Supabase: each entry
/// can be tagged with a category and the stop it was spent at, added
/// fresh or edited later. The per-stop / per-category breakdown is
/// surfaced as "insights" — framed as the data a future AI budget
/// recommendation would draw on.
class ExpenseTrackerScreen extends StatefulWidget {
  const ExpenseTrackerScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<ExpenseTrackerScreen> createState() => _ExpenseTrackerScreenState();
}

class _ExpenseTrackerScreenState extends State<ExpenseTrackerScreen> {
  final _budgetService = BudgetService();
  final _groupService = GroupService();
  late final Future<bool> _isOrganizerFuture = _groupService.isOrganizer(
    widget.tripId,
  );

  Future<void> _saveExpense({
    Expense? existing,
    required String title,
    required String category,
    required double amount,
    required String? stopPlace,
  }) async {
    if (existing != null) {
      await _budgetService.updateExpense(
        existing.id,
        title: title,
        category: category,
        amount: amount,
        stopPlace: stopPlace,
      );
    } else {
      await _budgetService.addExpense(
        tripId: widget.tripId,
        title: title,
        category: category,
        amount: amount,
        spentAt: DateTime.now(),
        stopPlace: stopPlace,
      );
    }
  }

  Future<void> _confirmDeleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('budget_delete_expense_confirm_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${expense.title}" (RM ${expense.amount.toStringAsFixed(2)}) ${tr('budget_delete_expense_confirm_suffix')}',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(tr('budget_delete_button')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _budgetService.deleteExpense(expense.id, tripId: widget.tripId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
    }
  }

  void _showExpenseSheet({
    Expense? existing,
    required List<String> stopSuggestions,
    required List<BudgetCategory> categorySuggestions,
  }) {
    final titleController = TextEditingController(text: existing?.title);
    final amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(2) : '',
    );
    final stopController = TextEditingController(text: existing?.stopPlace);
    final stopFocusNode = FocusNode();
    var selectedCategory = existing != null
        ? categoryVisuals(existing.category)
        : budgetCategories.first;
    String? formError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            Future<void> save() async {
              final title = titleController.text.trim();
              final rawAmount = amountController.text.trim();
              // Save works whether or not "=" was tapped first — typing
              // "13+12" and hitting Add directly computes and saves 25.
              final amount =
                  double.tryParse(rawAmount) ?? _evaluateExpression(rawAmount);
              if (title.isEmpty) {
                setSheetState(() => formError = tr('budget_enter_what_spent_on'));
                return;
              }
              if (amount == null || amount <= 0) {
                setSheetState(() => formError = tr('budget_enter_valid_amount'));
                return;
              }
              final stopPlace = stopController.text.trim();
              Navigator.of(sheetContext).pop();
              await _saveExpense(
                existing: existing,
                title: title,
                category: selectedCategory.label,
                amount: amount,
                stopPlace: stopPlace.isEmpty ? null : stopPlace,
              );
            }

            Future<void> delete() async {
              Navigator.of(sheetContext).pop();
              await _confirmDeleteExpense(existing!);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            existing != null
                                ? tr('budget_edit_expense_title')
                                : tr('budget_add_expense_title'),
                            style: TextStyle(
                              color: sheetContext.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        if (existing != null)
                          IconButton(
                            onPressed: delete,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      onChanged: (_) {
                        if (formError != null) {
                          setSheetState(() => formError = null);
                        }
                      },
                      style: TextStyle(color: sheetContext.colors.ink),
                      decoration: InputDecoration(
                        hintText: tr('budget_expense_title_hint'),
                        filled: true,
                        fillColor: sheetContext.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.text,
                      onChanged: (value) {
                        setSheetState(() {
                          formError = null;
                          _handleAmountTyped(amountController, value);
                        });
                      },
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: tr('budget_amount_hint_keypad'),
                        filled: true,
                        fillColor: sheetContext.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final text = amountController.text;
                        final hasOperator = text.contains(RegExp(r'[+−×÷]'));
                        final preview = hasOperator
                            ? _evaluateExpression(text)
                            : null;
                        if (preview == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            '= RM ${formatAmount(preview)}',
                            style: TextStyle(
                              color: sheetContext.colors.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _CalculatorKeypad(
                      onKeyTap: (key) {
                        setSheetState(() {
                          formError = null;
                          _applyCalculatorKey(amountController, key);
                        });
                      },
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        formError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      tr('budget_field_category'),
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ...budgetCategories.map(
                          (c) => _CategoryChip(
                            category: c,
                            isSelected: c.label == selectedCategory.label,
                            onTap: () =>
                                setSheetState(() => selectedCategory = c),
                          ),
                        ),
                        // Custom categories typed in via "Other" on a
                        // past expense (e.g. "Visa") — offered directly
                        // as a chip from here on, instead of having to
                        // retype it through "Other" every time. Skips
                        // whichever one is currently selected-but-custom
                        // — the "Other" chip below already represents
                        // that case, so this avoids showing it twice.
                        ...categorySuggestions
                            .where(
                              (c) =>
                                  c.label != selectedCategory.label ||
                                  budgetCategories.any(
                                    (b) => b.label == selectedCategory.label,
                                  ),
                            )
                            .map(
                              (c) => _CategoryChip(
                                category: c,
                                isSelected: false,
                                onTap: () =>
                                    setSheetState(() => selectedCategory = c),
                              ),
                            ),
                        _OtherCategoryChip(
                          selectedCategory: selectedCategory,
                          onPicked: (custom) =>
                              setSheetState(() => selectedCategory = custom),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      tr('budget_field_where'),
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('budget_pick_stop_hint'),
                      style: TextStyle(
                        color: sheetContext.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Autocomplete<String>(
                      textEditingController: stopController,
                      focusNode: stopFocusNode,
                      optionsBuilder: (value) {
                        if (value.text.trim().isEmpty) {
                          return stopSuggestions;
                        }
                        final q = value.text.trim().toLowerCase();
                        return stopSuggestions.where(
                          (s) => s.toLowerCase().contains(q),
                        );
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              style: TextStyle(color: sheetContext.colors.ink),
                              decoration: InputDecoration(
                                hintText: tr('budget_where_optional_hint'),
                                prefixIcon: Icon(
                                  Icons.place_rounded,
                                  size: 18,
                                  color: sheetContext.colors.muted,
                                ),
                                filled: true,
                                fillColor: sheetContext.colors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            );
                          },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            color: sheetContext.colors.card,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(14),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 220,
                                minWidth: 280,
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.place_rounded,
                                            size: 14,
                                            color: sheetContext.colors.muted,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: TextStyle(
                                                color: sheetContext.colors.ink,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: save,
                        style: FilledButton.styleFrom(
                          backgroundColor: sheetContext.colors.ink,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          existing != null
                              ? tr('budget_save_changes')
                              : tr('budget_add_button'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: FutureBuilder<bool>(
          future: _isOrganizerFuture,
          builder: (context, organizerSnap) {
            final isOrganizer = organizerSnap.data ?? false;
            return StreamBuilder<List<String>>(
              stream: _budgetService.watchStopNames(widget.tripId),
              builder: (context, stopSnap) {
                final stopNames = stopSnap.data ?? const <String>[];
                return StreamBuilder<List<Expense>>(
                  stream: _budgetService.watchExpenses(widget.tripId),
                  builder: (context, snapshot) {
                    final expenses = snapshot.data ?? const <Expense>[];
                    final total = expenses.fold<double>(
                      0,
                      (sum, e) => sum + e.amount,
                    );

                    final byStop = <String, List<Expense>>{};
                    for (final e in expenses) {
                      if (e.stopPlace == null) continue;
                      byStop.putIfAbsent(e.stopPlace!, () => []).add(e);
                    }
                    final avgPerStop = byStop.isEmpty
                        ? 0.0
                        : byStop.values
                                  .map(
                                    (list) => list.fold<double>(
                                      0,
                                      (s, e) => s + e.amount,
                                    ),
                                  )
                                  .fold<double>(0, (a, b) => a + b) /
                              byStop.length;

                    final byCategory = <String, double>{};
                    for (final e in expenses) {
                      byCategory.update(
                        e.category,
                        (v) => v + e.amount,
                        ifAbsent: () => e.amount,
                      );
                    }
                    final topCategory = byCategory.entries.isEmpty
                        ? null
                        : byCategory.entries.reduce(
                            (a, b) => a.value > b.value ? a : b,
                          );

                    // Suggestions for "Where were you?": planned trip
                    // stops plus any custom stop name already typed on an
                    // expense — a trip with no planned stops (e.g. the
                    // auto-created demo trip) would otherwise offer no
                    // suggestions at all and, since the field used to be
                    // chip-only, no way to tag a stop whatsoever.
                    final stopSuggestions = <String>{
                      ...stopNames,
                      for (final e in expenses)
                        if (e.stopPlace != null) e.stopPlace!,
                    }.toList()..sort();

                    // Custom categories already typed in via "Other" on
                    // a past expense (e.g. "Visa") — offered directly as
                    // a chip from here on instead of only through the
                    // fixed budgetCategories set.
                    final categorySuggestions = <String>{
                      for (final e in expenses)
                        if (!budgetCategories.any((c) => c.label == e.category))
                          e.category,
                    }.toList()..sort();
                    final categoryVisualSuggestions = categorySuggestions
                        .map(categoryVisuals)
                        .toList();

                    return Column(
                      children: [
                        DetailHeader(
                          title: tr('budget_expense_tracker_title'),
                          subtitle: 'RM ${total.toStringAsFixed(2)} ${tr('budget_logged')}',
                          trailing: IconButton(
                            onPressed: () => _showExpenseSheet(
                              stopSuggestions: stopSuggestions,
                              categorySuggestions: categoryVisualSuggestions,
                            ),
                            icon: Icon(
                              Icons.add_circle_rounded,
                              color: context.colors.ink,
                              size: 26,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: context.colors.card,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: context.colors.ink.withValues(
                                        alpha: 0.05,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.insights_rounded,
                                          color: AppColors.accent,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          tr('budget_spending_insights'),
                                          style: TextStyle(
                                            color: context.colors.ink,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _InsightStat(
                                            label: tr('budget_avg_per_stop'),
                                            value: byStop.isEmpty
                                                ? '—'
                                                : 'RM ${formatAmount(avgPerStop)}',
                                          ),
                                        ),
                                        Expanded(
                                          child: _InsightStat(
                                            label: tr('budget_top_category'),
                                            value: topCategory == null
                                                ? '—'
                                                : translatedCategoryLabel(topCategory.key),
                                          ),
                                        ),
                                        Expanded(
                                          child: _InsightStat(
                                            label: tr('budget_stops_tagged'),
                                            value: '${byStop.length}',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      tr('budget_insights_hint'),
                                      style: TextStyle(
                                        color: context.colors.muted,
                                        fontSize: 11,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (expenses.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Center(
                                    child: Text(
                                      tr('budget_no_expenses_logged'),
                                      style: TextStyle(
                                        color: context.colors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ...expenses.map((e) {
                                final visuals = categoryVisuals(e.category);
                                final canEdit =
                                    e.userId == myUid || isOrganizer;
                                return Material(
                                  color: context.colors.card,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: canEdit
                                        ? () => _showExpenseSheet(
                                            existing: e,
                                            stopSuggestions: stopSuggestions,
                                            categorySuggestions:
                                                categoryVisualSuggestions,
                                          )
                                        : null,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(13),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: context.colors.ink
                                                .withValues(alpha: 0.05),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: visuals.color.withValues(
                                                alpha: 0.12,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(
                                              visuals.icon,
                                              color: visuals.color,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  e.title,
                                                  style: TextStyle(
                                                    color: context.colors.ink,
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                Text(
                                                  e.stopPlace == null
                                                      ? '${translatedCategoryLabel(e.category)} · ${_formatShortDate(e.spentAt)}'
                                                      : '${translatedCategoryLabel(e.category)} · ${e.stopPlace} · ${_formatShortDate(e.spentAt)}',
                                                  style: TextStyle(
                                                    color: context.colors.muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            'RM ${e.amount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: context.colors.ink,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          if (canEdit) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: context.colors.muted,
                                              size: 18,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// On-screen calculator keypad for the amount field — digits plus
/// `+ − × ÷` and `=`, so "13+12" can be typed and evaluated to 25
/// directly, like a receipt/accounting app's amount entry. Replaces the
/// OS keyboard (the amount field is read-only) since a plain numeric
/// keypad has no operator keys.
class _CalculatorKeypad extends StatelessWidget {
  const _CalculatorKeypad({required this.onKeyTap});

  final ValueChanged<String> onKeyTap;

  static const _rows = [
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['C', '0', '.', '+'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final key in row) ...[
                  Expanded(
                    child: _KeypadButton(
                      label: key,
                      isOperator: _calcOperators.contains(key),
                      onTap: () => onKeyTap(key),
                    ),
                  ),
                  if (key != row.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _KeypadButton(label: '⌫', onTap: () => onKeyTap('⌫')),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _KeypadButton(
                label: '=',
                isAccent: true,
                onTap: () => onKeyTap('='),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.onTap,
    this.isOperator = false,
    this.isAccent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isOperator;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final background = isAccent ? context.colors.ink : context.colors.surface;
    final foreground = isAccent
        ? Colors.white
        : isOperator
        ? AppColors.accent
        : context.colors.ink;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single selectable category chip — shared by the fixed
/// [budgetCategories] and by previously-used custom categories.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final BudgetCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? category.color.withValues(alpha: 0.16)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? category.color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 14, color: category.color),
            const SizedBox(width: 6),
            Text(
              translatedCategoryLabel(category.label),
              style: TextStyle(
                color: isSelected ? category.color : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip for a category outside the fixed [budgetCategories] set —
/// prompts for a custom name (e.g. "Souvenirs", "Visa Fees") so
/// spending that doesn't fit the presets still gets tagged and shows
/// up in the Budget Planner's "By Category" breakdown.
class _OtherCategoryChip extends StatelessWidget {
  const _OtherCategoryChip({
    required this.selectedCategory,
    required this.onPicked,
  });

  final BudgetCategory selectedCategory;
  final ValueChanged<BudgetCategory> onPicked;

  bool get _isSelected =>
      !budgetCategories.any((c) => c.label == selectedCategory.label);

  Future<void> _pick(BuildContext context) async {
    final controller = TextEditingController(
      text: _isSelected ? selectedCategory.label : '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('budget_custom_category_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: dialogContext.colors.ink),
          decoration: InputDecoration(
            hintText: tr('budget_custom_category_hint'),
            filled: true,
            fillColor: dialogContext.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.colors.ink,
            ),
            child: Text(tr('budget_use_this_button')),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      onPicked(categoryVisuals(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _isSelected ? selectedCategory : categoryVisuals('Other');
    return GestureDetector(
      onTap: () => _pick(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isSelected
              ? c.color.withValues(alpha: 0.16)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isSelected ? c.color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(c.icon, size: 14, color: c.color),
            const SizedBox(width: 6),
            Text(
              _isSelected ? selectedCategory.label : tr('budget_other_category'),
              style: TextStyle(
                color: _isSelected ? c.color : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightStat extends StatelessWidget {
  const _InsightStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: context.colors.muted, fontSize: 10.5),
        ),
      ],
    );
  }
}
