import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/expense.dart';
import '../../services/budget_service.dart';
import '../../services/group_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'budget_planner_screen.dart' show budgetCategories, categoryVisuals;

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

  Future<void> _deleteExpense(String id) => _budgetService.deleteExpense(id);

  void _showExpenseSheet({Expense? existing, required List<String> stopNames}) {
    final titleController = TextEditingController(text: existing?.title);
    final amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(2) : '',
    );
    var selectedCategory = categoryVisuals(existing?.category ?? '');
    String? selectedStop = existing?.stopPlace;

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
              final amount = double.tryParse(amountController.text.trim());
              if (title.isEmpty || amount == null) return;
              Navigator.of(sheetContext).pop();
              await _saveExpense(
                existing: existing,
                title: title,
                category: selectedCategory.label,
                amount: amount,
                stopPlace: selectedStop,
              );
            }

            Future<void> delete() async {
              Navigator.of(sheetContext).pop();
              await _deleteExpense(existing!.id);
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
                            existing != null ? 'Edit Expense' : 'Add Expense',
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
                      style: TextStyle(color: sheetContext.colors.ink),
                      decoration: InputDecoration(
                        hintText: 'What did you spend on?',
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: TextStyle(color: sheetContext.colors.ink),
                      decoration: InputDecoration(
                        hintText: 'Amount (RM)',
                        filled: true,
                        fillColor: sheetContext.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Category',
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
                      children: budgetCategories.map((c) {
                        final isSelected = c.label == selectedCategory.label;
                        return GestureDetector(
                          onTap: () =>
                              setSheetState(() => selectedCategory = c),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? c.color.withValues(alpha: 0.16)
                                  : sheetContext.colors.surface,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? c.color
                                    : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(c.icon, size: 14, color: c.color),
                                const SizedBox(width: 6),
                                Text(
                                  c.label,
                                  style: TextStyle(
                                    color: isSelected
                                        ? c.color
                                        : sheetContext.colors.ink,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Where were you?',
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tag the stop you\'re at so we can learn your spending patterns',
                      style: TextStyle(
                        color: sheetContext.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: stopNames.map((stop) {
                        final isSelected = stop == selectedStop;
                        return GestureDetector(
                          onTap: () => setSheetState(
                            () => selectedStop = isSelected ? null : stop,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? sheetContext.colors.ink
                                  : sheetContext.colors.surface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.place_rounded,
                                  size: 14,
                                  color: isSelected
                                      ? Colors.white
                                      : sheetContext.colors.muted,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  stop,
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : sheetContext.colors.ink,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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
                        child: Text(existing != null ? 'Save Changes' : 'Add'),
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

                    return Column(
                      children: [
                        DetailHeader(
                          title: 'Expense Tracker',
                          subtitle: 'RM ${total.toStringAsFixed(2)} logged',
                          trailing: IconButton(
                            onPressed: () =>
                                _showExpenseSheet(stopNames: stopNames),
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
                                          'Spending Insights',
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
                                            label: 'Avg per stop',
                                            value: byStop.isEmpty
                                                ? '—'
                                                : 'RM ${avgPerStop.toStringAsFixed(0)}',
                                          ),
                                        ),
                                        Expanded(
                                          child: _InsightStat(
                                            label: 'Top category',
                                            value: topCategory?.key ?? '—',
                                          ),
                                        ),
                                        Expanded(
                                          child: _InsightStat(
                                            label: 'Stops tagged',
                                            value: '${byStop.length}',
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Tag expenses with a stop and category — we\'ll use this history to recommend smarter budgets on future trips.',
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
                                      'No expenses logged yet.',
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
                                            stopNames: stopNames,
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
                                                      ? '${e.category} · ${_formatShortDate(e.spentAt)}'
                                                      : '${e.category} · ${e.stopPlace} · ${_formatShortDate(e.spentAt)}',
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
