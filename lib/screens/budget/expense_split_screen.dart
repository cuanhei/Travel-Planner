import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/trip_balance.dart';
import '../../services/budget_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Shows what each trip member paid (summed from their logged expenses)
/// and how much they owe the organizer — the owed amount is editable
/// by the organizer rather than an automatic even split.
class ExpenseSplitScreen extends StatefulWidget {
  const ExpenseSplitScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<ExpenseSplitScreen> createState() => _ExpenseSplitScreenState();
}

class _ExpenseSplitScreenState extends State<ExpenseSplitScreen> {
  final _budgetService = BudgetService();
  late Future<List<TripBalance>> _balancesFuture = _load();

  Future<List<TripBalance>> _load() => _budgetService.getBalances(widget.tripId);

  void _refresh() => setState(() => _balancesFuture = _load());

  Future<void> _editOwed(TripBalance traveler, String organizerFirstName) async {
    final controller = TextEditingController(
      text: traveler.owes.toStringAsFixed(2),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${traveler.displayName} owes $organizerFirstName',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
          decoration: InputDecoration(
            prefixText: 'RM ',
            prefixStyle: TextStyle(
              color: dialogContext.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
            filled: true,
            fillColor: dialogContext.colors.surface,
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(value);
            },
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.colors.ink,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result >= 0) {
      await _budgetService.setOwedAmount(
        tripId: widget.tripId,
        userId: traveler.userId,
        amount: result,
      );
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: FutureBuilder<List<TripBalance>>(
          future: _balancesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Column(
                children: [
                  DetailHeader(title: 'Split Expenses'),
                  Expanded(child: Center(child: CircularProgressIndicator())),
                ],
              );
            }
            final travelers = snapshot.data ?? const <TripBalance>[];
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

            final organizer = travelers.firstWhere(
              (t) => t.isOrganizer,
              orElse: () => travelers.first,
            );
            final canEdit = organizer.userId == myUid;
            final total = travelers.fold<double>(0, (sum, t) => sum + t.paid);
            final totalOwed = travelers
                .where((t) => !t.isOrganizer)
                .fold<double>(0, (sum, t) => sum + t.owes);

            return Column(
              children: [
                DetailHeader(
                  title: 'Split Expenses',
                  subtitle: 'Penang Adventure · ${travelers.length} travelers',
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
                              color: context.colors.ink.withValues(alpha: 0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Spent',
                                    style: TextStyle(
                                      color: context.colors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'RM ${total.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: context.colors.ink,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'Owed to ${organizer.displayName.split(' ').first}',
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'RM ${totalOwed.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 20,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text(
                            'Balances',
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          if (canEdit)
                            Text(
                              'Tap an amount to edit',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ...travelers.map((t) {
                        final settled = t.owes < 0.01;
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          t.displayName,
                                          style: TextStyle(
                                            color: context.colors.ink,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                        if (t.isOrganizer) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
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
                              if (t.isOrganizer)
                                Text(
                                  'Collects RM ${totalOwed.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Color(0xFF11998E),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                )
                              else if (canEdit)
                                Material(
                                  color: (settled
                                          ? const Color(0xFF11998E)
                                          : Colors.redAccent)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _editOwed(
                                      t,
                                      organizer.displayName.split(' ').first,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            settled
                                                ? 'Settled'
                                                : 'Owes RM ${t.owes.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: settled
                                                  ? const Color(0xFF11998E)
                                                  : Colors.redAccent,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.edit_rounded,
                                            size: 12,
                                            color: settled
                                                ? const Color(0xFF11998E)
                                                : Colors.redAccent,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              else
                                Text(
                                  settled
                                      ? 'Settled'
                                      : 'Owes RM ${t.owes.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    color: settled
                                        ? const Color(0xFF11998E)
                                        : Colors.redAccent,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
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
