import 'package:flutter/material.dart';

import '../../models/expense.dart';
import '../../services/budget_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'budget_pie_chart_screen.dart';
import 'budget_planner_screen.dart' show formatAmount;

class SpendingInsightsScreen extends StatelessWidget {
  const SpendingInsightsScreen({super.key, required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    final budgetService = BudgetService();

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: StreamBuilder<List<Expense>>(
          stream: budgetService.watchExpenses(tripId),
          builder: (context, snapshot) {
            final expenses = (snapshot.data ?? const <Expense>[])
                .where((e) => e.isShared)
                .toList();
            final total = expenses.fold<double>(0, (s, e) => s + e.amount);

            final byStop = <String, List<Expense>>{};
            for (final e in expenses) {
              if (e.stopPlace == null) continue;
              byStop.putIfAbsent(e.stopPlace!, () => []).add(e);
            }
            final stopTotals = {
              for (final entry in byStop.entries)
                entry.key: entry.value.fold<double>(0, (s, e) => s + e.amount),
            };
            final sortedStops = stopTotals.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            final untagged = expenses
                .where((e) => e.stopPlace == null)
                .toList();
            final untaggedTotal = untagged.fold<double>(
              0,
              (s, e) => s + e.amount,
            );

            return Column(
              children: [
                FutureBuilder<String>(
                  future: TripService().getTripName(tripId),
                  builder: (context, nameSnap) => DetailHeader(
                    title: 'Spending Insights',
                    subtitle: nameSnap.data,
                  ),
                ),
                Expanded(
                  child: expenses.isEmpty
                      ? Center(
                          child: Text(
                            'No expenses logged yet.',
                            style: TextStyle(color: context.colors.muted),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                          children: [
                            Material(
                              color: context.colors.card,
                              borderRadius: BorderRadius.circular(18),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => FutureBuilder<String>(
                                      future: TripService().getTripName(tripId),
                                      builder: (context, nameSnap) =>
                                          BudgetPieChartScreen(
                                            tripId: tripId,
                                            tripName: nameSnap.data ?? '',
                                          ),
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.pie_chart_rounded,
                                        color: AppColors.accent,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          'Spending by Category',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: context.colors.ink,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color: context.colors.muted,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'By Stop',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: context.colors.ink,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Where the money actually went, ranked',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 14),
                            if (sortedStops.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
                                child: Center(
                                  child: Text(
                                    'No expenses tagged with a stop yet.',
                                    style: TextStyle(
                                      color: context.colors.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ...sortedStops.map((entry) {
                              final count = byStop[entry.key]!.length;
                              final pct = total <= 0
                                  ? 0.0
                                  : entry.value / total * 100;
                              return _StopRow(
                                name: entry.key,
                                count: count,
                                amount: entry.value,
                                percent: pct,
                              );
                            }),
                            if (untagged.isNotEmpty)
                              _StopRow(
                                name: 'Not tagged to a stop',
                                count: untagged.length,
                                amount: untaggedTotal,
                                percent: total <= 0
                                    ? 0
                                    : untaggedTotal / total * 100,
                                muted: true,
                              ),
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

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.name,
    required this.count,
    required this.amount,
    required this.percent,
    this.muted = false,
  });

  final String name;
  final int count;
  final double amount;
  final double percent;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final accent = muted ? context.colors.muted : AppColors.accent;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.place_rounded, size: 16, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$count expense${count == 1 ? '' : 's'}',
                  style: TextStyle(color: context.colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'RM ${formatAmount(amount)}',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                '${percent.toStringAsFixed(0)}%',
                style: TextStyle(color: context.colors.muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
