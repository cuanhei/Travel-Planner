import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

class _Traveler {
  _Traveler({
    required this.name,
    required this.color,
    required this.paid,
    required this.owes,
    this.isOrganizer = false,
  });

  final String name;
  final Color color;
  final double paid;

  /// How much this traveler owes the organizer — editable.
  double owes;
  final bool isOrganizer;
}

/// Shows what each traveler paid and how much they owe the trip
/// organizer — the owed amount is editable per traveler rather than an
/// automatic even split.
class ExpenseSplitScreen extends StatefulWidget {
  const ExpenseSplitScreen({super.key});

  @override
  State<ExpenseSplitScreen> createState() => _ExpenseSplitScreenState();
}

class _ExpenseSplitScreenState extends State<ExpenseSplitScreen> {
  final _travelers = [
    _Traveler(
      name: 'Alex Tan',
      color: AppColors.accent,
      paid: 820,
      owes: 0,
      isOrganizer: true,
    ),
    _Traveler(
      name: 'Mei Ling',
      color: const Color(0xFF5C6BC0),
      paid: 145,
      owes: 337.5,
    ),
    _Traveler(
      name: 'Arif Hakim',
      color: const Color(0xFF11998E),
      paid: 200,
      owes: 337.5,
    ),
  ];

  _Traveler get _organizer =>
      _travelers.firstWhere((t) => t.isOrganizer, orElse: () => _travelers.first);

  Future<void> _editOwed(_Traveler traveler) async {
    final controller = TextEditingController(
      text: traveler.owes.toStringAsFixed(2),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${traveler.name} ${tr('budget_owes')} ${_organizer.name}',
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
            child: Text(tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              Navigator.of(dialogContext).pop(value);
            },
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.colors.ink,
            ),
            child: Text(tr('common_save')),
          ),
        ],
      ),
    );
    if (result != null && result >= 0) {
      setState(() => traveler.owes = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _travelers.fold<double>(0, (sum, t) => sum + t.paid);
    final totalOwed = _travelers
        .where((t) => !t.isOrganizer)
        .fold<double>(0, (sum, t) => sum + t.owes);

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('budget_split_title'),
              subtitle:
                  'Penang Adventure · ${_travelers.length} ${tr('budget_travelers_label')}',
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
                                tr('budget_total_spent'),
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
                              '${tr('budget_owed_to')} ${_organizer.name.split(' ').first}',
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
                        tr('budget_balances'),
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        tr('budget_tap_to_edit'),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ..._travelers.map((t) {
                    final settled = t.owes < 0.01;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(18),
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
                            radius: 20,
                            backgroundColor: t.color,
                            child: Text(
                              t.name[0],
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
                                      t.name,
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
                                          color: AppColors.accent.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          tr('budget_organizer_badge'),
                                          style: const TextStyle(
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
                                  '${tr('budget_paid')} RM ${t.paid.toStringAsFixed(2)}',
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
                              '${tr('budget_collects')} RM ${totalOwed.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF11998E),
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            )
                          else
                            Material(
                              color: (settled
                                      ? const Color(0xFF11998E)
                                      : Colors.redAccent)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => _editOwed(t),
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
                                            ? tr('budget_settled')
                                            : '${tr('budget_owes_amount')} RM ${t.owes.toStringAsFixed(2)}',
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
