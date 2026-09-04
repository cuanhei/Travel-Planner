import 'package:flutter/material.dart';

import '../../models/trip_stop_location.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show Place, places;
import 'location_map_picker.dart';
import 'stop_selection_screen.dart';
import 'trip_data.dart';

/// Result of [StopFormScreen]: either a saved (added/edited) stop, or a
/// request to delete the stop being edited.
class StopFormResult {
  const StopFormResult.save(TripStop savedStop)
    : stop = savedStop,
      deleted = false;
  const StopFormResult.delete() : stop = null, deleted = true;

  final TripStop? stop;
  final bool deleted;
}

enum _ArrangeMode { auto, manual }

/// UI-only form for adding a new trip stop or editing an existing one.
///
/// Adding mirrors the Create Trip flow: search or tap a pin on the
/// stylized map (or add a custom location) to pick the place, then
/// choose whether the system auto-arranges it into the itinerary or the
/// traveler sets the day and time manually. Editing keeps a simpler
/// name/day/time/category form. Either way, days that have already
/// passed can't be selected.
class StopFormScreen extends StatefulWidget {
  const StopFormScreen({
    super.key,
    this.initial,
    required this.dayCount,
    this.currentDay = 1,
    this.preferredDay,
    this.existingStops = const [],
  });

  /// Stop being edited, or null when adding a new one.
  final TripStop? initial;

  /// Highest day number currently in the schedule — bounds the day
  /// selector, since a new stop may start at most one day past the last.
  final int dayCount;

  /// The trip's current day (1-based). Days before this have already
  /// passed and can't be scheduled.
  final int currentDay;

  /// Day to preselect when adding — e.g. whichever day tab the traveler
  /// was viewing in Edit Schedule. Ignored when editing an existing stop.
  final int? preferredDay;

  /// The trip's other stops, used to render the "pick a time slot"
  /// timeline when arranging a new stop manually.
  final List<TripStop> existingStops;

  bool get isEditing => initial != null;

  @override
  State<StopFormScreen> createState() => _StopFormScreenState();
}

class _StopFormScreenState extends State<StopFormScreen> {
  // Edit mode only.
  late final _nameController = TextEditingController(
    text: widget.initial?.name ?? '',
  );
  late int _categoryIndex = widget.initial == null
      ? 0
      : stopCategories
            .indexWhere((c) => c.icon == widget.initial!.icon)
            .clamp(0, stopCategories.length - 1);

  // Add mode only.
  final _searchController = TextEditingController();
  String _query = '';
  Place? _selectedPlace;

  /// Real geocoded data behind [_selectedPlace] when it came from
  /// [StopSelectionScreen] — null for a catalog pick, which has no
  /// coordinates of its own.
  TripStopLocation? _selectedStopDetails;
  _ArrangeMode _arrangeMode = _ArrangeMode.auto;

  // Shared.
  late int _day = _clampToCurrentDay(
    widget.initial?.day ?? _defaultDay,
  );
  late TimeOfDay _time =
      widget.initial?.time ?? const TimeOfDay(hour: 10, minute: 0);
  late Duration _duration = widget.initial?.duration ?? const Duration(hours: 1);

  int get _defaultDay {
    if (widget.preferredDay != null) return _clampToCurrentDay(widget.preferredDay!);
    return widget.dayCount >= widget.currentDay ? widget.dayCount : widget.currentDay;
  }

  int _clampToCurrentDay(int day) =>
      day < widget.currentDay ? widget.currentDay : day;

  int get _maxDay =>
      (widget.dayCount + 1) > widget.currentDay
      ? widget.dayCount + 1
      : widget.currentDay;

  static int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  /// This day's other activities, earliest first, excluding the stop
  /// being edited — used by the "pick a time slot" list so the
  /// traveler can see the day at a glance and choose a slot instead of
  /// guessing an exact time.
  List<TripStop> get _daySchedule {
    final list = widget.existingStops
        .where((s) => s.day == _day && s.id != widget.initial?.id)
        .toList();
    list.sort((a, b) => _minutesOf(a.time).compareTo(_minutesOf(b.time)));
    return list;
  }

  void _pickSlot(TimeOfDay time) => setState(() => _time = time);

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      widget.isEditing ? _nameController.text.trim().isNotEmpty : _selectedPlace != null;

  void _togglePlace(Place place) {
    setState(() {
      _selectedPlace = _selectedPlace == place ? null : place;
      _selectedStopDetails = null;
    });
  }

  Future<void> _addCustomLocation() async {
    final result = await Navigator.of(context).push<List<TripStopLocation>>(
      MaterialPageRoute(builder: (_) => const StopSelectionScreen()),
    );
    if (result == null || result.isEmpty) return;
    final stop = result.last;
    setState(() {
      _selectedPlace = buildCustomPlace(stop.name);
      _selectedStopDetails = stop;
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    if (!_canSave) return;
    final TripStop stop;
    if (widget.isEditing) {
      final category = stopCategories[_categoryIndex];
      stop = TripStop(
        id: widget.initial!.id,
        name: _nameController.text.trim(),
        day: _day,
        time: _time,
        icon: category.icon,
        gradient: category.gradient,
        duration: _duration,
      );
    } else {
      final place = _selectedPlace!;
      final isAuto = _arrangeMode == _ArrangeMode.auto;
      stop = TripStop(
        id: DateTime.now().microsecondsSinceEpoch,
        name: place.name,
        day: isAuto ? _defaultDay : _day,
        time: isAuto ? const TimeOfDay(hour: 12, minute: 0) : _time,
        icon: place.icon,
        gradient: place.gradient,
        duration: _duration,
      );
    }
    Navigator.of(context).pop(StopFormResult.save(stop));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('trip_remove_stop_confirm_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${widget.initial!.name}" ${tr('trip_remove_stop_confirm_suffix')}',
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
            child: Text(tr('trip_remove_button')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const StopFormResult.delete());
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
              title: widget.isEditing
                  ? tr('trip_edit_stop_title')
                  : tr('trip_add_stop_title'),
              subtitle: widget.isEditing
                  ? tr('trip_edit_stop_subtitle')
                  : tr('trip_add_stop_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  ...widget.isEditing ? _editFields() : _addFields(),
                  const SizedBox(height: 36),
                  GradientButton(
                    label: widget.isEditing
                        ? tr('trip_save_changes')
                        : tr('trip_add_stop_title'),
                    icon: Icons.check_rounded,
                    onPressed: _canSave ? _save : () {},
                  ),
                  if (widget.isEditing) ...[
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
                          tr('trip_remove_stop_button'),
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _addFields() {
    final filtered = _query.isEmpty
        ? places
        : places
              .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();

    return [
      _FieldLabel(tr('trip_field_location')),
      _SearchBox(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 10),
      LocationMapPicker(
        selected: _selectedPlace == null ? const {} : {_selectedPlace!},
        onToggle: _togglePlace,
        onAddCustom: _addCustomLocation,
        visiblePlaces: filtered,
        showSearch: false,
      ),
      const SizedBox(height: 10),
      if (_selectedPlace == null)
        Builder(
          builder: (context) => Text(
            tr('trip_no_location_picked'),
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        )
      else
        _SelectedPlaceChip(
          place: _selectedPlace!,
          address: _selectedStopDetails == null
              ? null
              : '${_selectedStopDetails!.category} · ${_selectedStopDetails!.address}',
          icon: _selectedStopDetails?.categoryIcon,
          onRemove: () => setState(() {
            _selectedPlace = null;
            _selectedStopDetails = null;
          }),
        ),
      const SizedBox(height: 28),
      _FieldLabel(tr('trip_field_arrangement')),
      const SizedBox(height: 8),
      _ArrangeOption(
        title: tr('trip_auto_arrange_title'),
        description: tr('trip_auto_arrange_desc'),
        icon: Icons.auto_awesome_rounded,
        selected: _arrangeMode == _ArrangeMode.auto,
        onTap: () => setState(() => _arrangeMode = _ArrangeMode.auto),
      ),
      const SizedBox(height: 10),
      _ArrangeOption(
        title: tr('trip_arrange_manually_title'),
        description: tr('trip_arrange_manually_desc'),
        icon: Icons.tune_rounded,
        selected: _arrangeMode == _ArrangeMode.manual,
        onTap: () => setState(() => _arrangeMode = _ArrangeMode.manual),
      ),
      const SizedBox(height: 28),
      _FieldLabel(tr('trip_field_how_long')),
      const SizedBox(height: 4),
      _DurationSelector(
        duration: _duration,
        onChanged: (v) => setState(() => _duration = v),
      ),
      const SizedBox(height: 16),
      if (_arrangeMode == _ArrangeMode.auto)
        _AutoArrangePreview(day: _defaultDay)
      else ...[
        _FieldLabel(tr('trip_day_word')),
        _DaySelector(
          day: _day,
          currentDay: widget.currentDay,
          maxDay: _maxDay,
          onChanged: (v) => setState(() => _day = v),
        ),
        const SizedBox(height: 20),
        _FieldLabel(tr('trip_field_pick_time_slot')),
        const SizedBox(height: 4),
        _TimelineSlotPicker(
          day: _day,
          schedule: _daySchedule,
          selectedTime: _time,
          selectedDuration: _duration,
          onSelect: _pickSlot,
        ),
        const SizedBox(height: 20),
        _FieldLabel(tr('trip_field_time')),
        _TimeBox(time: _time, onTap: _pickTime),
      ],
    ];
  }

  List<Widget> _editFields() {
    return [
      _FieldLabel(tr('trip_field_place_name')),
      _InputBox(
        controller: _nameController,
        icon: Icons.place_rounded,
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 20),
      _FieldLabel(tr('trip_day_word')),
      _DaySelector(
        day: _day,
        currentDay: widget.currentDay,
        maxDay: _maxDay,
        onChanged: (v) => setState(() => _day = v),
      ),
      const SizedBox(height: 20),
      _FieldLabel(tr('trip_field_pick_time_slot')),
      const SizedBox(height: 4),
      _TimelineSlotPicker(
        day: _day,
        schedule: _daySchedule,
        selectedTime: _time,
        selectedDuration: _duration,
        onSelect: _pickSlot,
      ),
      const SizedBox(height: 20),
      _FieldLabel(tr('trip_field_time')),
      _TimeBox(time: _time, onTap: _pickTime),
      const SizedBox(height: 20),
      _FieldLabel(tr('trip_field_how_long')),
      const SizedBox(height: 4),
      _DurationSelector(
        duration: _duration,
        onChanged: (v) => setState(() => _duration = v),
      ),
      const SizedBox(height: 20),
      _FieldLabel(tr('trip_field_category')),
      const SizedBox(height: 4),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: List.generate(stopCategories.length, (i) {
          final category = stopCategories[i];
          final selected = i == _categoryIndex;
          return Builder(
            builder: (context) => GestureDetector(
              onTap: () => setState(() => _categoryIndex = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: selected ? context.colors.ink : context.colors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? context.colors.ink
                        : context.colors.muted.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      category.icon,
                      size: 14,
                      color: selected ? Colors.white : context.colors.muted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tr('trip_category_${category.label.toLowerCase()}'),
                      style: TextStyle(
                        color: selected ? Colors.white : context.colors.ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    ];
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
    this.onChanged,
  });

  final TextEditingController controller;
  final IconData icon;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: context.colors.muted, size: 20),
        filled: true,
        fillColor: context.colors.card,
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
        hintText: tr('trip_place_name_hint'),
        hintStyle: TextStyle(color: context.colors.muted),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: context.colors.muted, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(color: context.colors.ink, fontSize: 14),
              decoration: InputDecoration(
                hintText: tr('trip_search_places_hint'),
                hintStyle: TextStyle(color: context.colors.muted),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Icon(
                Icons.close_rounded,
                color: context.colors.muted,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

class _SelectedPlaceChip extends StatelessWidget {
  const _SelectedPlaceChip({
    required this.place,
    required this.onRemove,
    this.address,
    this.icon,
  });

  final Place place;
  final VoidCallback onRemove;

  /// Real address from Photon, when [place] came from
  /// [StopSelectionScreen] rather than the recommended-places catalog.
  final String? address;

  /// Category icon from [StopSelectionScreen]'s geocoded data, overriding
  /// [place]'s generic pin icon when available.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.only(left: 12, right: 6, top: 6, bottom: 6),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.muted.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? place.icon, size: 14, color: context.colors.ink),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place.name,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
                if (address != null)
                  Text(
                    address!,
                    style: TextStyle(color: context.colors.muted, fontSize: 10.5),
                  ),
              ],
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onRemove,
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: context.colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrangeOption extends StatelessWidget {
  const _ArrangeOption({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.1)
              : context.colors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppColors.accent
                : context.colors.muted.withValues(alpha: 0.2),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected ? AppColors.accent : context.colors.surface,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                color: selected ? Colors.white : context.colors.muted,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.accent : context.colors.muted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the selected day's existing stops as a mini timeline, with
/// tappable gaps before/between/after them so the traveler can drop the
/// new stop exactly where it belongs instead of guessing an exact time.
/// Lists the day's other activities so the traveler can pick a slot by
/// tapping one, instead of guessing an exact time — used by both the
/// add-stop and edit-stop flows.
/// Google Calendar–style day grid: hour gridlines down the left, the
/// day's other activities plotted as blocks at their scheduled time,
/// and an accent line marking the currently selected time. Tapping
/// anywhere on the grid (empty space or an existing block) sets the
/// time to that position, snapped to the nearest 15 minutes.
class _TimelineSlotPicker extends StatefulWidget {
  const _TimelineSlotPicker({
    required this.day,
    required this.schedule,
    required this.selectedTime,
    required this.selectedDuration,
    required this.onSelect,
  });

  final int day;
  final List<TripStop> schedule;
  final TimeOfDay selectedTime;
  final Duration selectedDuration;
  final ValueChanged<TimeOfDay> onSelect;

  @override
  State<_TimelineSlotPicker> createState() => _TimelineSlotPickerState();
}

class _TimelineSlotPickerState extends State<_TimelineSlotPicker> {
  static const _startHour = 6;
  static const _endHour = 24;
  static const _pxPerMinute = 1.0;
  static const _labelWidth = 42.0;
  static const _totalMinutes = (_endHour - _startHour) * 60;

  late final _scrollController = ScrollController(
    initialScrollOffset:
        (_minutesFromStart(widget.selectedTime) - 120).clamp(0, _totalMinutes.toDouble()),
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _minutesFromStart(TimeOfDay t) =>
      (((t.hour - _startHour) * 60 + t.minute).clamp(0, _totalMinutes)) * _pxPerMinute;

  TimeOfDay _timeFromOffset(double dy) {
    final clamped = dy.clamp(0, _totalMinutes - 1);
    final snapped = ((clamped / 15).round() * 15).toInt();
    return TimeOfDay(hour: _startHour + snapped ~/ 60, minute: snapped % 60);
  }

  String _hourLabel(int hour) {
    final normalized = hour % 24;
    final period = normalized < 12 ? 'AM' : 'PM';
    final display = normalized % 12 == 0 ? 12 : normalized % 12;
    return '$display $period';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) =>
                widget.onSelect(_timeFromOffset(details.localPosition.dy)),
            child: SizedBox(
              height: _totalMinutes * _pxPerMinute,
              child: Stack(
                children: [
                  for (var h = _startHour; h < _endHour; h++)
                    Positioned(
                      top: (h - _startHour) * 60 * _pxPerMinute,
                      left: 0,
                      right: 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _labelWidth,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8, top: 2),
                              child: Text(
                                _hourLabel(h),
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: context.colors.muted.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final stop in widget.schedule)
                    Positioned(
                      top: _minutesFromStart(stop.time) + 1,
                      left: _labelWidth + 6,
                      right: 6,
                      height: (stop.duration.inMinutes * _pxPerMinute).clamp(
                        26,
                        double.infinity,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: stop.gradient),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.topLeft,
                        child: Row(
                          children: [
                            Icon(stop.icon, color: Colors.white, size: 12),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                stop.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            Text(
                              '${stop.time.format(context)} · ${formatDuration(stop.duration)}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: Positioned(
                      top: _minutesFromStart(widget.selectedTime),
                      left: 0,
                      right: 0,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: _labelWidth,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                margin: const EdgeInsets.only(right: 4, top: 2),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  widget.selectedTime.format(context),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Container(
                              height: (widget.selectedDuration.inMinutes * _pxPerMinute)
                                  .clamp(20, double.infinity),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.22),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.accent, width: 1.5),
                              ),
                              alignment: Alignment.topLeft,
                              child: Text(
                                '${tr('trip_this_stop_label')} · ${formatDuration(widget.selectedDuration)}',
                                style: const TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Quick-pick chips for how long the traveler plans to stay at a stop.
class _DurationSelector extends StatelessWidget {
  const _DurationSelector({required this.duration, required this.onChanged});

  final Duration duration;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: stopDurationOptions.map((d) {
        final selected = d == duration;
        return GestureDetector(
          onTap: () => onChanged(d),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? context.colors.ink : context.colors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? context.colors.ink
                    : context.colors.muted.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              formatDuration(d),
              style: TextStyle(
                color: selected ? Colors.white : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AutoArrangePreview extends StatelessWidget {
  const _AutoArrangePreview({required this.day});

  final int day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.accent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${tr('trip_auto_arrange_preview_prefix')} $day, '
              '${tr('trip_auto_arrange_preview_suffix')}',
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({required this.time, required this.onTap});

  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule_rounded, color: context.colors.muted, size: 18),
            const SizedBox(width: 12),
            Text(
              time.format(context),
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

/// Day chip row for scheduling a stop. Days before [currentDay] have
/// already passed and are shown locked — tapping one explains why
/// instead of selecting it.
class _DaySelector extends StatelessWidget {
  const _DaySelector({
    required this.day,
    required this.currentDay,
    required this.maxDay,
    required this.onChanged,
  });

  final int day;
  final int currentDay;
  final int maxDay;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(maxDay, (i) {
            final d = i + 1;
            final passed = d < currentDay;
            final selected = d == day;
            return GestureDetector(
              onTap: passed
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: context.colors.ink,
                        content: Text(
                          '${tr('trip_day_word')} $d ${tr('trip_day_passed_snackbar_suffix')}',
                        ),
                      ),
                    )
                  : () => onChanged(d),
              child: Opacity(
                opacity: passed ? 0.45 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? context.colors.ink : context.colors.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? context.colors.ink
                          : context.colors.muted.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (passed) ...[
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: context.colors.muted,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        '${tr('trip_day_word')} $d',
                        style: TextStyle(
                          color: selected ? Colors.white : context.colors.ink,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          decoration: passed ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        if (currentDay > 1) ...[
          const SizedBox(height: 8),
          Text(
            currentDay > 2
                ? '${tr('trip_days_before_passed_prefix')} $currentDay '
                      '${tr('trip_days_before_passed_suffix')}'
                : tr('trip_day1_passed'),
            style: TextStyle(color: context.colors.muted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}
