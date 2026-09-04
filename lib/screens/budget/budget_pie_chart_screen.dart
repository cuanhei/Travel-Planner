import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/expense.dart';
import '../../services/budget_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'budget_planner_screen.dart' show categoryVisuals, formatAmount;

/// Where the trip's money actually went, visually — a donut chart of
/// spending by category (from logged expenses, not planned amounts),
/// with a legend listing each category's amount and share of the total.
/// Hovering (or tapping, on touch devices) a slice reveals its category
/// name on the chart itself; otherwise the ring stays clean and the
/// legend below is the readable source of truth.
class BudgetPieChartScreen extends StatefulWidget {
  const BudgetPieChartScreen({
    super.key,
    required this.tripId,
    required this.tripName,
  });

  final String tripId;
  final String tripName;

  @override
  State<BudgetPieChartScreen> createState() => _BudgetPieChartScreenState();
}

class _BudgetPieChartScreenState extends State<BudgetPieChartScreen> {
  final _budgetService = BudgetService();
  int _hoveredIndex = -1;

  static String _shortCategoryName(String category) {
    return category.length <= 18 ? category : '${category.substring(0, 17)}…';
  }

  PieChartSectionData _pieSection({
    required int index,
    required String category,
    required double value,
  }) {
    final hovered = index == _hoveredIndex;
    return PieChartSectionData(
      value: value,
      color: categoryVisuals(category).color,
      radius: hovered ? 78 : 72,
      showTitle: hovered,
      title: _shortCategoryName(category),
      titlePositionPercentageOffset: 0.62,
      titleStyle: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 12,
        shadows: [Shadow(color: Colors.black38, blurRadius: 3)],
      ),
      borderSide: BorderSide(color: context.colors.surface, width: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: StreamBuilder<List<Expense>>(
          stream: _budgetService.watchExpenses(widget.tripId),
          builder: (context, snapshot) {
            final expenses = snapshot.data ?? const <Expense>[];
            final byCategory = <String, double>{};
            for (final e in expenses) {
              byCategory.update(
                e.category,
                (v) => v + e.amount,
                ifAbsent: () => e.amount,
              );
            }
            final total = byCategory.values.fold<double>(0, (s, v) => s + v);
            final entries = byCategory.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return Column(
              children: [
                DetailHeader(
                  title: 'Spending by Category',
                  subtitle: widget.tripName,
                ),
                Expanded(
                  child: total <= 0
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'No expenses logged yet — the chart will fill\nin once spending starts.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: context.colors.muted),
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          children: [
                            SizedBox(
                              height: 280,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  PieChart(
                                    PieChartData(
                                      sections: [
                                        for (final (index, e) in entries.indexed)
                                          _pieSection(
                                            index: index,
                                            category: e.key,
                                            value: e.value,
                                          ),
                                      ],
                                      centerSpaceRadius: 58,
                                      sectionsSpace: 2,
                                      pieTouchData: PieTouchData(
                                        touchCallback: (event, response) {
                                          setState(() {
                                            final section =
                                                response?.touchedSection;
                                            _hoveredIndex =
                                                !event.isInterestedForInteractions ||
                                                    section == null
                                                ? -1
                                                : section.touchedSectionIndex;
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'RM ${formatAmount(total)}',
                                        style: TextStyle(
                                          color: context.colors.ink,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 20,
                                        ),
                                      ),
                                      Text(
                                        'total spent',
                                        style: TextStyle(
                                          color: context.colors.muted,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                            ...entries.map((entry) {
                              final visuals = categoryVisuals(entry.key);
                              final pct = entry.value / total * 100;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: visuals.color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Icon(
                                      visuals.icon,
                                      size: 15,
                                      color: visuals.color,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.colors.ink,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'RM ${formatAmount(entry.value)}',
                                      style: TextStyle(
                                        color: context.colors.muted,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 46,
                                      child: Text(
                                        '${pct.toStringAsFixed(0)}%',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                          color: context.colors.ink,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                        ),
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
            );
          },
        ),
      ),
    );
  }
}
