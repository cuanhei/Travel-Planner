import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/trip_balance.dart';
import '../../models/trip_settlement.dart';
import '../../services/budget_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

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

class _Settlement {
  const _Settlement({
    required this.from,
    required this.to,
    required this.amount,
  });

  final TripBalance from;
  final TripBalance to;
  final double amount;
}

const _settledThreshold = 0.01;

List<_Settlement> _computeSettlements(
  List<TripBalance> travelers,
  Map<String, double> netByUser,
) {
  if (travelers.length < 2) return const [];

  final creditors = <MapEntry<TripBalance, double>>[];
  final debtors = <MapEntry<TripBalance, double>>[];
  for (final t in travelers) {
    final net = netByUser[t.userId] ?? 0;
    if (net > _settledThreshold) {
      creditors.add(MapEntry(t, net));
    } else if (net < -_settledThreshold) {
      debtors.add(MapEntry(t, -net));
    }
  }
  creditors.sort((a, b) => b.value.compareTo(a.value));
  debtors.sort((a, b) => b.value.compareTo(a.value));

  final settlements = <_Settlement>[];
  var ci = 0;
  var di = 0;
  var creditorLeft = creditors.isEmpty ? 0.0 : creditors[0].value;
  var debtorLeft = debtors.isEmpty ? 0.0 : debtors[0].value;
  while (ci < creditors.length && di < debtors.length) {
    final amount = creditorLeft < debtorLeft ? creditorLeft : debtorLeft;
    if (amount > _settledThreshold) {
      settlements.add(
        _Settlement(
          from: debtors[di].key,
          to: creditors[ci].key,
          amount: amount,
        ),
      );
    }
    creditorLeft -= amount;
    debtorLeft -= amount;
    if (creditorLeft <= _settledThreshold) {
      ci++;
      if (ci < creditors.length) creditorLeft = creditors[ci].value;
    }
    if (debtorLeft <= _settledThreshold) {
      di++;
      if (di < debtors.length) debtorLeft = debtors[di].value;
    }
  }
  return settlements;
}

class ExpenseSplitScreen extends StatefulWidget {
  const ExpenseSplitScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<ExpenseSplitScreen> createState() => _ExpenseSplitScreenState();
}

class _ExpenseSplitScreenState extends State<ExpenseSplitScreen> {
  final _budgetService = BudgetService();
  late final Future<String> _tripNameFuture = TripService().getTripName(
    widget.tripId,
  );
  late final Future<List<TripBalance>> _balancesFuture = _budgetService
      .getBalances(widget.tripId);
  late final Future<double> _personalTotalFuture = _budgetService
      .getPersonalExpensesTotal(widget.tripId);

  final _myUid = Supabase.instance.client.auth.currentUser?.id;

  Future<void> _markSettled(_Settlement s) async {
    await _budgetService.recordSettlement(
      tripId: widget.tripId,
      fromUserId: s.from.userId,
      toUserId: s.to.userId,
      amount: s.amount,
    );
  }

  Future<void> _undoSettlement(TripSettlement s) async {
    await _budgetService.deleteSettlement(s.id, tripId: widget.tripId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: FutureBuilder<List<TripBalance>>(
          future: _balancesFuture,
          builder: (context, balanceSnap) {
            if (balanceSnap.connectionState != ConnectionState.done) {
              return const Column(
                children: [
                  DetailHeader(title: 'Split Expenses'),
                  Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              );
            }
            if (balanceSnap.hasError) {
              return Column(
                children: [
                  const DetailHeader(title: 'Split Expenses'),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Could not load trip members.\n${balanceSnap.error}',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.colors.muted),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }
            final travelers = balanceSnap.data ?? const <TripBalance>[];
            if (travelers.isEmpty) {
              return Column(
                children: [
                  const DetailHeader(title: 'Split Expenses'),
                  Expanded(
                    child: Center(
                      child: Text(
                        'No trip members yet.',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    ),
                  ),
                ],
              );
            }

            final total = travelers.fold<double>(0, (sum, t) => sum + t.paid);
            final fairShare = total / travelers.length;

            return StreamBuilder<List<TripSettlement>>(
              stream: _budgetService.watchSettlements(widget.tripId),
              builder: (context, settleSnap) {
                final settlements = settleSnap.data ?? const <TripSettlement>[];

                final netByUser = {
                  for (final t in travelers) t.userId: t.paid - fairShare,
                };
                for (final s in settlements) {
                  netByUser.update(
                    s.fromUserId,
                    (v) => v + s.amount,
                    ifAbsent: () => s.amount,
                  );
                  netByUser.update(
                    s.toUserId,
                    (v) => v - s.amount,
                    ifAbsent: () => -s.amount,
                  );
                }

                final pending = _computeSettlements(travelers, netByUser);

                return Column(
                  children: [
                    FutureBuilder<String>(
                      future: _tripNameFuture,
                      builder: (context, nameSnap) {
                        final tripName = nameSnap.data;
                        return DetailHeader(
                          title: 'Split Expenses',
                          subtitle: tripName == null
                              ? '${travelers.length} travelers'
                              : '$tripName · ${travelers.length} travelers',
                        );
                      },
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: context.colors.card,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: context.colors.ink.withValues(
                                    alpha: 0.05,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: _SplitStat(
                                    label: 'Total Spent',
                                    value: 'RM ${total.toStringAsFixed(2)}',
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 34,
                                  color: context.colors.surface,
                                ),
                                Expanded(
                                  child: _SplitStat(
                                    label: 'Fair Share Each',
                                    value: 'RM ${fairShare.toStringAsFixed(2)}',
                                    valueColor: AppColors.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          FutureBuilder<double>(
                            future: _personalTotalFuture,
                            builder: (context, personalSnap) {
                              final personalTotal = personalSnap.data ?? 0;
                              if (personalTotal <= 0) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'Your RM ${personalTotal.toStringAsFixed(2)} '
                                  "in personal expenses isn't included above "
                                  '— mark an expense "Split with group" in '
                                  'Expense Tracker to include it.',
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 11,
                                    height: 1.4,
                                  ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Who Paid',
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Split evenly across everyone below · tap Settle Up for who pays who',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          ...travelers.map((t) {
                            final net = netByUser[t.userId] ?? 0;
                            final isSettled = net.abs() < _settledThreshold;
                            final isCreditor = net > 0;
                            final badgeColor = isSettled
                                ? context.colors.muted
                                : isCreditor
                                ? const Color(0xFF11998E)
                                : Colors.redAccent;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(14),
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
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: Color(t.avatarColor),
                                    child: Text(
                                      t.displayName[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                t.displayName,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: context.colors.ink,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                            ),
                                            if (t.isOrganizer) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1.5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.accent
                                                      .withValues(alpha: 0.14),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'ORGANIZER',
                                                  style: TextStyle(
                                                    color: AppColors.accent,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0.3,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Paid RM ${t.paid.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            color: context.colors.muted,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      isSettled
                                          ? 'Settled'
                                          : isCreditor
                                          ? 'Gets back RM ${net.toStringAsFixed(2)}'
                                          : 'Owes RM ${net.abs().toStringAsFixed(2)}',
                                      style: TextStyle(
                                        color: badgeColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(
                                Icons.swap_horiz_rounded,
                                size: 16,
                                color: context.colors.ink,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Settle Up',
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pending.isEmpty
                                ? 'Nothing to settle — everyone paid their fair share.'
                                : 'Tap the check once a payment is actually made.',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          if (pending.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF11998E,
                                ).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF11998E),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "You're all settled up!",
                                      style: TextStyle(
                                        color: context.colors.ink,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            ...pending.map(
                              (s) => _PendingSettlementRow(
                                settlement: s,
                                onMarkSettled: () => _markSettled(s),
                              ),
                            ),
                          if (settlements.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            Text(
                              'Settled History',
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Payments already made — tap ↺ to undo a mistake.',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 14),
                            ...settlements.map((s) {
                              final from = travelers.firstWhere(
                                (t) => t.userId == s.fromUserId,
                                orElse: () => travelers.first,
                              );
                              final to = travelers.firstWhere(
                                (t) => t.userId == s.toUserId,
                                orElse: () => travelers.first,
                              );
                              final myself = travelers.firstWhere(
                                (t) => t.userId == _myUid,
                                orElse: () => travelers.first,
                              );
                              final canUndo =
                                  s.createdBy == _myUid || myself.isOrganizer;
                              return _SettledHistoryRow(
                                settlement: s,
                                fromName: from.displayName,
                                toName: to.displayName,
                                canUndo: canUndo,
                                onUndo: () => _undoSettlement(s),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PendingSettlementRow extends StatefulWidget {
  const _PendingSettlementRow({
    required this.settlement,
    required this.onMarkSettled,
  });

  final _Settlement settlement;
  final Future<void> Function() onMarkSettled;

  @override
  State<_PendingSettlementRow> createState() => _PendingSettlementRowState();
}

class _PendingSettlementRowState extends State<_PendingSettlementRow> {
  var _isSaving = false;

  Future<void> _handleTap() async {
    setState(() => _isSaving = true);
    try {
      await widget.onMarkSettled();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settlement;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
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
          CircleAvatar(
            radius: 15,
            backgroundColor: Color(s.from.avatarColor),
            child: Text(
              s.from.displayName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                children: [
                  TextSpan(text: s.from.displayName),
                  TextSpan(
                    text: ' pays ',
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(text: s.to.displayName),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            radius: 15,
            backgroundColor: Color(s.to.avatarColor),
            child: Text(
              s.to.displayName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'RM ${s.amount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(width: 8),
          _isSaving
              ? SizedBox(
                  width: 28,
                  height: 28,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.muted,
                    ),
                  ),
                )
              : Material(
                  color: const Color(0xFF11998E).withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _handleTap,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Color(0xFF11998E),
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _SettledHistoryRow extends StatelessWidget {
  const _SettledHistoryRow({
    required this.settlement,
    required this.fromName,
    required this.toName,
    required this.canUndo,
    required this.onUndo,
  });

  final TripSettlement settlement;
  final String fromName;
  final String toName;
  final bool canUndo;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF11998E).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.check_rounded,
              size: 15,
              color: Color(0xFF11998E),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$fromName paid $toName',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  _formatShortDate(settlement.createdAt),
                  style: TextStyle(color: context.colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            'RM ${settlement.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          if (canUndo) ...[
            const SizedBox(width: 8),
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onUndo,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.undo_rounded,
                    size: 16,
                    color: context.colors.muted,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SplitStat extends StatelessWidget {
  const _SplitStat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.colors.muted, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? context.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
      ],
    );
  }
}
