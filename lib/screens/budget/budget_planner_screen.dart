import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'expense_split_screen.dart';
import 'expense_tracker_screen.dart';

class BudgetCategory {
  BudgetCategory({
    required this.label,
    required this.icon,
    required this.color,
    required this.planned,
    required this.spent,
  });

  final String label;
  final IconData icon;
  final Color color;
  final double planned;
  final double spent;
}

final budgetCategories = [
  BudgetCategory(
    label: 'Accommodation',
    icon: Icons.hotel_rounded,
    color: Color(0xFF5C6BC0),
    planned: 600,
    spent: 600,
  ),
  BudgetCategory(
    label: 'Food & Drinks',
    icon: Icons.restaurant_rounded,
    color: AppColors.accent,
    planned: 350,
    spent: 268,
  ),
  BudgetCategory(
    label: 'Transport',
    icon: Icons.directions_bus_filled_rounded,
    color: Color(0xFF11998E),
    planned: 150,
    spent: 92,
  ),
  BudgetCategory(
    label: 'Shopping',
    icon: Icons.shopping_bag_rounded,
    color: Color(0xFFFFB347),
    planned: 300,
    spent: 145,
  ),
  BudgetCategory(
    label: 'Activities',
    icon: Icons.local_activity_rounded,
    color: Color(0xFF8E63CE),
    planned: 100,
    spent: 40,
  ),
];

/// Trip budget overview: total vs spent, category breakdown, and links
/// into expense tracking and splitting.
class BudgetPlannerScreen extends StatefulWidget {
  const BudgetPlannerScreen({super.key});

  @override
  State<BudgetPlannerScreen> createState() => _BudgetPlannerScreenState();
}

class _BudgetPlannerScreenState extends State<BudgetPlannerScreen> {
  late double _totalBudget = budgetCategories.fold<double>(
    0,
    (sum, c) => sum + c.planned,
  );

  Future<void> _editBudget() async {
    final result = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EditBudgetSheet(initialAmount: _totalBudget),
    );
    if (result == null) return;
    setState(() => _totalBudget = result);
  }

  @override
  Widget build(BuildContext context) {
    final totalSpent = budgetCategories.fold<double>(
      0,
      (sum, c) => sum + c.spent,
    );
    final ratio = _totalBudget <= 0
        ? 0.0
        : (totalSpent / _totalBudget).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Budget Planner',
              subtitle: 'Penang Adventure',
              trailing: IconButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => ExpenseSplitScreen())),
                icon: Icon(Icons.call_split_rounded, color: context.colors.ink),
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
                          color: AppColors.horizon.last.withValues(alpha: 0.3),
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
                                'Total Budget',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Material(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: _editBudget,
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
                          'RM ${_totalBudget.toStringAsFixed(0)}',
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
                          'RM ${totalSpent.toStringAsFixed(0)} spent · RM ${(_totalBudget - totalSpent).toStringAsFixed(0)} remaining',
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
                        'By Category',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ExpenseTrackerScreen(),
                          ),
                        ),
                        child: Text(
                          'View expenses',
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
                  ...budgetCategories.map((c) {
                    final r = (c.spent / c.planned).clamp(0.0, 1.0);
                    return Container(
                      margin: EdgeInsets.only(bottom: 12),
                      padding: EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.ink.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(c.icon, color: c.color, size: 18),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  c.label,
                                  style: TextStyle(
                                    color: context.colors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Text(
                                'RM ${c.spent.toStringAsFixed(0)} / ${c.planned.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: r,
                              minHeight: 6,
                              backgroundColor: context.colors.surface,
                              valueColor: AlwaysStoppedAnimation(c.color),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
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
    text: widget.initialAmount.toStringAsFixed(0),
  );

  double get _value => double.tryParse(_controller.text) ?? 0;

  void _adjust(double delta) {
    final next = (_value + delta).clamp(0, 999999).toDouble();
    setState(() => _controller.text = next.toStringAsFixed(0));
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
                'Edit Total Budget',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Set how much you plan to spend on this trip',
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
                label: 'Save Budget',
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
