import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../services/trip_scheduler_service.dart';
import '../../utils/scheduling/place_identity.dart';

import '../../models/trip.dart';
import '../../models/trip_stop_location.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/scheduling/day_ordering.dart';
import '../../utils/scheduling/travel_matrix.dart';
import '../../utils/scheduling/trip_day.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/google_place_search_field.dart';
import '../../widgets/gradient_button.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Snapshot of a day's stop ids, in the order last considered
/// "optimized" (either freshly loaded, or after the most recent
/// automatic re-optimization) — [visits] then [unfitStops], matching
/// [DayOrderingResult]'s own field order, so a later manual drag can be
/// compared against it to detect a genuine override (spec's "override
/// planned order?" warning).
List<String?> _orderSnapshot(DayOrderingResult result) => [
  for (final v in result.visits) v.stop.id,
  for (final s in result.unfitStops) s.id,
];

bool _sameOrder(List<TripStopLocation> stops, List<String?> snapshot) {
  if (stops.length != snapshot.length) return false;
  for (var i = 0; i < stops.length; i++) {
    if (stops[i].id != snapshot[i]) return false;
  }
  return true;
}

/// The real, persisted-schedule editor for an existing trip (spec's
/// "Edit Schedule — Modify itinerary") — loads [tripId]'s stops and
/// saved `trip_schedule_stops` rows, rebuilds the same [TripDay]
/// structures [TripSchedulerService] works with, and lets the traveler
/// drag-reorder a day's stops or move one to a different day. Neither
/// action blindly trusts the traveler's exact request:
///  - A drag-reorder is re-simulated in that literal order
///    ([simulateFixedOrder]) rather than accepted as-is, so a sequence
///    that can't actually be kept (a stop ending up closed, or the day
///    running past its end time) is surfaced instead of silently saved
///    (spec §34).
///  - A move to another day removes the stop from its old day and adds
///    it to the new one, then fully re-optimizes *both* days
///    ([orderDay]) — the traveler chose which day, not where in it, so
///    a real search for the best position is appropriate there, unlike
///    a same-day drag where they *did* choose the exact order.
/// Changes are staged locally and only written back (via
/// [TripService.saveSchedule]/[TripService.deleteStop]) when the
/// traveler taps Save.
class RealEditScheduleView extends StatefulWidget {
  const RealEditScheduleView({super.key, required this.tripId});

  final String tripId;

  @override
  State<RealEditScheduleView> createState() => _RealEditScheduleViewState();
}

class _RealEditScheduleViewState extends State<RealEditScheduleView> {
  final _tripService = TripService();

  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _editing = false;
  final Map<String, TripStopLocation> _pendingAdditions = {};
  String _saveOperationId = const Uuid().v4();

  Trip? _trip;
  TravelMatrixSource? _travelMatrix;
  List<TripDay> _days = const [];
  Map<TripDay, DayOrderingResult> _orderings = {};

  /// Each day's stop-id order as of the last load or automatic
  /// re-optimization — compared against a fresh drag to detect a
  /// genuine manual override (see [_orderSnapshot]).
  Map<TripDay, List<String?>> _baseline = {};

  /// Days the traveler has already been warned about and accepted an
  /// override for, so dragging further within an already-overridden day
  /// doesn't re-prompt on every small move.
  final Set<TripDay> _overriddenDays = {};

  /// Stop ids to delete from `trip_stops` entirely on Save — removal is
  /// staged locally first, same as every other edit here.
  final Set<String> _pendingDeletions = {};

  int _selectedDay = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trip = await _tripService.getTrip(widget.tripId);
      final startDate = trip.startDate;
      final endDate = trip.endDate;
      if (startDate == null || endDate == null) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error =
              "This trip has no travel dates set, so there's no schedule to edit.";
        });
        return;
      }

      final allStops = await _tripService.getTripStops(widget.tripId);
      final accommodations = await _tripService.getAccommodations(
        widget.tripId,
      );
      final scheduleRows = await _tripService.getSchedule(widget.tripId);

      final stopsById = {
        for (final s in allStops)
          if (s.id != null) s.id!: s,
      };
      final accommodationByNight = {
        for (final a in accommodations) _dateOnly(a.nightDate): a.stop,
      };

      final days = buildTripDays(
        startDate: startDate,
        endDate: endDate,
        dailyStartTime: trip.startTime,
        dailyEndTime: trip.endTime,
        accommodationByNight: accommodationByNight,
        tripStartLocation: stopsById[trip.startLocationStopId],
        tripEndLocation: stopsById[trip.endLocationStopId],
      );
      if (days.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = "This trip's date range isn't valid, so it can't be edited.";
        });
        return;
      }

      final byDayNumber = <int, List<TripScheduleRow>>{};
      for (final row in scheduleRows) {
        byDayNumber.putIfAbsent(row.dayNumber, () => []).add(row);
      }
      for (var i = 0; i < days.length; i++) {
        final rows = byDayNumber[i + 1] ?? const [];
        days[i].assignedStops.addAll([for (final row in rows) row.stop]);
      }

      final travelMatrix = RouteServiceTravelMatrix(
        travelMode: TravelMode.fromDbValue(trip.transportMode),
      );
      final everyPoint = <TripStopLocation>{
        for (final day in days) ...[
          ...day.assignedStops,
          if (day.startAnchor != null) day.startAnchor!,
          if (day.endAnchor != null) day.endAnchor!,
        ],
      }.toList();
      await travelMatrix.precompute(everyPoint);

      final orderings = <TripDay, DayOrderingResult>{
        for (final day in days)
          day: await simulateFixedOrder(
            day,
            day.assignedStops,
            notBeforeByStopId: {
              for (final row
                  in byDayNumber[days.indexOf(day) + 1] ?? <TripScheduleRow>[])
                if (row.stop.id != null && row.scheduledVisitStart != null)
                  row.stop.id!: DateTime.parse(
                    '${day.date.toIso8601String().split('T').first}T${row.scheduledVisitStart}',
                  ),
            },
            travelMatrix: travelMatrix,
          ),
      };

      if (!mounted) return;
      setState(() {
        _trip = trip;
        _days = days;
        _travelMatrix = travelMatrix;
        _orderings = orderings;
        _baseline = {
          for (final day in days) day: _orderSnapshot(orderings[day]!),
        };
        _overriddenDays.clear();
        _pendingDeletions.clear();
        _pendingAdditions.clear();
        _saveOperationId = const Uuid().v4();
        _selectedDay = 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            'Could not load your itinerary. Check your connection and try again.';
      });
    }
  }

  Future<void> _edit(Future<void> Function() action) async {
    if (_saving || _editing) return;
    final stops = {
      for (final day in _days)
        day: List<TripStopLocation>.of(day.assignedStops),
    };
    final orderings = Map<TripDay, DayOrderingResult>.of(_orderings);
    setState(() => _editing = true);
    try {
      await action();
      _saveOperationId = const Uuid().v4();
    } catch (e) {
      for (final entry in stops.entries) {
        entry.key.assignedStops
          ..clear()
          ..addAll(entry.value);
      }
      _orderings = orderings;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  /// Simulated "today" within the trip (1-based) — days before this
  /// have already happened and are locked to view-only. A trip that
  /// hasn't started yet (or starts today) has nothing locked.
  int get _currentDay {
    final start = _trip?.startDate;
    if (start == null || _days.isEmpty) return 1;
    final today = DateTime.now();
    final elapsed = _dateOnly(today).difference(_dateOnly(start)).inDays;
    if (elapsed <= 0) return 1;
    return (elapsed + 1).clamp(1, _days.length);
  }

  bool _isDayLocked(int dayNumber) => dayNumber < _currentDay;

  /// [newIndex] arrives already adjusted for the removed item at
  /// [oldIndex] — `onReorderItem`'s contract, unlike the deprecated
  /// `onReorder` (which needs the caller to do that adjustment itself).
  Future<void> _reorder(TripDay day, int oldIndex, int newIndex) =>
      _edit(() => _reorderImpl(day, oldIndex, newIndex));

  Future<void> _reorderImpl(TripDay day, int oldIndex, int newIndex) async {
    final travelMatrix = _travelMatrix;
    if (travelMatrix == null) return;

    final result = _orderings[day]!;
    final visitOrder = [for (final v in result.visits) v.stop];
    final moved = visitOrder.removeAt(oldIndex);
    visitOrder.insert(newIndex, moved);
    // Still-unfit stops ride along at the end, unchanged relative order
    // — a reorder of the *feasible* stops may free up enough time for
    // one of these to fit after all.
    final candidateOrder = [...visitOrder, ...result.unfitStops];

    final simulated = await simulateFixedOrder(
      day,
      candidateOrder,
      travelMatrix: travelMatrix,
    );
    if (!mounted) return;

    final baseline = _baseline[day] ?? const [];
    final changedFromBaseline = !_sameOrder(candidateOrder, baseline);
    if (changedFromBaseline && !_overriddenDays.contains(day)) {
      final confirmed = await _confirmOverrideDialog(
        infeasible: simulated.unfitStops.isNotEmpty,
      );
      if (confirmed != true || !mounted) return;
      setState(() => _overriddenDays.add(day));
    }

    setState(() => _orderings = {..._orderings, day: simulated});
  }

  Future<bool?> _confirmOverrideDialog({required bool infeasible}) {
    final accent = infeasible ? Colors.redAccent : Colors.orangeAccent;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(Icons.warning_amber_rounded, color: accent),
        ),
        title: Text(
          infeasible ? "This order doesn't fit" : 'Override planned order?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: Text(
          infeasible
              ? "One or more stops can't be visited in this order — they'd "
                    "be closed, or the day would run past your end time. "
                    'Continuing marks those stops as not fitting this day '
                    "instead of forcing a plan that can't actually be kept."
              : 'Your stops were sequenced to minimize travel time. '
                    'Overriding the order may no longer be optimized and '
                    'could lead to a less enjoyable trip.',
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
            child: const Text('Keep Original Order'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: accent),
            child: Text(infeasible ? 'Apply Anyway' : 'Override Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetOrder(TripDay day) => _edit(() => _resetOrderImpl(day));

  Future<void> _resetOrderImpl(TripDay day) async {
    final travelMatrix = _travelMatrix;
    final baseline = _baseline[day];
    if (travelMatrix == null || baseline == null) return;
    final byId = {
      for (final s in day.assignedStops)
        if (s.id != null) s.id!: s,
    };
    final restored = [
      for (final id in baseline)
        if (id != null) byId[id],
    ].whereType<TripStopLocation>().toList();

    final simulated = await simulateFixedOrder(
      day,
      restored,
      travelMatrix: travelMatrix,
    );
    if (!mounted) return;
    setState(() {
      _orderings = {..._orderings, day: simulated};
      _overriddenDays.remove(day);
    });
  }

  Future<void> _moveStop(TripDay fromDay, TripStopLocation stop) =>
      _edit(() => _moveStopImpl(fromDay, stop));

  Future<void> _moveStopImpl(TripDay fromDay, TripStopLocation stop) async {
    final travelMatrix = _travelMatrix;
    if (travelMatrix == null) return;
    final fromIndex = _days.indexOf(fromDay);
    final targetIndex = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoveToDaySheet(
        dayCount: _days.length,
        currentDayIndex: fromIndex,
        isDayLocked: (i) => _isDayLocked(i + 1),
      ),
    );
    if (targetIndex == null || targetIndex == fromIndex || !mounted) return;
    final toDay = _days[targetIndex];

    fromDay.assignedStops.remove(stop);
    toDay.assignedStops.add(stop);

    final fromResult = await orderDay(fromDay, travelMatrix: travelMatrix);
    final toResult = await orderDay(toDay, travelMatrix: travelMatrix);
    if (!mounted) return;

    setState(() {
      _orderings = {..._orderings, fromDay: fromResult, toDay: toResult};
      _baseline = {
        ..._baseline,
        fromDay: _orderSnapshot(fromResult),
        toDay: _orderSnapshot(toResult),
      };
      _overriddenDays
        ..remove(fromDay)
        ..remove(toDay);
      _selectedDay = targetIndex + 1;
    });

    final stillDoesntFit = toResult.unfitStops.any((s) => s.id == stop.id);
    if (stillDoesntFit && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            "${stop.name} doesn't fit on Day ${targetIndex + 1} — try a "
            'different day or free up time there.',
          ),
        ),
      );
    }
  }

  /// Opens a real Google Places search and, if the traveler picks
  /// something, adds it to whichever day is currently selected (falling
  /// back to the trip's first still-editable day if that one's locked).
  /// Previously the only ways to add a stop to a trip were Create Trip
  /// (before it existed) or the AI Planner's own gap-recommendation
  /// flow — Edit Schedule itself had no add path at all.
  Future<void> _openAddStop() async {
    final picked = await showModalBottomSheet<TripStopLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddStopSheet(),
    );
    if (picked == null || !mounted) return;
    await _addStop(picked);
  }

  Future<void> _addStop(TripStopLocation stop) =>
      _edit(() => _addStopImpl(stop));

  Future<void> _addStopImpl(TripStopLocation stop) async {
    final travelMatrix = _travelMatrix;
    if (travelMatrix == null) return;

    final maxDay = _days.length;
    final selectedDayNumber = _selectedDay.clamp(1, maxDay);
    var targetDay = _days[selectedDayNumber - 1];
    if (_isDayLocked(selectedDayNumber)) {
      targetDay = _days[_currentDay - 1];
    }

    if (_days.any(
      (d) =>
          d.assignedStops.any((s) => placeIdentity(s) == placeIdentity(stop)),
    )) {
      throw StateError('This place is already on your itinerary.');
    }
    final savedStop = stop.copyWith(id: const Uuid().v4());
    final proposed = targetDay.copyWithStops([
      ...targetDay.assignedStops,
      savedStop,
    ]);
    final result = await orderDay(proposed, travelMatrix: travelMatrix);
    if (result.unfitStops.isNotEmpty || !result.endAnchorReachable) {
      throw StateError(
        'This stop does not fit without displacing another visit. '
        'Choose another day or free up time first.',
      );
    }
    if (!mounted) return;
    setState(() {
      targetDay.assignedStops.add(savedStop);
      _pendingAdditions[savedStop.id!] = savedStop;
      _orderings = {..._orderings, targetDay: result};
      _baseline = {..._baseline, targetDay: _orderSnapshot(result)};
      _overriddenDays.remove(targetDay);
      _selectedDay = _days.indexOf(targetDay) + 1;
    });
  }

  Future<void> _confirmRemoveStop(TripDay day, TripStopLocation stop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Remove this stop?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${stop.name}" will be removed from your trip entirely.',
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _removeStop(day, stop);
  }

  Future<void> _removeStop(TripDay day, TripStopLocation stop) =>
      _edit(() => _removeStopImpl(day, stop));

  Future<void> _removeStopImpl(TripDay day, TripStopLocation stop) async {
    final travelMatrix = _travelMatrix;
    if (travelMatrix == null) return;
    final result = _orderings[day]!;
    final remainingOrder = [
      for (final v in result.visits)
        if (v.stop != stop) v.stop,
      for (final s in result.unfitStops)
        if (s != stop) s,
    ];

    day.assignedStops.remove(stop);
    final simulated = await simulateFixedOrder(
      day,
      remainingOrder,
      travelMatrix: travelMatrix,
    );
    if (!mounted) return;
    setState(() {
      _orderings = {..._orderings, day: simulated};
      _baseline = {..._baseline, day: _orderSnapshot(simulated)};
      if (stop.id != null) {
        if (_pendingAdditions.remove(stop.id) == null) {
          _pendingDeletions.add(stop.id!);
        }
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _editing) return;
    if (_orderings.values.any(
      (o) => o.unfitStops.isNotEmpty || !o.endAnchorReachable,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Resolve the stops that do not fit and any missing end route before saving.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _tripService.saveSchedule(
        widget.tripId,
        buildScheduleRows([
          for (final day in _days) (day: day, ordering: _orderings[day]!),
        ], travelMode: _trip!.transportMode),
        expectedRevision: _trip!.scheduleRevision,
        operationId: _saveOperationId,
        newStops: _pendingAdditions.values.toList(),
        deletedStopIds: _pendingDeletions,
        days: buildScheduleDayRows([
          for (final day in _days) (day: day, ordering: _orderings[day]!),
        ]),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.ink,
          content: const Text('Schedule updated'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          content: Text('Could not save changes: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _editing || _saving,
          child: _buildBody(context),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Column(
        children: [
          const DetailHeader(
            title: 'Edit Trip',
            subtitle: 'Loading your schedule…',
          ),
          const Expanded(
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
            ),
          ),
        ],
      );
    }
    final error = _error;
    if (error != null) {
      return Column(
        children: [
          const DetailHeader(
            title: 'Edit Trip',
            subtitle: "Couldn't load your schedule",
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: context.colors.muted,
                      size: 28,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      error,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    final maxDay = _days.length;
    final selectedDayNumber = _selectedDay.clamp(1, maxDay);
    final day = _days[selectedDayNumber - 1];
    final locked = _isDayLocked(selectedDayNumber);
    final result = _orderings[day]!;
    final overridden = _overriddenDays.contains(day);

    return Column(
      children: [
        DetailHeader(
          title: 'Edit Trip',
          subtitle: locked
              ? 'Day $selectedDayNumber is already complete — view only'
              : 'Tap a stop to move or remove it, drag to reorder',
          trailing: IconButton(
            onPressed: _openAddStop,
            icon: Icon(Icons.add_rounded, color: context.colors.ink),
            tooltip: 'Add a stop',
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: List.generate(maxDay, (i) {
              final dayNumber = i + 1;
              final dayLocked = _isDayLocked(dayNumber);
              final active = dayNumber == selectedDayNumber;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedDay = dayNumber),
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
                          'Day $dayNumber',
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
        if (overridden && !locked)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: _OverrideBanner(onReset: () => _resetOrder(day)),
          ),
        Expanded(
          child: result.visits.isEmpty && result.unfitStops.isEmpty
              ? Center(
                  child: Text(
                    'No stops scheduled for Day $selectedDayNumber yet.',
                    style: TextStyle(color: context.colors.muted, fontSize: 13),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  children: [
                    if (locked)
                      for (var i = 0; i < result.visits.length; i++)
                        _VisitRow(
                          visit: result.visits[i],
                          isLast: i == result.visits.length - 1,
                          locked: true,
                        )
                    else
                      ReorderableListView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        onReorderItem: (oldIndex, newIndex) =>
                            _reorder(day, oldIndex, newIndex),
                        children: [
                          for (var i = 0; i < result.visits.length; i++)
                            _VisitRow(
                              key: ValueKey(result.visits[i].stop.id ?? i),
                              visit: result.visits[i],
                              isLast:
                                  i == result.visits.length - 1 &&
                                  result.unfitStops.isEmpty,
                              locked: false,
                              onMove: () =>
                                  _moveStop(day, result.visits[i].stop),
                              onDelete: () => _confirmRemoveStop(
                                day,
                                result.visits[i].stop,
                              ),
                            ),
                        ],
                      ),
                    if (result.unfitStops.isNotEmpty)
                      _UnfitSection(
                        stops: result.unfitStops,
                        locked: locked,
                        onMove: locked ? null : (stop) => _moveStop(day, stop),
                        onDelete: locked
                            ? null
                            : (stop) => _confirmRemoveStop(day, stop),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: GradientButton(
            label: 'Save Changes',
            icon: Icons.check_rounded,
            loading: _saving,
            onPressed: _saving ? () {} : _save,
          ),
        ),
      ],
    );
  }
}

/// One scheduled stop: icon + connecting line on the left, time and
/// name/address on the right — [ScheduledVisit]-backed equivalent of
/// the mock-mode `_StopTimelineRow`.
class _VisitRow extends StatelessWidget {
  const _VisitRow({
    super.key,
    required this.visit,
    required this.isLast,
    required this.locked,
    this.onMove,
    this.onDelete,
  });

  final ScheduledVisit visit;
  final bool isLast;
  final bool locked;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final stop = visit.stop;
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
                  gradient: locked
                      ? null
                      : const LinearGradient(colors: AppColors.horizon),
                  color: locked
                      ? context.colors.muted.withValues(alpha: 0.15)
                      : null,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  stop.categoryIcon,
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
                      if (visit.travelFromPrevious.inMinutes > 0)
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
                            '${visit.travelFromPrevious.inMinutes}m',
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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _content(context)),
                  if (!locked) ...[
                    IconButton(
                      onPressed: onMove,
                      icon: const Icon(Icons.calendar_month_rounded, size: 19),
                      tooltip: 'Move to another day',
                      color: context.colors.muted,
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
              '${formatClockTime(visit.visitStart)} – ${formatClockTime(visit.visitEnd)}',
              style: TextStyle(
                color: locked ? context.colors.muted : AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (locked) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                decoration: BoxDecoration(
                  color: context.colors.muted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'COMPLETED',
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Text(
          visit.stop.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: locked ? context.colors.muted : context.colors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        Text(
          visit.stop.address,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.colors.muted, fontSize: 11.5),
        ),
      ],
    );
  }
}

/// Stops assigned to this day that don't currently fit anywhere in it
/// (spec §33-34) — shown separately from the reorderable timeline above
/// since they have no feasible time slot to render into; each can still
/// be moved to a different day or removed.
class _UnfitSection extends StatelessWidget {
  const _UnfitSection({
    required this.stops,
    required this.locked,
    this.onMove,
    this.onDelete,
  });

  final List<TripStopLocation> stops;
  final bool locked;
  final ValueChanged<TripStopLocation>? onMove;
  final ValueChanged<TripStopLocation>? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
                size: 17,
              ),
              const SizedBox(width: 8),
              Text(
                "Doesn't fit this day",
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final stop in stops)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    stop.categoryIcon,
                    size: 16,
                    color: context.colors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stop.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  if (!locked) ...[
                    IconButton(
                      onPressed: () => onMove?.call(stop),
                      icon: const Icon(Icons.calendar_month_rounded, size: 18),
                      tooltip: 'Move to another day',
                      color: context.colors.muted,
                    ),
                    IconButton(
                      onPressed: () => onDelete?.call(stop),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Persistent warning shown once a day's visiting order no longer
/// matches the last-optimized sequence, with a one-tap way to undo it.
class _OverrideBanner extends StatelessWidget {
  const _OverrideBanner({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Custom order applied',
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'This sequence may not be optimized and could lead to a '
                  'worse experience.',
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onReset,
                  child: Text(
                    'Reset to optimized order',
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

/// Bottom sheet listing every day of the trip as a tappable tile —
/// returns the chosen day's 0-based index via `Navigator.pop`. The
/// stop's current day and any already-completed day are shown but not
/// selectable.
class _MoveToDaySheet extends StatelessWidget {
  const _MoveToDaySheet({
    required this.dayCount,
    required this.currentDayIndex,
    required this.isDayLocked,
  });

  final int dayCount;
  final int currentDayIndex;
  final bool Function(int dayIndex) isDayLocked;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Move to which day?',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: dayCount,
                itemBuilder: (context, i) {
                  final isCurrent = i == currentDayIndex;
                  final locked = isDayLocked(i);
                  final disabled = isCurrent || locked;
                  return ListTile(
                    enabled: !disabled,
                    leading: Icon(
                      locked
                          ? Icons.lock_rounded
                          : Icons.calendar_today_rounded,
                      size: 18,
                    ),
                    title: Text('Day ${i + 1}'),
                    subtitle: isCurrent
                        ? const Text('Current day')
                        : locked
                        ? const Text('Already complete')
                        : null,
                    onTap: disabled ? null : () => Navigator.of(context).pop(i),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet for adding a new stop to the trip — an unrestricted real
/// Google Places search (unlike the accommodation picker, which is
/// lodging-only), same visual pattern as Create Trip's own pickers.
/// Returns the picked [TripStopLocation] via `Navigator.pop`.
class _AddStopSheet extends StatelessWidget {
  const _AddStopSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxHeight: 420),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a Stop',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "Search for a place — we'll fit it into the selected day's "
                'schedule.',
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              GooglePlaceSearchField(
                hintText: 'Search for a place to add…',
                onChanged: (stop) => Navigator.of(context).pop(stop),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
