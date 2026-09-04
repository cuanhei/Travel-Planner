import 'package:flutter/material.dart';

import '../../models/budget_category.dart';
import '../../models/expense.dart';
import '../../services/budget_service.dart';
import '../../services/group_service.dart';
import '../../services/locale_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'expense_split_screen.dart';
import 'expense_tracker_screen.dart';

/// Visual definition (icon/color) for a spending category, keyed by
/// [label]. Planned/spent amounts are no longer static — they're read
/// live from Supabase (`budget_categories` / `expenses`) and matched
/// back to this list by label purely to pick an icon and color.
class BudgetCategory {
  const BudgetCategory({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

const budgetCategories = [
  BudgetCategory(
    label: 'Accommodation',
    icon: Icons.hotel_rounded,
    color: Color(0xFF5C6BC0),
  ),
  BudgetCategory(
    label: 'Food & Drinks',
    icon: Icons.restaurant_rounded,
    color: AppColors.accent,
  ),
  BudgetCategory(
    label: 'Transport',
    icon: Icons.directions_bus_filled_rounded,
    color: Color(0xFF11998E),
  ),
  BudgetCategory(
    label: 'Shopping',
    icon: Icons.shopping_bag_rounded,
    color: Color(0xFFFFB347),
  ),
  BudgetCategory(
    label: 'Activities',
    icon: Icons.local_activity_rounded,
    color: Color(0xFF8E63CE),
  ),
];

/// Fallback visual for a custom category typed in via "Other" — a
/// neutral tag icon rather than misleadingly reusing Accommodation's.
BudgetCategory _otherCategoryVisual(String label) =>
    BudgetCategory(label: label, icon: Icons.sell_rounded, color: Colors.grey);

BudgetCategory categoryVisuals(String label) => budgetCategories.firstWhere(
  (c) => c.label == label,
  orElse: () => _otherCategoryVisual(label),
);

const _categoryTranslationKeys = {
  'Accommodation': 'budget_category_accommodation',
  'Food & Drinks': 'budget_category_food',
  'Transport': 'budget_category_transport',
  'Shopping': 'budget_category_shopping',
  'Activities': 'budget_category_activities',
};

/// Translates a fixed budget category label; a custom ("Other") category
/// a traveler typed in has no fixed-language key, so it's shown exactly
/// as entered.
String translatedCategoryLabel(String label) {
  final key = _categoryTranslationKeys[label];
  return key == null ? label : tr(key);
}

/// Formats an RM amount, showing decimals only when it actually has
/// cents — RM 1500 stays whole, RM 12.50 keeps its cents instead of
/// being silently rounded away to RM 13 by a flat `toStringAsFixed(0)`.
String formatAmount(double amount) {
  final rounded = double.parse(amount.toStringAsFixed(2));
  return rounded % 1 == 0
      ? rounded.toStringAsFixed(0)
      : rounded.toStringAsFixed(2);
}

/// Trip budget overview: total vs spent, category breakdown, and links
/// into expense tracking and splitting. Backed live by Supabase.
class BudgetPlannerScreen extends StatefulWidget {
  const BudgetPlannerScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<BudgetPlannerScreen> createState() => _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends State<BudgetPlannerScreen> {
  final _budgetService = BudgetService();
  final _tripService = TripService();
  final _groupService = GroupService();
  late final Future<(String, String, bool)> _tripFuture = _loadTrip();

  Future<(String, String, bool)> _loadTrip() async {
    final tripName = await _tripService.getTripName(widget.tripId);
    final isOrganizer = await _groupService.isOrganizer(widget.tripId);
    return (widget.tripId, tripName, isOrganizer);
  }

  Future<void> _editBudget(String tripId, double currentTotal) async {
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditBudgetSheet(initialAmount: currentTotal),
    );
    if (result == null) return;
    await _budgetService.setTotalBudget(tripId, result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: FutureBuilder<(String, String, bool)>(
          future: _tripFuture,
          builder: (context, tripSnap) {
            if (tripSnap.connectionState != ConnectionState.done) {
              return Column(
                children: [
                  DetailHeader(title: tr('budget_planner_title')),
                  const Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              );
            }
            if (tripSnap.hasError) {
              return Column(
                children: [
                  DetailHeader(title: tr('budget_planner_title')),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '${tripSnap.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            final (tripId, tripName, isOrganizer) = tripSnap.data!;
            return _BudgetPlannerContent(
              tripId: tripId,
              tripName: tripName,
              isOrganizer: isOrganizer,
              budgetService: _budgetService,
              onEditBudget: (currentTotal) => _editBudget(tripId, currentTotal),
            );
          },
        ),
      ),
    );
  }
}

class _BudgetPlannerContent extends StatelessWidget {
  const _BudgetPlannerContent({
    required this.tripId,
    required this.tripName,
    required this.isOrganizer,
    required this.budgetService,
    required this.onEditBudget,
  });

  final String tripId;
  final String tripName;
  final bool isOrganizer;
  final BudgetService budgetService;
  final ValueChanged<double> onEditBudget;

  Future<void> _manageCategories(
    BuildContext context,
    List<BudgetCategoryData> categories,
    double totalBudget,
  ) async {
    final plannedByLabel = {
      for (final c in categories) c.label: c.plannedAmount,
    };
    final result = await showModalBottomSheet<Map<String, double>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ManageCategoriesSheet(
        plannedByLabel: plannedByLabel,
        totalBudget: totalBudget,
      ),
    );
    if (result == null) return;
    await Future.wait([
      for (final entry in result.entries)
        budgetService.upsertCategory(
          tripId: tripId,
          label: entry.key,
          plannedAmount: entry.value,
        ),
    ]);
  }

  /// Tapping a single category row sets just that category's planned
  /// amount — quicker than opening the full "Plan Categories" sheet
  /// when you only want to fix up one category (e.g. Transport needs
  /// how much budget). Validated against [totalBudget] so the sum of
  /// every category's planned amount can never exceed it.
  Future<void> _editCategoryBudget(
    BuildContext context,
    String label,
    double currentPlanned,
    double totalBudget,
    Map<String, double> plannedByLabel,
  ) async {
    final otherCategoriesTotal = plannedByLabel.entries
        .where((e) => e.key != label)
        .fold<double>(0, (sum, e) => sum + e.value);
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => _CategoryBudgetDialog(
        label: label,
        initialAmount: currentPlanned,
        totalBudget: totalBudget,
        otherCategoriesTotal: otherCategoriesTotal,
      ),
    );
    if (result != null && result >= 0) {
      await budgetService.upsertCategory(
        tripId: tripId,
        label: label,
        plannedAmount: result,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: budgetService.watchTotalBudget(tripId),
      builder: (context, totalSnap) {
        final totalBudget = totalSnap.data ?? 0;
        return StreamBuilder<List<Expense>>(
          stream: budgetService.watchExpenses(tripId),
          builder: (context, expenseSnap) {
            final expenses = expenseSnap.data ?? const <Expense>[];
            final totalSpent = expenses.fold<double>(0, (s, e) => s + e.amount);
            final spentByCategory = <String, double>{};
            for (final e in expenses) {
              spentByCategory.update(
                e.category,
                (v) => v + e.amount,
                ifAbsent: () => e.amount,
              );
            }
            final ratio = totalBudget <= 0
                ? 0.0
                : (totalSpent / totalBudget).clamp(0.0, 1.0);

            return StreamBuilder<List<BudgetCategoryData>>(
              stream: budgetService.watchCategories(tripId),
              builder: (context, catSnap) {
                final plannedCategories =
                    catSnap.data ?? const <BudgetCategoryData>[];
                // Always show the default categories (so there's
                // somewhere to tap into and plan a budget for each one
                // before any spending happens), plus any category nobody
                // planned for but that already has real spending against
                // it — e.g. a custom "Other" category from the expense
                // form — so it doesn't silently vanish from the
                // breakdown.
                final plannedByLabel = {
                  for (final c in plannedCategories) c.label: c.plannedAmount,
                };
                final categoryLabels = {
                  for (final c in budgetCategories) c.label,
                  ...plannedByLabel.keys,
                  ...spentByCategory.keys,
                };

                return Column(
                  children: [
                    DetailHeader(
                      title: tr('budget_planner_title'),
                      subtitle: tripName,
                      trailing: IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExpenseSplitScreen(tripId: tripId),
                          ),
                        ),
                        icon: Icon(
                          Icons.call_split_rounded,
                          color: context.colors.ink,
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [
                          Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: AppColors.horizon,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.horizon.last.withValues(
                                    alpha: 0.3,
                                  ),
                                  blurRadius: 18,
                                  offset: Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tr('budget_total_budget'),
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (isOrganizer)
                                      Material(
                                        color: Colors.white.withValues(
                                          alpha: 0.18,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          onTap: () =>
                                              onEditBudget(totalBudget),
                                          child: Padding(
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              Icons.edit_rounded,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'RM ${formatAmount(totalBudget)}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 30,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 14),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 10,
                                    backgroundColor: Colors.white.withValues(
                                      alpha: 0.15,
                                    ),
                                    valueColor: AlwaysStoppedAnimation(
                                      AppColors.accent,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'RM ${formatAmount(totalSpent)} ${tr('budget_spent')} · '
                                  'RM ${formatAmount(totalBudget - totalSpent)} ${tr('budget_remaining')}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 24),
                          Row(
                            children: [
                              Text(
                                tr('budget_by_category'),
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                              Spacer(),
                              GestureDetector(
                                onTap: () => _manageCategories(
                                  context,
                                  plannedCategories,
                                  totalBudget,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 14),
                                  child: Icon(
                                    Icons.tune_rounded,
                                    size: 16,
                                    color: context.colors.muted,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        ExpenseTrackerScreen(tripId: tripId),
                                  ),
                                ),
                                child: Text(
                                  tr('budget_view_expenses'),
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 14),
                          ...categoryLabels.map((label) {
                            final visuals = categoryVisuals(label);
                            final planned = plannedByLabel[label] ?? 0;
                            final spent = spentByCategory[label] ?? 0;
                            // No planned amount to measure against but
                            // money was spent anyway — show the bar full
                            // rather than empty, since "0% of an unset
                            // budget" would read as no spending at all.
                            final r = planned <= 0
                                ? (spent > 0 ? 1.0 : 0.0)
                                : (spent / planned).clamp(0.0, 1.0);
                            return Material(
                              color: context.colors.card,
                              borderRadius: BorderRadius.circular(16),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () => _editCategoryBudget(
                                  context,
                                  label,
                                  planned,
                                  totalBudget,
                                  plannedByLabel,
                                ),
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 12),
                                  padding: EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: context.colors.ink.withValues(
                                          alpha: 0.05,
                                        ),
                                        blurRadius: 10,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            visuals.icon,
                                            color: visuals.color,
                                            size: 18,
                                          ),
                                          SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              translatedCategoryLabel(label),
                                              style: TextStyle(
                                                color: context.colors.ink,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            planned <= 0
                                                ? 'RM ${formatAmount(spent)} ${tr('budget_spent')} · ${tr('budget_no_budget_set')}'
                                                : 'RM ${formatAmount(spent)} / ${formatAmount(planned)}',
                                            style: TextStyle(
                                              color: context.colors.muted,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(width: 4),
                                          Icon(
                                            Icons.edit_rounded,
                                            size: 13,
                                            color: context.colors.muted,
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 10),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: r,
                                          minHeight: 6,
                                          backgroundColor:
                                              context.colors.surface,
                                          valueColor: AlwaysStoppedAnimation(
                                            visuals.color,
                                          ),
                                        ),
                                      ),
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
    );
  }
}

class _EditBudgetSheet extends StatefulWidget {
  const _EditBudgetSheet({required this.initialAmount});

  final double initialAmount;

  @override
  State<_EditBudgetSheet> createState() => _EditBudgetSheetState();
}

class _EditBudgetSheetState extends State<_EditBudgetSheet> {
  late final _controller = TextEditingController(
    text: formatAmount(widget.initialAmount),
  );

  double get _value => double.tryParse(_controller.text) ?? 0;

  void _adjust(double delta) {
    final next = (_value + delta).clamp(0, 999999).toDouble();
    setState(() => _controller.text = formatAmount(next));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('budget_edit_total_title'),
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('budget_edit_total_subtitle'),
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(),
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
                decoration: InputDecoration(
                  prefixText: 'RM ',
                  prefixStyle: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 24,
                  ),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: context.colors.ink,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdjustChip(label: '-RM50', onTap: () => _adjust(-50)),
                  _AdjustChip(label: '-RM10', onTap: () => _adjust(-10)),
                  _AdjustChip(label: '+RM10', onTap: () => _adjust(10)),
                  _AdjustChip(label: '+RM50', onTap: () => _adjust(50)),
                ],
              ),
              const SizedBox(height: 22),
              GradientButton(
                label: tr('budget_save_budget_button'),
                icon: Icons.check_rounded,
                onPressed: _value > 0
                    ? () => Navigator.of(context).pop(_value)
                    : () {},
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single-category planned-amount editor, opened by tapping a category
/// row. Validates that this category's amount plus every other
/// category's planned amount ([otherCategoriesTotal]) never exceeds
/// [totalBudget] — shows an inline error instead of saving when it would.
class _CategoryBudgetDialog extends StatefulWidget {
  const _CategoryBudgetDialog({
    required this.label,
    required this.initialAmount,
    required this.totalBudget,
    required this.otherCategoriesTotal,
  });

  final String label;
  final double initialAmount;
  final double totalBudget;
  final double otherCategoriesTotal;

  @override
  State<_CategoryBudgetDialog> createState() => _CategoryBudgetDialogState();
}

class _CategoryBudgetDialogState extends State<_CategoryBudgetDialog> {
  late final _controller = TextEditingController(
    text: widget.initialAmount > 0 ? formatAmount(widget.initialAmount) : '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim());
    if (value == null || value < 0) {
      setState(() => _error = tr('budget_enter_valid_amount'));
      return;
    }
    final remaining = widget.totalBudget - widget.otherCategoriesTotal;
    if (widget.totalBudget > 0 && value > remaining) {
      setState(() {
        _error =
            "${tr('budget_thats_word')} RM ${formatAmount(value - remaining)} "
            "${tr('budget_over_your_word')} RM ${formatAmount(widget.totalBudget)} "
            "${tr('budget_total_budget_suffix_word')} · "
            "RM ${formatAmount(remaining.clamp(0, double.infinity))} ${tr('budget_left_to_allocate')}";
      });
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        '${translatedCategoryLabel(widget.label)} ${tr('budget_category_budget_suffix')}',
        style: TextStyle(
          color: context.colors.ink,
          fontWeight: FontWeight.w800,
          fontSize: 15.5,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
            decoration: InputDecoration(
              prefixText: 'RM ',
              prefixStyle: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
              hintText: tr('budget_how_much_hint'),
              filled: true,
              fillColor: context.colors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('common_cancel')),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: context.colors.ink),
          child: Text(tr('common_save')),
        ),
      ],
    );
  }
}

/// Lets any trip member set how much they plan to spend in each of the
/// fixed [budgetCategories] — the planned side of the Budget Planner's
/// "By Category" breakdown. Open to every member (not just the
/// organizer), matching the `categories_write_members` RLS policy.
/// Validates that the categories never add up to more than [totalBudget].
class _ManageCategoriesSheet extends StatefulWidget {
  const _ManageCategoriesSheet({
    required this.plannedByLabel,
    required this.totalBudget,
  });

  final Map<String, double> plannedByLabel;
  final double totalBudget;

  @override
  State<_ManageCategoriesSheet> createState() => _ManageCategoriesSheetState();
}

class _ManageCategoriesSheetState extends State<_ManageCategoriesSheet> {
  late final _controllers = {
    for (final c in budgetCategories)
      c.label: TextEditingController(
        text: (widget.plannedByLabel[c.label] ?? 0) > 0
            ? formatAmount(widget.plannedByLabel[c.label]!)
            : '',
      ),
  };
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final result = {
      for (final entry in _controllers.entries)
        entry.key: double.tryParse(entry.value.text.trim()) ?? 0,
    };
    final sum = result.values.fold<double>(0, (s, v) => s + v);
    if (widget.totalBudget > 0 && sum > widget.totalBudget) {
      setState(() {
        _error =
            "${tr('budget_categories_add_up_to')} ${formatAmount(sum)}, "
            "${tr('budget_which_is_word')} RM ${formatAmount(sum - widget.totalBudget)} "
            "${tr('budget_over_your_word')} RM ${formatAmount(widget.totalBudget)} "
            "${tr('budget_total_budget_suffix_word')}";
      });
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('budget_plan_categories_title'),
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.totalBudget > 0
                    ? "${tr('budget_plan_categories_subtitle')} · "
                          "RM ${formatAmount(widget.totalBudget)} ${tr('budget_total_word')}"
                    : tr('budget_plan_categories_subtitle'),
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 18),
              ...budgetCategories.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(c.icon, color: c.color, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          translatedCategoryLabel(c.label),
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _controllers[c.label],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textAlign: TextAlign.end,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: InputDecoration(
                            prefixText: 'RM ',
                            hintText: '0',
                            filled: true,
                            fillColor: context.colors.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              GradientButton(
                label: tr('budget_save_categories_button'),
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdjustChip extends StatelessWidget {
  const _AdjustChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
