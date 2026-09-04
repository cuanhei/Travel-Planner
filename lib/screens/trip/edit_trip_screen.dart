import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show categories;

/// UI-only trip editor for the trip's core details — same section
/// layout as Create Trip, but pre-filled and focused on editing rather
/// than planning a new itinerary. Day-by-day stops and timing are
/// handled separately by Edit Schedule, so they're not duplicated here.
class EditTripScreen extends StatefulWidget {
  const EditTripScreen({super.key});

  @override
  State<EditTripScreen> createState() => _EditTripScreenState();
}

class _EditTripScreenState extends State<EditTripScreen> {
  final _nameController = TextEditingController(text: 'Penang Adventure');
  final _descriptionController = TextEditingController(
    text: 'A 3-day getaway exploring George Town, Gurney Drive, and Queensbay.',
  );
  final _destinationController = TextEditingController(
    text: 'Penang, Malaysia',
  );
  final _budgetController = TextEditingController(text: 'RM 1,500');
  int _travelers = 2;
  final Set<String> _selectedInterests = {'Shopping', 'Food'};

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _destinationController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text(tr('trip_updated_snackbar')),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('trip_delete_trip_confirm_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${_nameController.text.trim()}" '
          '${tr('trip_delete_trip_confirm_body_suffix')}',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('trip_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(tr('trip_delete')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
          content: Text(tr('trip_deleted_snackbar')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('trip_edit_trip_title'),
              subtitle: tr('trip_edit_trip_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _SectionCard(
                    icon: Icons.edit_note_rounded,
                    title: tr('trip_section_trip_details'),
                    children: [
                      _FieldLabel(tr('trip_field_trip_name')),
                      _InputBox(
                        controller: _nameController,
                        icon: Icons.edit_rounded,
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_description')),
                      _InputBox(
                        controller: _descriptionController,
                        icon: Icons.notes_rounded,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.flight_takeoff_rounded,
                    title: tr('trip_section_logistics'),
                    children: [
                      _FieldLabel(tr('trip_field_destination')),
                      _InputBox(
                        controller: _destinationController,
                        icon: Icons.location_on_rounded,
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_travel_dates')),
                      _DatePickerRow(onTap: () {}),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_travelers')),
                      _TravelersStepper(
                        count: _travelers,
                        onChanged: (v) => setState(() => _travelers = v),
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_budget_word')),
                      _InputBox(
                        controller: _budgetController,
                        icon: Icons.account_balance_wallet_rounded,
                        keyboardType: TextInputType.text,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.interests_rounded,
                    title: tr('trip_field_interests'),
                    children: [
                      Text(
                        tr('trip_interests_hint'),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: categories.map((c) {
                          final selected = _selectedInterests.contains(
                            c.label,
                          );
                          return GestureDetector(
                            onTap: () => setState(() {
                              selected
                                  ? _selectedInterests.remove(c.label)
                                  : _selectedInterests.add(c.label);
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? context.colors.ink
                                    : context.colors.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected
                                      ? context.colors.ink
                                      : context.colors.muted.withValues(
                                          alpha: 0.25,
                                        ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    c.icon,
                                    size: 14,
                                    color: selected
                                        ? Colors.white
                                        : context.colors.muted,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    c.label,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : context.colors.ink,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: tr('trip_save_changes'),
                    icon: Icons.check_rounded,
                    onPressed: _save,
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed: _confirmDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      label: Text(
                        tr('trip_delete_trip_button'),
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        prefixIcon: maxLines == 1
            ? Icon(icon, color: context.colors.muted, size: 20)
            : null,
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.colors.ink, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: context.colors.muted,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              'Aug 14 — Aug 16, 2026',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(Icons.expand_more_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

class _TravelersStepper extends StatelessWidget {
  const _TravelersStepper({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.people_alt_rounded, color: context.colors.muted, size: 18),
          const SizedBox(width: 12),
          Text(
            '$count ${count == 1 ? tr('trip_traveler_singular') : tr('trip_traveler_plural')}',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _StepperButton(
            icon: Icons.remove_rounded,
            onTap: count > 1 ? () => onChanged(count - 1) : null,
          ),
          const SizedBox(width: 8),
          _StepperButton(
            icon: Icons.add_rounded,
            onTap: () => onChanged(count + 1),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? context.colors.muted.withValues(alpha: 0.4)
                : context.colors.ink,
          ),
        ),
      ),
    );
  }
}
