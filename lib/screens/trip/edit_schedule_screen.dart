import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'stop_form_screen.dart';
import 'trip_data.dart';

/// UI-only trip editor, styled like the Daily Timeline: day tabs up top,
/// a vertical timeline of that day's stops below. Stops can be added,
/// edited, removed, and dragged to override the visiting order — except
/// on days before [_currentDay], which are already complete and shown
/// grayed out, view-only. The original order is treated as
/// route/weather-optimized, so overriding it (on editable days) prompts
/// a confirmation warning before the change is allowed to stick.
class EditScheduleScreen extends StatefulWidget {
  const EditScheduleScreen({super.key});

  @override
  State<EditScheduleScreen> createState() => _EditScheduleScreenState();
}

class _EditScheduleScreenState extends State<EditScheduleScreen> {
  /// Simulated "today" within the trip — days before this have already
  /// happened and are locked to view-only.
  static const _currentDay = 2;

  int _selectedDay = 1;

  final _items = [
    // Day 1
    TripStop(
      id: 1,
      name: 'Breakfast at Hotel',
      day: 1,
      time: const TimeOfDay(hour: 8, minute: 0),
      icon: Icons.free_breakfast_rounded,
      gradient: AppColors.sunset,
      duration: const Duration(minutes: 45),
    ),
    TripStop(
      id: 2,
      name: 'Komtar, George Town',
      day: 1,
      time: const TimeOfDay(hour: 10, minute: 0),
      icon: Icons.location_city_rounded,
      gradient: AppColors.horizon,
      duration: const Duration(hours: 2),
    ),
    TripStop(
      id: 3,
      name: 'Lunch at Komtar Food Court',
      day: 1,
      time: const TimeOfDay(hour: 13, minute: 0),
      icon: Icons.restaurant_rounded,
      gradient: AppColors.sunset,
      duration: const Duration(hours: 1),
    ),
    TripStop(
      id: 4,
      name: 'Back to Hotel',
      day: 1,
      time: const TimeOfDay(hour: 18, minute: 0),
      icon: Icons.hotel_rounded,
      gradient: AppColors.lagoon,
      duration: const Duration(minutes: 30),
    ),
    // Day 2
    TripStop(
      id: 5,
      name: 'Breakfast Nearby',
      day: 2,
      time: const TimeOfDay(hour: 9, minute: 30),
      icon: Icons.coffee_rounded,
      gradient: AppColors.sunset,
      duration: const Duration(minutes: 45),
    ),
    TripStop(
      id: 6,
      name: 'Gurney Drive & Plaza',
      day: 2,
      time: const TimeOfDay(hour: 13, minute: 0),
      icon: Icons.shopping_bag_rounded,
      gradient: AppColors.dusk,
      duration: const Duration(hours: 2, minutes: 30),
    ),
    TripStop(
      id: 7,
      name: 'Dinner at Gurney Food Stalls',
      day: 2,
      time: const TimeOfDay(hour: 18, minute: 30),
      icon: Icons.restaurant_rounded,
      gradient: AppColors.sunset,
      duration: const Duration(hours: 1),
    ),
    TripStop(
      id: 8,
      name: 'Back to Hotel',
      day: 2,
      time: const TimeOfDay(hour: 21, minute: 0),
      icon: Icons.hotel_rounded,
      gradient: AppColors.lagoon,
      duration: const Duration(minutes: 30),
    ),
    // Day 3
    TripStop(
      id: 9,
      name: 'Breakfast at Hotel',
      day: 3,
      time: const TimeOfDay(hour: 8, minute: 30),
      icon: Icons.free_breakfast_rounded,
      gradient: AppColors.sunset,
      duration: const Duration(minutes: 45),
    ),
    TripStop(
      id: 10,
      name: 'Queensbay Mall',
      day: 3,
      time: const TimeOfDay(hour: 16, minute: 0),
      icon: Icons.shopping_bag_rounded,
      gradient: AppColors.dusk,
      duration: const Duration(hours: 2),
    ),
    TripStop(
      id: 11,
      name: 'Head to Airport',
      day: 3,
      time: const TimeOfDay(hour: 20, minute: 0),
      icon: Icons.flight_takeoff_rounded,
      duration: const Duration(minutes: 30),
      gradient: AppColors.horizon,
    ),
  ];

  /// Snapshot of the original, optimized visiting order (by stop id) —
  /// used to detect when a drag-reorder has actually changed the
  /// sequence. Kept in sync whenever a stop is added or removed, so only
  /// genuine drag-reorders of the existing set count as an "override".
  late final List<int> _originalOrder = _items.map((i) => i.id).toList();

  /// Whether the user has already been warned and accepted the override
  /// for the current reordered sequence, so we don't re-prompt on every
  /// small drag while it's already in a non-original order.
  bool _orderOverridden = false;

  int get _maxDay =>
      _items.isEmpty ? 1 : _items.map((i) => i.day).reduce((a, b) => a > b ? a : b);

  bool _isDayLocked(int day) => day < _currentDay;

  /// Estimated transport time between two consecutive stops: the gap
  /// between when [current] ends (its start time plus how long the
  /// traveler stays) and when [next] begins.
  static int _transportMinutes(TripStop current, TripStop next) {
    final currentStart = current.time.hour * 60 + current.time.minute;
    final currentEnd = currentStart + current.duration.inMinutes;
    final nextStart = next.time.hour * 60 + next.time.minute;
    return (nextStart - currentEnd).clamp(0, 1 << 30);
  }

  bool get _isReordered {
    final currentIds = _items.map((i) => i.id).toList();
    if (currentIds.length != _originalOrder.length) return false;
    for (var i = 0; i < currentIds.length; i++) {
      if (currentIds[i] != _originalOrder[i]) return true;
    }
    return false;
  }

  Future<void> _reorder(int day, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final previousItems = List<TripStop>.from(_items);

    final dayIndices = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].day == day) i,
    ];
    final daySlice = [for (final i in dayIndices) _items[i]];
    final moved = daySlice.removeAt(oldIndex);
    daySlice.insert(newIndex, moved);

    setState(() {
      for (var i = 0; i < dayIndices.length; i++) {
        _items[dayIndices[i]] = daySlice[i];
      }
    });

    if (!_isReordered || _orderOverridden) return;

    final confirmed = await _confirmOverrideDialog();
    if (!mounted) return;
    if (confirmed == true) {
      setState(() => _orderOverridden = true);
    } else {
      // Revert — user chose to keep the original, optimized order.
      setState(() {
        _items
          ..clear()
          ..addAll(previousItems);
      });
    }
  }

  Future<bool?> _confirmOverrideDialog() {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.orangeAccent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
          ),
        ),
        title: Text(
          tr('trip_override_order_title'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: Text(
          tr('trip_override_order_body'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: dialogContext.colors.muted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('trip_keep_original_order')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orangeAccent.shade700,
            ),
            child: Text(tr('trip_override_anyway')),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddStop() async {
    final result = await Navigator.of(context).push<StopFormResult>(
      MaterialPageRoute(
        builder: (_) => StopFormScreen(
          dayCount: _maxDay,
          currentDay: _currentDay,
          preferredDay: _selectedDay,
          existingStops: _items,
        ),
      ),
    );
    if (result == null || result.stop == null) return;
    setState(() {
      _items.add(result.stop!);
      _originalOrder.add(result.stop!.id);
    });
  }

  Future<void> _openEditStop(int index) async {
    final result = await Navigator.of(context).push<StopFormResult>(
      MaterialPageRoute(
        builder: (_) => StopFormScreen(
          initial: _items[index],
          dayCount: _maxDay,
          currentDay: _currentDay,
          existingStops: _items,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.deleted) {
        final removedId = _items[index].id;
        _items.removeAt(index);
        _originalOrder.remove(removedId);
      } else if (result.stop != null) {
        _items[index] = result.stop!;
      }
    });
  }

  void _deleteStop(int index) {
    setState(() {
      _originalOrder.remove(_items[index].id);
      _items.removeAt(index);
    });
  }

  void _resetOrder() {
    setState(() {
      _items.sort(
        (a, b) => _originalOrder.indexOf(a.id).compareTo(_originalOrder.indexOf(b.id)),
      );
      _orderOverridden = false;
    });
  }

  void _save() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text(
          _isReordered
              ? tr('trip_updated_custom_order')
              : tr('trip_updated_snackbar'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reordered = _isReordered;
    final maxDay = _maxDay;
    final selectedDay = _selectedDay.clamp(1, maxDay);
    final locked = _isDayLocked(selectedDay);
    final dayIndices = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].day == selectedDay) i,
    ];

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('trip_edit_trip_title'),
              subtitle: locked
                  ? '${tr('trip_day_word')} $selectedDay ${tr('trip_day_locked_suffix')}'
                  : tr('trip_edit_schedule_subtitle'),
              trailing: IconButton(
                onPressed: locked ? null : _openAddStop,
                icon: Icon(
                  Icons.add_rounded,
                  color: locked
                      ? context.colors.muted.withValues(alpha: 0.4)
                      : context.colors.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(maxDay, (i) {
                  final day = i + 1;
                  final dayLocked = _isDayLocked(day);
                  final active = day == selectedDay;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedDay = day),
                      child: Container(
                        margin: EdgeInsets.only(right: i < maxDay - 1 ? 10 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: active
                              ? (dayLocked
                                    ? context.colors.ink.withValues(alpha: 0.5)
                                    : context.colors.ink)
                              : context.colors.card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (dayLocked) ...[
                              Icon(
                                Icons.lock_rounded,
                                size: 11,
                                color: active
                                    ? Colors.white70
                                    : context.colors.muted,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              '${tr('trip_day_word')} $day',
                              style: TextStyle(
                                color: active ? Colors.white : context.colors.ink,
                                fontWeight: FontWeight.w700,
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
            ),
            if (reordered && !locked)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: _OverrideBanner(onReset: _resetOrder),
              ),
            Expanded(
              child: dayIndices.isEmpty
                  ? Center(
                      child: Text(
                        '${tr('trip_no_stops_scheduled_prefix')} $selectedDay ${tr('trip_no_stops_scheduled_suffix')}',
                        style: TextStyle(color: context.colors.muted, fontSize: 13),
                      ),
                    )
                  : locked
                  ? ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      itemCount: dayIndices.length,
                      itemBuilder: (context, i) {
                        final isLast = i == dayIndices.length - 1;
                        return _StopTimelineRow(
                          stop: _items[dayIndices[i]],
                          isLast: isLast,
                          locked: true,
                          transportMinutes: isLast
                              ? null
                              : _transportMinutes(
                                  _items[dayIndices[i]],
                                  _items[dayIndices[i + 1]],
                                ),
                        );
                      },
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      itemCount: dayIndices.length,
                      onReorder: (oldIndex, newIndex) =>
                          _reorder(selectedDay, oldIndex, newIndex),
                      itemBuilder: (context, i) {
                        final absoluteIndex = dayIndices[i];
                        final item = _items[absoluteIndex];
                        final isLast = i == dayIndices.length - 1;
                        return _StopTimelineRow(
                          key: ValueKey(item.id),
                          stop: item,
                          isLast: isLast,
                          locked: false,
                          onTap: () => _openEditStop(absoluteIndex),
                          onDelete: () => _deleteStop(absoluteIndex),
                          transportMinutes: isLast
                              ? null
                              : _transportMinutes(
                                  item,
                                  _items[dayIndices[i + 1]],
                                ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: GradientButton(
                label: tr('trip_save_changes'),
                icon: Icons.check_rounded,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One stop on the timeline: icon + connecting line on the left, time
/// and name on the right. Editable stops are tappable with a delete
/// button and drag handle; locked (already-completed) stops render
/// grayed out with no interaction.
class _StopTimelineRow extends StatelessWidget {
  const _StopTimelineRow({
    super.key,
    required this.stop,
    required this.isLast,
    required this.locked,
    this.onTap,
    this.onDelete,
    this.transportMinutes,
  });

  final TripStop stop;
  final bool isLast;
  final bool locked;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  /// Estimated transport time to the next stop, shown inline on the
  /// connecting line. Null for the last stop of the day.
  final int? transportMinutes;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: locked ? null : LinearGradient(colors: stop.gradient),
                  color: locked ? context.colors.muted.withValues(alpha: 0.15) : null,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  stop.icon,
                  color: locked ? context.colors.muted : Colors.white,
                  size: 18,
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: context.colors.muted.withValues(alpha: 0.2),
                      ),
                      if (transportMinutes != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.surface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${transportMinutes}m',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 12 : 20),
              child: locked
                  ? _content(context)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: onTap,
                            child: _content(context),
                          ),
                        ),
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                        ),
                        Icon(
                          Icons.drag_handle_rounded,
                          color: context.colors.muted,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${stop.time.format(context)} · ${formatDuration(stop.duration)}',
              style: TextStyle(
                color: locked ? context.colors.muted : AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: context.colors.muted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tr('trip_completed_badge_caps'),
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 4),
              Icon(Icons.edit_rounded, size: 12, color: context.colors.muted),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          stop.name,
          style: TextStyle(
            color: locked ? context.colors.muted : context.colors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

/// Persistent warning shown once the visiting order no longer matches the
/// original optimized sequence, with a one-tap way to undo the override.
class _OverrideBanner extends StatelessWidget {
  const _OverrideBanner({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orangeAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Colors.orangeAccent.shade700,
            size: 18,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('trip_custom_order_applied'),
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  tr('trip_custom_order_desc'),
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 6),
                GestureDetector(
                  onTap: onReset,
                  child: Text(
                    tr('trip_reset_optimized_order'),
                    style: TextStyle(
                      color: Colors.orangeAccent.shade700,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
