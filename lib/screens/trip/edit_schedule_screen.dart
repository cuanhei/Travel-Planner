import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/place_environment.dart';
import '../../models/trip_schedule.dart';
import '../../models/trip_schedule_input.dart';
import '../../models/trip_stop_location.dart';
import '../../services/group_service.dart';
import '../../services/route_service.dart';
import '../../services/stop_weather_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/opening_hours_check.dart';
import '../../utils/weather_display.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/location_search_field.dart';

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

String _formatShortDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

int? _minutesFromTimeString(String? value) {
  if (value == null) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

String _minutesToClock(int minutesSinceMidnight) {
  final wrapped = minutesSinceMidnight % (24 * 60);
  final normalized = wrapped < 0 ? wrapped + 24 * 60 : wrapped;
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

String _durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}min';
  if (m == 0) return '${h}hr';
  return '${h}hr ${m}min';
}

bool _isPastDay(DateTime date) {
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  final dateOnly = DateTime(date.year, date.month, date.day);
  return dateOnly.isBefore(todayOnly);
}

class _EditStop {
  _EditStop(this.location, this.visitMinutes);
  final TripStopLocation location;
  int visitMinutes;
}

class _EditDay {
  _EditDay({
    required this.dayNumber,
    required this.date,
    required this.startTimeOverride,
    required this.stops,
    required this.legs,
    required this.originName,
    required this.originLat,
    required this.originLng,
  });

  final int dayNumber;
  final DateTime date;
  String? startTimeOverride;
  List<_EditStop> stops;
  List<TripScheduleLeg> legs;
  final String originName;
  final double originLat;
  final double originLng;
  bool dirty = false;

  bool get isPast => _isPastDay(date);
}

class EditScheduleScreen extends StatefulWidget {
  const EditScheduleScreen({super.key, required this.tripId, this.pendingStop});

  final String tripId;

  final TripStopLocation? pendingStop;

  @override
  State<EditScheduleScreen> createState() => _EditScheduleScreenState();
}

class _EditScheduleScreenState extends State<EditScheduleScreen> {
  final _tripService = TripService();
  final _groupService = GroupService();
  final _routeService = RouteService();
  final _stopWeatherService = StopWeatherService();

  bool _loading = true;
  String? _error;
  bool _isOrganizer = false;
  String? _tripStartTime;
  String _transportMode = 'driving';
  List<_EditDay> _days = [];
  int _selectedDay = 0;
  bool _saving = false;

  final Map<_EditStop, StopWeatherCheck?> _stopWeather = {};

  bool _pendingStopApplied = false;

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
      final organizer = await _groupService.isOrganizer(widget.tripId);
      final schedule = await _tripService.getTripSchedule(widget.tripId);
      if (!mounted) return;
      setState(() {
        _isOrganizer = organizer;
        _tripStartTime = schedule.tripStartTime;
        _transportMode = schedule.transportMode;
        _days = [for (final day in schedule.days) _toEditDay(day)];
        if (_selectedDay >= _days.length) _selectedDay = 0;
        _loading = false;
      });
      for (final day in _days) {
        if (!day.isPast) unawaited(_recheckWeatherForDay(day));
      }
      final pending = widget.pendingStop;
      if (pending != null && !_pendingStopApplied && _isOrganizer) {
        _pendingStopApplied = true;
        unawaited(_applyPendingStop(pending));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  _EditDay _toEditDay(TripScheduleDay day) {
    final legs = day.legs;
    final firstLeg = legs.isNotEmpty ? legs.first : null;
    return _EditDay(
      dayNumber: day.dayNumber,
      date: day.date,
      startTimeOverride: day.startTimeOverride,
      stops: [for (final s in day.stops) _EditStop(s.location, s.visitMinutes)],
      legs: [...legs],
      originName: firstLeg?.fromName ?? 'Starting point',
      originLat: firstLeg?.fromLatitude ?? 0,
      originLng: firstLeg?.fromLongitude ?? 0,
    );
  }

  int _dayStartMinutes(_EditDay day) =>
      _minutesFromTimeString(day.startTimeOverride) ??
      _minutesFromTimeString(_tripStartTime) ??
      8 * 60;

  ({List<int> arrivals, List<int> ends}) _computeTimes(_EditDay day) {
    var clock = _dayStartMinutes(day);
    final arrivals = <int>[];
    final ends = <int>[];
    for (var i = 0; i < day.stops.length; i++) {
      final travelMinutes = i < day.legs.length
          ? (day.legs[i].durationMinutes ?? 0)
          : 0;
      final arrival = clock + travelMinutes;
      final end = arrival + day.stops[i].visitMinutes;
      arrivals.add(arrival);
      ends.add(end);
      clock = end;
    }
    return (arrivals: arrivals, ends: ends);
  }

  int _lockedStopCount(_EditDay day) {
    if (day.isPast) return day.stops.length;
    final now = DateTime.now();
    final isToday =
        now.year == day.date.year &&
        now.month == day.date.month &&
        now.day == day.date.day;
    if (!isToday) return 0;
    final nowMinutes = now.hour * 60 + now.minute;
    final arrivals = _computeTimes(day).arrivals;
    var count = 0;
    for (var i = 0; i < arrivals.length; i++) {
      if (arrivals[i] > nowMinutes) break;
      count = i + 1;
    }
    return count;
  }

  Future<void> _addStop(_EditDay day) async {
    final picked = await showModalBottomSheet<TripStopLocation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddStopSheet(),
    );
    if (picked == null || !mounted) return;
    final added = await _appendLocation(day, picked);
    if (!mounted || added) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          '${picked.name} can\'t be added here — it would start after midnight (early next morning). Add it to a different day instead.',
        ),
      ),
    );
  }

  /// Appends [location] to the end of [day]'s stops, refetches its travel
  /// leg, and — once the real travel time is known — rejects it (removing
  /// what was just added) if it would arrive at or after that day's own
  /// midnight. A day's own tab is fixed to whichever calendar day it
  /// represents, so a stop that actually starts at 1am–3am the *next*
  /// morning must never sit under the wrong day's label. Returns whether
  /// the stop was actually kept.
  Future<bool> _appendLocation(_EditDay day, TripStopLocation location) async {
    final insertIndex = day.stops.length;
    setState(() {
      day.stops.add(_EditStop(location, location.estimatedVisitMinutes));
      day.legs.insert(
        insertIndex,
        TripScheduleLeg(
          sequence: insertIndex,
          fromName: '',
          fromLatitude: 0,
          fromLongitude: 0,
          toName: location.name,
          toLatitude: location.latitude,
          toLongitude: location.longitude,
          legKind: TripLegKind.stop,
          transportMode: _transportMode,
          durationMinutes: null,
        ),
      );
      day.dirty = true;
    });
    await _refetchLegsFrom(day, insertIndex);
    unawaited(_recheckWeatherForDay(day));
    if (!mounted) return false;

    final times = _computeTimes(day);
    if (insertIndex < times.arrivals.length &&
        times.arrivals[insertIndex] >= 24 * 60) {
      setState(() {
        day.stops.removeAt(insertIndex);
        day.legs.removeAt(insertIndex);
      });
      return false;
    }
    return true;
  }

  Future<void> _applyPendingStop(TripStopLocation location) async {
    final index = _days.indexWhere((d) => !d.isPast);
    if (index == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${location.name} wasn\'t added — this trip has no upcoming days left.',
          ),
        ),
      );
      return;
    }
    setState(() => _selectedDay = index);
    final added = await _appendLocation(_days[index], location);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          added
              ? '${location.name} added to Day ${_days[index].dayNumber} — tap Save to confirm.'
              : '${location.name} can\'t be added to Day ${_days[index].dayNumber} — it would start after midnight (early next morning).',
        ),
      ),
    );
  }

  Future<void> _recheckWeatherForDay(_EditDay day) async {
    if (!StopWeatherService.isWithinForecastWindow(day.date)) {
      setState(() {
        for (final stop in day.stops) {
          _stopWeather.remove(stop);
        }
      });
      return;
    }
    final times = _computeTimes(day);
    for (var i = 0; i < day.stops.length; i++) {
      final stop = day.stops[i];
      final env = stop.location.environment;
      if (env != PlaceEnvironment.outdoor && env != PlaceEnvironment.mixed) {
        setState(() => _stopWeather.remove(stop));
        continue;
      }
      if (!mounted) return;
      setState(() => _stopWeather[stop] = null);
      final result = await _stopWeatherService.check(
        position: LatLng(stop.location.latitude, stop.location.longitude),
        date: day.date,
        arrivalMinutes: times.arrivals[i],
        endMinutes: times.ends[i],
      );
      if (!mounted || !day.stops.contains(stop)) continue;
      setState(() => _stopWeather[stop] = result);
    }
  }

  void _removeStop(_EditDay day, int index) {
    setState(() {
      day.stops.removeAt(index);
      day.legs.removeAt(index);
      day.dirty = true;
    });
    unawaited(_refetchLegsFrom(day, index));
    unawaited(_recheckWeatherForDay(day));
  }

  void _reorderStop(_EditDay day, int oldIndex, int newIndex) {
    final locked = _lockedStopCount(day);
    if (oldIndex < locked) return;
    final target = newIndex < locked ? locked : newIndex;
    setState(() {
      final movedStop = day.stops.removeAt(oldIndex);
      day.stops.insert(target, movedStop);
      final movedLeg = day.legs.removeAt(oldIndex);
      day.legs.insert(target, movedLeg);
      day.dirty = true;
    });
    unawaited(_refetchLegsFrom(day, locked));
    unawaited(_recheckWeatherForDay(day));
  }

  Future<int?> _fetchLegDuration(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) async {
    try {
      final from = LatLng(fromLat, fromLng);
      final to = LatLng(toLat, toLng);
      if (_transportMode == 'transit') {
        final routes = await _routeService.getTransitRoutes(
          origin: from,
          destination: to,
        );
        return routes.isEmpty ? null : routes.first.duration.inMinutes;
      }
      final route = await _routeService.getDriveRoute(
        origin: from,
        destination: to,
      );
      return route?.duration.inMinutes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _refetchLegsFrom(_EditDay day, int fromIndex) async {
    var prevName = fromIndex == 0
        ? day.originName
        : day.stops[fromIndex - 1].location.name;
    var prevLat = fromIndex == 0
        ? day.originLat
        : day.stops[fromIndex - 1].location.latitude;
    var prevLng = fromIndex == 0
        ? day.originLng
        : day.stops[fromIndex - 1].location.longitude;

    for (var i = fromIndex; i < day.stops.length; i++) {
      final dest = day.stops[i].location;
      if (!mounted || i >= day.legs.length) return;
      setState(() {
        day.legs[i] = TripScheduleLeg(
          sequence: i,
          fromName: prevName,
          fromLatitude: prevLat,
          fromLongitude: prevLng,
          toName: dest.name,
          toLatitude: dest.latitude,
          toLongitude: dest.longitude,
          legKind: TripLegKind.stop,
          transportMode: _transportMode,
          durationMinutes: null,
        );
      });
      final duration = await _fetchLegDuration(
        prevLat,
        prevLng,
        dest.latitude,
        dest.longitude,
      );
      if (!mounted || i >= day.legs.length) return;
      setState(() {
        final l = day.legs[i];
        day.legs[i] = TripScheduleLeg(
          sequence: l.sequence,
          fromName: l.fromName,
          fromLatitude: l.fromLatitude,
          fromLongitude: l.fromLongitude,
          toName: l.toName,
          toLatitude: l.toLatitude,
          toLongitude: l.toLongitude,
          legKind: l.legKind,
          transportMode: l.transportMode,
          durationMinutes: duration,
        );
      });
      prevName = dest.name;
      prevLat = dest.latitude;
      prevLng = dest.longitude;
    }

    if (day.legs.length <= day.stops.length) return;
    final trailingIndex = day.legs.length - 1;
    final old = day.legs[trailingIndex];
    setState(() {
      day.legs[trailingIndex] = TripScheduleLeg(
        sequence: day.stops.length,
        fromName: prevName,
        fromLatitude: prevLat,
        fromLongitude: prevLng,
        toName: old.toName,
        toLatitude: old.toLatitude,
        toLongitude: old.toLongitude,
        legKind: old.legKind,
        transportMode: _transportMode,
        durationMinutes: null,
      );
    });
    final duration = await _fetchLegDuration(
      prevLat,
      prevLng,
      old.toLatitude,
      old.toLongitude,
    );
    if (!mounted) return;
    setState(() {
      final l = day.legs[trailingIndex];
      day.legs[trailingIndex] = TripScheduleLeg(
        sequence: l.sequence,
        fromName: l.fromName,
        fromLatitude: l.fromLatitude,
        fromLongitude: l.fromLongitude,
        toName: l.toName,
        toLatitude: l.toLatitude,
        toLongitude: l.toLongitude,
        legKind: l.legKind,
        transportMode: l.transportMode,
        durationMinutes: duration,
      );
    });
  }

  void _changeDuration(_EditDay day, int index, int delta) {
    final next = day.stops[index].visitMinutes + delta;
    if (next < 15) return;
    setState(() {
      day.stops[index].visitMinutes = next;
      day.dirty = true;
    });
    unawaited(_recheckWeatherForDay(day));
  }

  Future<void> _editStartTime(_EditDay day) async {
    final initial = TimeOfDay(
      hour: _dayStartMinutes(day) ~/ 60 % 24,
      minute: _dayStartMinutes(day) % 60,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;
    setState(() {
      day.startTimeOverride =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}:00';
      day.dirty = true;
    });
    unawaited(_recheckWeatherForDay(day));
  }

  Future<void> _save() async {
    final dirtyDays = _days.where((d) => d.dirty && !d.isPast).toList();
    if (dirtyDays.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final closedStops = <({int dayNumber, String name, String reason})>[];
    for (final day in dirtyDays) {
      final times = _computeTimes(day);
      for (var i = 0; i < day.stops.length; i++) {
        final location = day.stops[i].location;
        if (location.businessStatus == 'CLOSED_PERMANENTLY') {
          closedStops.add((
            dayNumber: day.dayNumber,
            name: location.name,
            reason: 'permanently closed',
          ));
          continue;
        }
        final isClosed = isClosedDuringVisit(
          periods: location.openingHoursPeriods,
          date: day.date,
          arrivalMinutes: times.arrivals[i],
          endMinutes: times.ends[i],
        );
        if (isClosed) {
          closedStops.add((
            dayNumber: day.dayNumber,
            name: location.name,
            reason: 'closed at the scheduled time',
          ));
        }
      }
    }
    if (closedStops.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Some places are closed'),
          content: Text(
            [
              'The following stops are closed — please arrange them to a '
                  'different day or time, or remove them:',
              '',
              for (final stop in closedStops)
                '• Day ${stop.dayNumber}: ${stop.name} (${stop.reason})',
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Go Back and Fix'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      for (final day in dirtyDays) {
        final times = _computeTimes(day);
        final stops = [
          for (var i = 0; i < day.stops.length; i++)
            TripStopInput(
              dayNumber: day.dayNumber,
              sequence: i,
              location: day.stops[i].location,
              visitMinutes: day.stops[i].visitMinutes,
              arrivalMinutes: times.arrivals[i],
              endMinutes: times.ends[i],
            ),
        ];
        final segments = [
          for (var i = 0; i < day.legs.length; i++)
            TripTravelSegmentInput(
              dayNumber: day.dayNumber,
              sequence: day.legs[i].sequence,
              fromName: day.legs[i].fromName,
              fromLatitude: day.legs[i].fromLatitude,
              fromLongitude: day.legs[i].fromLongitude,
              toName: day.legs[i].toName,
              toLatitude: day.legs[i].toLatitude,
              toLongitude: day.legs[i].toLongitude,
              legKind: day.legs[i].legKind,
              transportMode: day.legs[i].transportMode,
              durationMinutes: day.legs[i].durationMinutes,
            ),
        ];
        await _tripService.updateDaySchedule(
          tripId: widget.tripId,
          dayNumber: day.dayNumber,
          startTimeOverride: day.startTimeOverride,
          stops: stops,
          segments: segments,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not save changes: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyDirty = _days.any((d) => d.dirty);
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Edit Schedule',
              subtitle: 'Tap a stop to edit, only future days can change',
              trailing: !_loading && _isOrganizer
                  ? TextButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(anyDirty ? 'Save' : 'Done'),
                    )
                  : null,
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MessageState(
        icon: Icons.error_outline_rounded,
        title: 'Could not load the schedule',
        message: _error!,
        onRetry: _load,
      );
    }
    if (_days.isEmpty) {
      return const _MessageState(
        icon: Icons.event_busy_rounded,
        title: 'No saved schedule yet',
        message: 'This trip has no day-by-day timeline saved.',
      );
    }

    final day = _days[_selectedDay];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        if (!_isOrganizer)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only the trip organizer can edit the schedule. You can still view it below.',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        _DayTabBar(
          days: _days,
          selected: _selectedDay,
          onSelect: (i) => setState(() => _selectedDay = i),
        ),
        const SizedBox(height: 16),
        if (day.isPast) _PastDayNotice(day: day) else const SizedBox.shrink(),
        const SizedBox(height: 8),
        _DayEditCard(
          day: day,
          dayStartMinutes: _dayStartMinutes(day),
          editable: _isOrganizer && !day.isPast,
          lockedStopCount: _lockedStopCount(day),
          onEditStartTime: () => _editStartTime(day),
          onRemoveStop: (i) => _removeStop(day, i),
          onChangeDuration: (i, delta) => _changeDuration(day, i, delta),
          onReorderStop: (oldIndex, newIndex) =>
              _reorderStop(day, oldIndex, newIndex),
          onAddStop: () => _addStop(day),
          weatherFor: (stop) => _stopWeather[stop],
        ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: context.colors.muted, size: 32),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}

class _PastDayNotice extends StatelessWidget {
  const _PastDayNotice({required this.day});
  final _EditDay day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.muted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_rounded, color: context.colors.muted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Day ${day.dayNumber} has already happened — it can no longer be edited.',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayTabBar extends StatelessWidget {
  const _DayTabBar({
    required this.days,
    required this.selected,
    required this.onSelect,
  });

  final List<_EditDay> days;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = i == selected;
          final isPast = days[i].isPast;
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onSelect(i),
            child: Container(
              width: 84,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.accent : context.colors.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isPast) ...[
                        Icon(
                          Icons.lock_rounded,
                          size: 11,
                          color: isSelected
                              ? Colors.white
                              : context.colors.muted,
                        ),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        'Day ${days[i].dayNumber}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatShortDate(days[i].date),
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.9)
                          : context.colors.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DayEditCard extends StatelessWidget {
  const _DayEditCard({
    required this.day,
    required this.dayStartMinutes,
    required this.editable,
    required this.lockedStopCount,
    required this.onEditStartTime,
    required this.onRemoveStop,
    required this.onChangeDuration,
    required this.onReorderStop,
    required this.onAddStop,
    required this.weatherFor,
  });

  final _EditDay day;
  final int dayStartMinutes;
  final bool editable;

  final int lockedStopCount;

  final VoidCallback onEditStartTime;
  final void Function(int stopIndex) onRemoveStop;
  final void Function(int stopIndex, int deltaMinutes) onChangeDuration;
  final void Function(int oldIndex, int newIndex) onReorderStop;
  final VoidCallback onAddStop;

  final StopWeatherCheck? Function(_EditStop stop) weatherFor;

  @override
  Widget build(BuildContext context) {
    var clock = dayStartMinutes;
    final arrivals = <int>[];
    final ends = <int>[];
    for (var i = 0; i < day.stops.length; i++) {
      final travelMinutes = i < day.legs.length
          ? (day.legs[i].durationMinutes ?? 0)
          : 0;
      final arrival = clock + travelMinutes;
      final end = arrival + day.stops[i].visitMinutes;
      arrivals.add(arrival);
      ends.add(end);
      clock = end;
    }
    final trailingLeg = day.legs.length > day.stops.length
        ? day.legs.last
        : null;
    final canReorder = editable && day.stops.length > 1;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day ${day.dayNumber} — ${_formatShortDate(day.date)}',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          _OriginRow(
            time: _minutesToClock(dayStartMinutes),
            label: day.originName,
            onEditTime: editable ? onEditStartTime : null,
          ),
          if (day.stops.isNotEmpty)
            if (canReorder)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: day.stops.length,
                onReorderItem: onReorderStop,
                itemBuilder: (context, i) {
                  final locked = i < lockedStopCount;
                  return Column(
                    key: ValueKey(day.stops[i]),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (i < day.legs.length) _TravelRow(leg: day.legs[i]),
                      _StopRow(
                        stop: day.stops[i],
                        arrivalLabel: _minutesToClock(arrivals[i]),
                        endLabel: _minutesToClock(ends[i]),
                        editable: !locked,
                        dragHandleIndex: locked ? null : i,
                        closed: isClosedDuringVisit(
                          periods: day.stops[i].location.openingHoursPeriods,
                          date: day.date,
                          arrivalMinutes: arrivals[i],
                          endMinutes: ends[i],
                        ),
                        weather: weatherFor(day.stops[i]),
                        onRemove: () => onRemoveStop(i),
                        onChangeDuration: (delta) => onChangeDuration(i, delta),
                      ),
                    ],
                  );
                },
              )
            else
              for (var i = 0; i < day.stops.length; i++) ...[
                if (i < day.legs.length) _TravelRow(leg: day.legs[i]),
                _StopRow(
                  stop: day.stops[i],
                  arrivalLabel: _minutesToClock(arrivals[i]),
                  endLabel: _minutesToClock(ends[i]),
                  editable: editable && i >= lockedStopCount,
                  closed: isClosedDuringVisit(
                    periods: day.stops[i].location.openingHoursPeriods,
                    date: day.date,
                    arrivalMinutes: arrivals[i],
                    endMinutes: ends[i],
                  ),
                  weather: weatherFor(day.stops[i]),
                  onRemove: () => onRemoveStop(i),
                  onChangeDuration: (delta) => onChangeDuration(i, delta),
                ),
              ],
          if (trailingLeg != null) ...[
            _TravelRow(leg: trailingLeg),
            _TrailingRow(leg: trailingLeg),
          ],
          if (day.stops.isEmpty && trailingLeg == null) ...[
            const SizedBox(height: 8),
            Text(
              'No stops planned for this day.',
              style: TextStyle(
                color: context.colors.muted,
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (editable) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onAddStop,
              icon: const Icon(Icons.add_location_alt_rounded, size: 18),
              label: const Text('Add Stop'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddStopSheet extends StatelessWidget {
  const _AddStopSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.colors.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Add a Stop',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            LocationSearchField(
              value: null,
              onChanged: (location) {
                if (location != null) Navigator.of(context).pop(location);
              },
              hintText: 'Search a place to add',
            ),
          ],
        ),
      ),
    );
  }
}

class _OriginRow extends StatelessWidget {
  const _OriginRow({required this.time, required this.label, this.onEditTime});
  final String time;
  final String label;
  final VoidCallback? onEditTime;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            time,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Icon(
          Icons.flag_circle_rounded,
          color: AppColors.accent,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
        if (onEditTime != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onEditTime,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.edit_rounded,
                size: 15,
                color: context.colors.muted,
              ),
            ),
          ),
      ],
    );
  }
}

class _TravelRow extends StatelessWidget {
  const _TravelRow({required this.leg});
  final TripScheduleLeg leg;

  @override
  Widget build(BuildContext context) {
    final minutes = leg.durationMinutes;
    final label = minutes == null
        ? 'Travel time unavailable'
        : (minutes < 1 ? 'Travel < 1 min' : 'Travel $minutes min');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 52),
          const SizedBox(width: 10),
          Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 16,
            color: context.colors.muted,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopRow extends StatelessWidget {
  const _StopRow({
    required this.stop,
    required this.arrivalLabel,
    required this.endLabel,
    required this.editable,
    required this.closed,
    required this.weather,
    required this.onRemove,
    required this.onChangeDuration,
    this.dragHandleIndex,
  });

  final _EditStop stop;
  final String arrivalLabel;
  final String endLabel;
  final bool editable;

  final bool closed;

  final StopWeatherCheck? weather;

  final VoidCallback onRemove;
  final void Function(int deltaMinutes) onChangeDuration;

  final int? dragHandleIndex;

  @override
  Widget build(BuildContext context) {
    final location = stop.location;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            arrivalLabel,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        editable
            ? const Icon(Icons.trip_origin, color: AppColors.accent, size: 14)
            : Icon(Icons.lock_rounded, color: context.colors.muted, size: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dragHandleIndex != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ReorderableDragStartListener(
                          index: dragHandleIndex!,
                          child: Icon(
                            Icons.drag_indicator_rounded,
                            color: context.colors.muted,
                            size: 20,
                          ),
                        ),
                      ),
                    Icon(
                      location.categoryIcon,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        location.name,
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (editable)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onRemove,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 17,
                            color: Colors.red,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Visit: ${_durationLabel(stop.visitMinutes)} · Ends $endLabel',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    if (editable) ...[
                      _DurationStepper(
                        icon: Icons.remove_rounded,
                        onTap: () => onChangeDuration(-15),
                      ),
                      const SizedBox(width: 6),
                      _DurationStepper(
                        icon: Icons.add_rounded,
                        onTap: () => onChangeDuration(15),
                      ),
                    ],
                  ],
                ),
                if (location.businessStatus == 'CLOSED_PERMANENTLY')
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.block_rounded,
                          size: 14,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'This place is permanently closed — remove it or pick another.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (closed)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 14,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Closed at this time — try another day or time.',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (location.environment == PlaceEnvironment.outdoor ||
                    location.environment == PlaceEnvironment.mixed) ...[
                  const SizedBox(height: 6),
                  _StopWeatherRow(check: weather),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StopWeatherRow extends StatelessWidget {
  const _StopWeatherRow({required this.check});
  final StopWeatherCheck? check;

  @override
  Widget build(BuildContext context) {
    if (check == null || !check!.isResolved) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking current weather…',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      );
    }
    final phrase = check!.forecast!.summaryForecast;
    if (check!.isBad) {
      final periods = check!.badPeriods
          .map((p) => p.name)
          .map(_capitalize)
          .join(' & ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(weatherIconFor(phrase), size: 14, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Weather: ${translateWeather(phrase)}',
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (periods.isNotEmpty) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                'Rain is currently forecast in the $periods.',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(weatherIconFor(phrase), size: 14, color: context.colors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Weather: ${translateWeather(phrase)} — suitable',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: context.colors.ink),
      ),
    );
  }
}

class _TrailingRow extends StatelessWidget {
  const _TrailingRow({required this.leg});
  final TripScheduleLeg leg;

  @override
  Widget build(BuildContext context) {
    final isAccommodation = leg.legKind == TripLegKind.accommodation;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 52),
        const SizedBox(width: 10),
        Icon(
          isAccommodation ? Icons.hotel_rounded : Icons.flag_rounded,
          color: isAccommodation
              ? const Color(0xFF1E88E5)
              : const Color(0xFFE53935),
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            isAccommodation
                ? 'Stay — ${leg.toName}'
                : 'Trip Ends — ${leg.toName}',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
        ),
      ],
    );
  }
}
