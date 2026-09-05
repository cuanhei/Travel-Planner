import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

/// Trip editor for a trip's name and description only — starting/ending
/// location, dates, and day-by-day stops/timing are all set once at
/// Create Trip and aren't editable here; budget/group-size tracking live
/// in their own dedicated modules.
class EditTripScreen extends StatefulWidget {
  const EditTripScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<EditTripScreen> createState() => _EditTripScreenState();
}

class _EditTripScreenState extends State<EditTripScreen> {
  final _tripService = TripService();
  late final _nameController = TextEditingController(text: widget.trip.name);
  late final _descriptionController = TextEditingController(
    text: widget.trip.description ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.redAccent : context.colors.ink,
        content: Text(message),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Give your trip a name.', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final trip = widget.trip;
      // updateTrip sets every field it's given, rather than merging — so
      // everything set once at Create Trip and not editable here
      // (location/dates) is passed straight through unchanged.
      await _tripService.updateTrip(
        tripId: trip.id,
        name: name,
        description: _descriptionController.text.trim(),
        destination: trip.destination,
        startLocationName: trip.startLocationName,
        startAddress: trip.startAddress,
        startLatitude: trip.startLatitude,
        startLongitude: trip.startLongitude,
        endLocationName: trip.endLocationName,
        endAddress: trip.endAddress,
        endLatitude: trip.endLatitude,
        endLongitude: trip.endLongitude,
        startDate: trip.startDate,
        endDate: trip.endDate,
      );
    } catch (e) {
      debugPrint('Update trip failed: $e');
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('Could not save changes: $e', isError: true);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
    _showMessage('Trip updated');
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete this trip?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${_nameController.text.trim()}" and its entire itinerary will '
          'be permanently deleted.',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _tripService.deleteTrip(widget.trip.id);
    } catch (e) {
      debugPrint('Delete trip failed: $e');
      if (!mounted) return;
      _showMessage('Could not delete trip: $e', isError: true);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    _showMessage('Trip deleted');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Edit Trip',
              subtitle: 'Update the name and description',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _SectionCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Trip Details',
                    children: [
                      _FieldLabel('Trip Name'),
                      _InputBox(
                        controller: _nameController,
                        icon: Icons.edit_rounded,
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel('Description'),
                      _InputBox(
                        controller: _descriptionController,
                        icon: Icons.notes_rounded,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: 'Save Changes',
                    icon: Icons.check_rounded,
                    loading: _saving,
                    onPressed: _saving ? () {} : _save,
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton.icon(
                      onPressed: _saving ? null : _confirmDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      label: const Text(
                        'Delete Trip',
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
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final IconData icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
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
