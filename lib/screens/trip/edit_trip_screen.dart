import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../models/trip_stop_location.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/location_search_field.dart';

/// e.g. "Aug 14 – Aug 16, 2026".
String _formatDateRange(DateTimeRange range) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final start = range.start;
  final end = range.end;
  return '${months[start.month - 1]} ${start.day} – '
      '${months[end.month - 1]} ${end.day}, ${end.year}';
}

/// Trip editor for a trip's core details — name, description,
/// starting/ending location, and travel dates. Wired live to
/// [TripService.updateTrip]/[TripService.deleteTrip]; day-by-day stops
/// and timing are handled separately by Edit Schedule, and
/// budget/group-size tracking live in their own dedicated modules, so
/// none of that is duplicated here.
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
  late TripStopLocation? _startLocation = _locationFrom(
    name: widget.trip.startLocationName,
    address: widget.trip.startAddress,
    latitude: widget.trip.startLatitude,
    longitude: widget.trip.startLongitude,
  );
  late TripStopLocation? _endLocation = _locationFrom(
    name: widget.trip.endLocationName,
    address: widget.trip.endAddress,
    latitude: widget.trip.endLatitude,
    longitude: widget.trip.endLongitude,
  );
  late DateTimeRange? _dateRange =
      widget.trip.startDate != null && widget.trip.endDate != null
      ? DateTimeRange(start: widget.trip.startDate!, end: widget.trip.endDate!)
      : null;
  bool _saving = false;

  TripStopLocation? _locationFrom({
    required String? name,
    required String? address,
    required double? latitude,
    required double? longitude,
  }) {
    if (name == null || latitude == null || longitude == null) return null;
    return TripStopLocation(
      name: name,
      address: address ?? '',
      latitude: latitude,
      longitude: longitude,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
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
      await _tripService.updateTrip(
        tripId: widget.trip.id,
        name: name,
        description: _descriptionController.text.trim(),
        destination:
            _endLocation?.name ?? _startLocation?.name ?? widget.trip.destination,
        startLocationName: _startLocation?.name,
        startAddress: _startLocation?.address,
        startLatitude: _startLocation?.latitude,
        startLongitude: _startLocation?.longitude,
        endLocationName: _endLocation?.name,
        endAddress: _endLocation?.address,
        endLatitude: _endLocation?.latitude,
        endLongitude: _endLocation?.longitude,
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
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
              subtitle: "Update this trip's details",
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
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.flight_takeoff_rounded,
                    title: 'Travel Information',
                    children: [
                      _FieldLabel('Starting From'),
                      LocationSearchField(
                        value: _startLocation,
                        onChanged: (loc) =>
                            setState(() => _startLocation = loc),
                        hintText: 'Search for a starting location…',
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel('Ending At'),
                      LocationSearchField(
                        value: _endLocation,
                        onChanged: (loc) => setState(() => _endLocation = loc),
                        hintText: 'Search for an ending location…',
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel('Travel Dates'),
                      _DatePickerRow(
                        range: _dateRange,
                        onTap: _pickDateRange,
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

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({required this.range, required this.onTap});

  final DateTimeRange? range;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final range = this.range;
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
              range == null ? 'Select travel dates' : _formatDateRange(range),
              style: TextStyle(
                color: range == null
                    ? context.colors.muted
                    : context.colors.ink,
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
