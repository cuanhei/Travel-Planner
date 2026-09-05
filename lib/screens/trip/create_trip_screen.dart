import 'package:flutter/material.dart';

import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

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

String _formatDate(DateTime d) =>
    '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

/// Minimal trip creation form: name + start/end date, with the day count
/// derived from the dates. The old location-picker/accommodation/budget
/// flow (and the algorithmic itinerary it fed into) has been removed —
/// this is a placeholder to rebuild a simplified Create Trip flow on top
/// of.
class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  // TODO: rebuild per simplified flow
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _tripService = TripService();

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Number of calendar days the trip spans, inclusive of both the start
  /// and end date — 0 while either date is unset.
  int get _dayCount {
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) return 0;
    return end.difference(start).inDays + 1;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      // Keep the end date valid (on/after the new start date).
      final end = _endDate;
      if (end != null && end.isBefore(picked)) _endDate = picked;
    });
  }

  Future<void> _pickEndDate() async {
    final start = _startDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? start,
      firstDate: start,
      lastDate: DateTime(DateTime.now().year + 3),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _submit() async {
    final formValid = _formKey.currentState?.validate() ?? false;
    if (!formValid) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Pick a start and end date.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _tripService.createTrip(
        name: _nameController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        totalBudget: 0,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not create trip: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Create Trip',
              subtitle: 'Name it and pick your dates',
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Text(
                      'Trip Name *',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: context.colors.ink,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. Penang Adventure',
                        hintStyle: TextStyle(
                          color: context.colors.muted,
                          fontWeight: FontWeight.w500,
                        ),
                        filled: true,
                        fillColor: context.colors.card,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 16,
                        ),
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Give your trip a name'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Start Date *',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DateField(
                      value: _startDate,
                      placeholder: 'Select start date',
                      onTap: _pickStartDate,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'End Date *',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DateField(
                      value: _endDate,
                      placeholder: 'Select end date',
                      onTap: _pickEndDate,
                    ),
                    const SizedBox(height: 16),
                    if (_dayCount > 0)
                      Text(
                        '$_dayCount day${_dayCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    const SizedBox(height: 32),
                    GradientButton(
                      label: 'Create Trip',
                      icon: Icons.route_rounded,
                      loading: _isSubmitting,
                      onPressed: _isSubmitting ? () {} : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  final DateTime? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final date = value;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.card,
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
            Expanded(
              child: Text(
                date == null ? placeholder : _formatDate(date),
                style: TextStyle(
                  color: date == null ? context.colors.muted : context.colors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.expand_more_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}
