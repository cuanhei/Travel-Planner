import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nearby_place.dart';
import '../../models/place_environment.dart';
import '../../models/trip_schedule_input.dart';
import '../../models/trip_stop_location.dart';
import '../../services/google_places_service.dart';
import '../../models/weather_condition.dart' as weather_condition;
import '../../services/route_optimizer_service.dart';
import '../../services/route_service.dart';
import '../../services/stop_weather_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/weather_display.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/location_search_field.dart';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';
const _searchDebounce = Duration(milliseconds: 400);

String _formatDate(DateTime d) =>
    '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

String _formatShortDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

String _formatTimeOfDay(TimeOfDay? t) {
  if (t == null) return 'Select time';
  final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
  final minute = t.minute.toString().padLeft(2, '0');
  final period = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '$hour:$minute $period';
}

/// 24-hour "HH:mm" clock label for a minutes-since-midnight value, wrapping
/// at 24h (a day's plan can run past midnight; the timeline just keeps
/// counting rather than trying to represent a rollover to the next date).
String _minutesToClock(int minutesSinceMidnight) {
  final wrapped = minutesSinceMidnight % (24 * 60);
  final normalized = wrapped < 0 ? wrapped + 24 * 60 : wrapped;
  final h = (normalized ~/ 60).toString().padLeft(2, '0');
  final m = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

int _timeOfDayToMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

/// Walks a day's stops in order: each one's arrival is the running clock
/// plus its travel segment, its end is arrival plus its (editable) visit
/// duration, and that end becomes the running clock for the next stop.
/// Shared by the timeline UI and by the weather-recheck trigger, which
/// both need the same arrival/end minutes.
({List<int> arrivals, List<int> ends}) _computeDayTimes(
  int dayStartMinutes,
  List<_StopEntry> stops,
  List<_TravelSegment> travel,
) {
  var clock = dayStartMinutes;
  final arrivals = <int>[];
  final ends = <int>[];
  for (var i = 0; i < stops.length; i++) {
    final travelMinutes = i < travel.length ? (travel[i].duration?.inMinutes ?? 0) : 0;
    final arrival = clock + travelMinutes;
    final end = arrival + stops[i].visitMinutes;
    arrivals.add(arrival);
    ends.add(end);
    clock = end;
  }
  return (arrivals: arrivals, ends: ends);
}

/// How every travel leg in the timeline is computed — driving
/// ([RouteService.getDriveRoute]) or public transport
/// ([RouteService.getTransitRoutes], taking the first/most relevant
/// candidate's duration).
enum _TransportMode { driving, transit }

/// Peninsular Malaysia and East Malaysia (Sabah & Sarawak) have no road,
/// rail, or ferry link between them — only flights — so a trip can't mix
/// stops from both.
enum _MalaysiaRegion { peninsular, borneo }

/// Rough peninsular-vs-Borneo split by longitude — the South China Sea
/// separates them with no land from roughly 105°E to 108.5°E (Peninsular
/// Malaysia's easternmost point, Johor, sits under ~104.5°E; Sarawak's
/// westernmost, Sematan, sits over ~109.6°E), so a simple cutoff reliably
/// tells which side of the sea a point is on without needing reverse
/// geocoding.
_MalaysiaRegion _regionOf(TripStopLocation location) =>
    location.longitude >= 107 ? _MalaysiaRegion.borneo : _MalaysiaRegion.peninsular;

String _regionLabel(_MalaysiaRegion region) => region == _MalaysiaRegion.borneo
    ? 'East Malaysia (Sabah & Sarawak)'
    : 'Peninsular Malaysia';

/// A stop added to a specific trip day — the place data comes straight
/// from Google Places ([TripStopLocation.fromNearbyPlace]); [visitMinutes]
/// starts at the category-based estimate but the traveler can override it.
class _StopEntry {
  _StopEntry(this.location) : visitMinutes = location.estimatedVisitMinutes;

  final TripStopLocation location;
  int visitMinutes;
}

/// Drive-time estimate (Google Routes API, via [RouteService.getDriveRoute])
/// from whatever preceded a stop (the trip's starting location, the
/// previous night's accommodation, or the prior stop that day) to that
/// stop. Null [duration] while [loading]; [noOrigin] distinguishes "there
/// was nothing to route from yet" (e.g. Starting Location isn't set) from
/// an actual failed API call, since both otherwise show a null duration.
class _TravelSegment {
  _TravelSegment({this.loading = false, this.duration, this.noOrigin = false, this.stale = false});
  bool loading;
  Duration? duration;
  bool noOrigin;

  /// True right after a manual reorder invalidated the previously-fetched
  /// duration — distinct from an actual failed API call, since both
  /// otherwise show a null [duration].
  bool stale;
}

String _periodLabel(weather_condition.DayPeriod period) {
  switch (period) {
    case weather_condition.DayPeriod.morning:
      return 'Morning';
    case weather_condition.DayPeriod.afternoon:
      return 'Afternoon';
    case weather_condition.DayPeriod.night:
      return 'Night';
  }
}

String _environmentLabel(PlaceEnvironment env) {
  switch (env) {
    case PlaceEnvironment.indoor:
      return 'Indoor';
    case PlaceEnvironment.outdoor:
      return 'Outdoor';
    case PlaceEnvironment.mixed:
      return 'Indoor / Outdoor';
    case PlaceEnvironment.unknown:
      return 'Unknown';
  }
}

String _durationLabel(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}min';
  if (m == 0) return '${h}hr';
  return '${h}hr ${m}min';
}

String _travelLabel(_TravelSegment? segment) {
  if (segment == null) return 'Travel time unavailable';
  if (segment.loading) return 'Calculating travel…';
  if (segment.noOrigin) return 'Set a starting point above to calculate travel';
  if (segment.stale) return 'Travel time needs recalculating — tap Optimize';
  final duration = segment.duration;
  if (duration == null) return 'Travel time unavailable — route request failed';
  final minutes = duration.inMinutes;
  return minutes < 1 ? 'Travel < 1 min' : 'Travel ${duration.inMinutes} min';
}

/// Simplified Create Trip flow: a tab-based daily timeline planner.
///
/// Trip name/dates/starting location/per-night accommodation are set once
/// up top; the days in between are horizontally-scrollable tabs, each
/// showing a single vertical timeline built purely from the order stops
/// were added — no route optimization runs here. Adding a stop appends it
/// to the end of that day's timeline, resolves the correct origin (trip
/// starting location for Day 1's first stop, the previous night's
/// accommodation for a later day's first stop, otherwise the previous
/// stop), calls the Google Routes API for the travel ETA, then applies the
/// existing category-based visit-duration estimate to work out when the
/// stop ends — which is what the next stop's travel calculation starts
/// from.
class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tripService = TripService();
  final _placesService = GooglePlacesService();
  final _routeService = RouteService();
  final _stopWeatherService = StopWeatherService();
  final _routeOptimizerService = RouteOptimizerService();

  TripStopLocation? _startingLocation;
  TripStopLocation? _endingLocation;
  DateTime? _startDate;
  DateTime? _endDate;

  /// The time the traveler leaves the starting location on Day 1 — every
  /// later day's clock also starts here (leaving that night's
  /// accommodation), since there's no separate per-day departure field.
  /// Required — null until explicitly picked, so it can be validated like
  /// every other required field.
  TimeOfDay? _tripStartTime;

  /// Target time to reach [_endingLocation] (e.g. a flight's departure) —
  /// purely informational: the last day's timeline still ends whenever its
  /// stops actually finish, but a computed arrival later than this is
  /// flagged.
  TimeOfDay? _tripEndTime;

  bool _isSubmitting = false;

  /// True once the traveler has attempted to save — turns on the red
  /// required-field styling/captions across the form rather than showing
  /// them immediately on a blank page.
  bool _showValidation = false;

  int _selectedDay = 0;

  /// Per day: stops in add-order, and the travel segment arriving at each
  /// one (index-aligned 1:1 with the stops — segment 0 is the trip's
  /// starting location or the previous night's accommodation to stop 0,
  /// not "no travel").
  List<List<_StopEntry>> _dayStops = [];
  List<List<_TravelSegment>> _dayTravel = [];

  /// One pick per night between two trip days — index 0 is the night
  /// after Day 1 (i.e. Day 2's starting point), and so on. A trip
  /// spanning N days has N-1 nights.
  List<TripStopLocation?> _nightAccommodation = [];

  /// Travel segment from the last day's final stop (or its origin, if that
  /// day has no stops yet) to [_endingLocation] — the trip's very last
  /// leg, e.g. to the airport.
  _TravelSegment? _tripEndTravel;

  /// Travel segment from a day's current end (its last stop, or — when it
  /// has none yet — straight from its origin, e.g. the previous night's
  /// accommodation) to that same day's own accommodation. Index-aligned
  /// with [_nightAccommodation] (day `i`'s accommodation is night `i`).
  List<_TravelSegment?> _accommodationTravel = [];

  /// Per-day override of [_tripStartTime] — index 0 (Day 1) is never used,
  /// since Day 1 always starts at [_tripStartTime] itself; a later day
  /// falls back to [_tripStartTime] until the traveler edits it here.
  List<TimeOfDay?> _dayStartOverride = [];

  /// How every travel leg is computed — applies to the whole trip, not
  /// per-day. Switching it refetches every already-computed leg.
  _TransportMode _transportMode = _TransportMode.driving;

  /// Weather check for each outdoor/mixed stop's planned visit window,
  /// keyed by the stop's own identity (default `Object` equality, so each
  /// [_StopEntry] instance is its own key — stable across reorders since
  /// entries are moved, not recreated). Absent entirely for an indoor
  /// stop (never checked) or one not yet checked; null while a check is
  /// in flight.
  final Map<_StopEntry, StopWeatherCheck?> _stopWeather = {};

  /// Day indices currently running [_optimizeDay] — drives the "Optimize
  /// Day N" button's loading state and keeps it from being tapped twice
  /// concurrently for the same day.
  final Set<int> _optimizingDays = {};

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  int get _dayCount {
    final start = _startDate;
    final end = _endDate;
    if (start == null || end == null) return 0;
    return end.difference(start).inDays + 1;
  }

  List<DateTime> get _dayDates {
    final start = _startDate;
    final count = _dayCount;
    if (start == null || count <= 0) return const [];
    return [for (var i = 0; i < count; i++) start.add(Duration(days: i))];
  }

  /// Resizes the per-day/per-night lists to match [_dayCount], preserving
  /// already-added stops/accommodations on days/nights that still exist.
  void _syncDays() {
    final count = _dayCount;
    _dayStops = List.generate(
      count,
      (i) => i < _dayStops.length ? _dayStops[i] : <_StopEntry>[],
    );
    _dayTravel = List.generate(
      count,
      (i) => i < _dayTravel.length ? _dayTravel[i] : <_TravelSegment>[],
    );
    final nights = count == 0 ? 0 : count - 1;
    _nightAccommodation = List.generate(
      nights,
      (i) => i < _nightAccommodation.length ? _nightAccommodation[i] : null,
    );
    _accommodationTravel = List.generate(
      nights,
      (i) => i < _accommodationTravel.length ? _accommodationTravel[i] : null,
    );
    _dayStartOverride = List.generate(
      count,
      (i) => i < _dayStartOverride.length ? _dayStartOverride[i] : null,
    );
    if (_selectedDay >= count) _selectedDay = count == 0 ? 0 : count - 1;
  }

  /// The effective start-of-day clock for [dayIndex] — [_tripStartTime]
  /// for Day 1 always, and for any later day too until the traveler picks
  /// a different time for it via [_pickDayStartOverride].
  int _dayStartMinutesFor(int dayIndex) {
    final time = dayIndex == 0
        ? _tripStartTime
        : (dayIndex < _dayStartOverride.length ? _dayStartOverride[dayIndex] : null) ?? _tripStartTime;
    return _timeOfDayToMinutes(time ?? const TimeOfDay(hour: 8, minute: 0));
  }

  Future<void> _pickDayStartOverride(int dayIndex) async {
    final current = (dayIndex < _dayStartOverride.length ? _dayStartOverride[dayIndex] : null) ??
        _tripStartTime ??
        const TimeOfDay(hour: 8, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: current);
    if (picked == null) return;
    setState(() => _dayStartOverride[dayIndex] = picked);
    unawaited(_recheckWeatherForDay(dayIndex));
  }

  /// Travel duration between two points, per the current [_transportMode]
  /// — driving via [RouteService.getDriveRoute], or transit via
  /// [RouteService.getTransitRoutes] (taking the first/most relevant
  /// candidate). Null if the mode has no route between them.
  Future<Duration?> _fetchDuration(TripStopLocation origin, TripStopLocation destination) async {
    final from = LatLng(origin.latitude, origin.longitude);
    final to = LatLng(destination.latitude, destination.longitude);
    if (_transportMode == _TransportMode.transit) {
      final routes = await _routeService.getTransitRoutes(origin: from, destination: to);
      return routes.isEmpty ? null : routes.first.duration;
    }
    final route = await _routeService.getDriveRoute(origin: from, destination: to);
    return route?.duration;
  }

  /// The region every location placed on this trip so far agrees on —
  /// whichever of the starting location, ending location, any night's
  /// accommodation, or any stop already added was set first. Null until
  /// the trip has committed to a side at all, meaning anything goes.
  _MalaysiaRegion? get _committedRegion {
    final candidates = <TripStopLocation?>[
      _startingLocation,
      _endingLocation,
      ..._nightAccommodation,
      for (final day in _dayStops)
        for (final stop in day) stop.location,
    ];
    for (final candidate in candidates) {
      if (candidate != null) return _regionOf(candidate);
    }
    return null;
  }

  bool _isRegionAllowed(TripStopLocation location) {
    final committed = _committedRegion;
    return committed == null || _regionOf(location) == committed;
  }

  /// Shows why [location] was rejected — only ever called after
  /// [_isRegionAllowed] already returned false, so [_committedRegion] is
  /// guaranteed non-null here.
  void _showRegionBlocked(TripStopLocation location) {
    final committed = _committedRegion!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        content: Text(
          'This trip is in ${_regionLabel(committed)} — ${location.name} is in '
          '${_regionLabel(_regionOf(location))}, across the sea with no road link. '
          'Pick a place in the same region.',
        ),
      ),
    );
  }

  /// The place a given day's *first* stop should route from: the trip's
  /// starting location for Day 1, otherwise the previous night's
  /// accommodation. If a day already has stops, [_addStop] never needs
  /// this — it origins from the last stop instead.
  TripStopLocation? _dayOrigin(int dayIndex) {
    if (dayIndex == 0) return _startingLocation;
    final nightIndex = dayIndex - 1;
    return nightIndex < _nightAccommodation.length
        ? _nightAccommodation[nightIndex]
        : null;
  }

  /// The real origin for the *next* stop added to [dayIndex] — the last
  /// stop already on that day, or [_dayOrigin] if the day is still empty.
  TripStopLocation? _originForNextStop(int dayIndex) {
    final stops = _dayStops[dayIndex];
    if (stops.isNotEmpty) return stops.last.location;
    return _dayOrigin(dayIndex);
  }

  /// True if [date] combined with [time] hasn't already passed — checked
  /// only at the moment the traveler picks a date or a time, never
  /// re-checked later (e.g. at Save Trip). Otherwise a start planned for
  /// today at 9am would get silently invalidated just because filling in
  /// the rest of the form took past 9am, punishing slow planning for a
  /// choice that was perfectly valid when made.
  bool _isStartMomentValid(DateTime date, TimeOfDay time) {
    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    return !combined.isBefore(DateTime.now());
  }

  DateTime _combine(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  /// True if [endDate] combined with [endTime] is after the trip's start
  /// (start date combined with Trip Start Time) — checked as one
  /// combined moment each, not just date-before-date, so a same-day trip
  /// whose end time is earlier in the day than its start time is still
  /// caught. True whenever the start isn't fully set yet — nothing to
  /// compare against.
  bool _isEndMomentAfterStart(DateTime endDate, TimeOfDay endTime) {
    final startDate = _startDate;
    final startTime = _tripStartTime;
    if (startDate == null || startTime == null) return true;
    return _combine(endDate, endTime).isAfter(_combine(startDate, startTime));
  }

  /// Same check against whatever's *currently* set for [_endDate]/
  /// [_tripEndTime] — true whenever either isn't set yet.
  bool _isEndAfterStart() {
    final endDate = _endDate;
    final endTime = _tripEndTime;
    if (endDate == null || endTime == null) return true;
    return _isEndMomentAfterStart(endDate, endTime);
  }

  /// Clears an already-set Trip End Time if it's no longer after the
  /// trip's (possibly just-changed) start — called after any edit to the
  /// start date/time or the end date, all of which can invalidate it.
  void _clearStaleTripEndTime() {
    if (_tripEndTime != null && !_isEndAfterStart()) {
      _tripEndTime = null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Trip End Time is no longer after the trip start — pick a new one.'),
        ),
      );
    }
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
      final end = _endDate;
      if (end != null && end.isBefore(picked)) _endDate = picked;
      // The already-picked start time may now be earlier than "now" for
      // this new date (e.g. switching from tomorrow back to today) — ask
      // for a fresh one rather than silently keeping a stale value.
      final time = _tripStartTime;
      if (time != null && !_isStartMomentValid(picked, time)) {
        _tripStartTime = null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('That start time has already passed today — pick a new one.'),
          ),
        );
      } else {
        // The start moved later in the day (or to a later date entirely)
        // — the already-picked Trip End Time may no longer be after it.
        _clearStaleTripEndTime();
      }
      _syncDays();
    });
    _refreshTripEndTravel();
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
    setState(() {
      _endDate = picked;
      _clearStaleTripEndTime();
      _syncDays();
    });
    _refreshTripEndTravel();
  }

  /// Keeps reopening the time picker — pre-filled with the traveler's
  /// last (rejected) attempt — until they either land on a time that
  /// isn't already past for [_startDate], or cancel outright. Flutter's
  /// [showTimePicker] has no built-in "earliest selectable time" the way
  /// [showDatePicker] has `firstDate`, so this is the closest equivalent:
  /// an invalid pick can never actually be accepted, it just bounces
  /// straight back to the picker instead of silently closing.
  Future<void> _pickTripStartTime() async {
    var initial = _tripStartTime ?? const TimeOfDay(hour: 8, minute: 0);
    while (true) {
      final picked = await showTimePicker(context: context, initialTime: initial);
      if (picked == null) return;

      final date = _startDate;
      if (date != null && !_isStartMomentValid(date, picked)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('That time has already passed today — pick a later time.'),
          ),
        );
        initial = picked;
        continue;
      }

      setState(() {
        _tripStartTime = picked;
        // The start moved later in the day — the already-picked Trip End
        // Time may no longer be after it.
        _clearStaleTripEndTime();
      });
      // Affects Day 1 always, and any later day that hasn't been given
      // its own start-time override.
      for (var d = 0; d < _dayStops.length; d++) {
        if (d == 0 || d >= _dayStartOverride.length || _dayStartOverride[d] == null) {
          unawaited(_recheckWeatherForDay(d));
        }
      }
      return;
    }
  }

  /// Same reopen-until-valid loop as [_pickTripStartTime], but checked
  /// against the trip's start (date + time) as one combined moment
  /// rather than "now" — a same-day trip's end time must still fall
  /// after its start time, not just be some arbitrary time of day.
  Future<void> _pickTripEndTime() async {
    var initial = _tripEndTime ?? const TimeOfDay(hour: 18, minute: 0);
    while (true) {
      final picked = await showTimePicker(context: context, initialTime: initial);
      if (picked == null) return;

      final endDate = _endDate;
      if (endDate != null && !_isEndMomentAfterStart(endDate, picked)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Trip End Time must be after the trip\'s start date and time.'),
          ),
        );
        initial = picked;
        continue;
      }

      setState(() => _tripEndTime = picked);
      return;
    }
  }

  /// Refetches the travel leg from the last day's current end (its last
  /// stop, or its origin if it has none yet) to [_endingLocation] — called
  /// whenever something that leg depends on changes (dates, the ending
  /// location itself, the last day's stops, or — when the last day is
  /// still empty — its origin).
  Future<void> _refreshTripEndTravel() async {
    final ending = _endingLocation;
    final lastDay = _dayCount - 1;
    if (ending == null || lastDay < 0) {
      setState(() => _tripEndTravel = null);
      return;
    }
    final origin = _originForNextStop(lastDay);
    if (origin == null) {
      setState(() => _tripEndTravel = _TravelSegment(noOrigin: true));
      return;
    }
    setState(() => _tripEndTravel = _TravelSegment(loading: true));
    Duration? duration;
    try {
      duration = await _fetchDuration(origin, ending);
    } catch (_) {
      duration = null;
    }
    if (!mounted) return;
    // Guard against a stale response landing after newer trip-end inputs
    // changed again while this request was in flight.
    if (_endingLocation != ending || _dayCount - 1 != lastDay) return;
    setState(() => _tripEndTravel = _TravelSegment(duration: duration));
  }

  /// Refetches the travel leg from day [dayIndex]'s current end (its last
  /// stop, or — if it has none yet — straight from its origin, e.g. the
  /// previous night's accommodation) to that day's own accommodation. This
  /// is what makes an empty day show a direct "yesterday's accommodation
  /// → tonight's accommodation" leg rather than nothing at all.
  Future<void> _refreshAccommodationTravel(int dayIndex) async {
    if (dayIndex < 0 || dayIndex >= _nightAccommodation.length) return;
    final destination = _nightAccommodation[dayIndex];
    if (destination == null) {
      setState(() => _accommodationTravel[dayIndex] = null);
      return;
    }
    final origin = _originForNextStop(dayIndex);
    if (origin == null) {
      setState(() => _accommodationTravel[dayIndex] = _TravelSegment(noOrigin: true));
      return;
    }
    setState(() => _accommodationTravel[dayIndex] = _TravelSegment(loading: true));
    Duration? duration;
    try {
      duration = await _fetchDuration(origin, destination);
    } catch (_) {
      duration = null;
    }
    if (!mounted) return;
    if (dayIndex >= _nightAccommodation.length || _nightAccommodation[dayIndex] != destination) {
      return;
    }
    setState(() => _accommodationTravel[dayIndex] = _TravelSegment(duration: duration));
  }

  Future<void> _addStop(int dayIndex) async {
    final existingIds = {
      for (final s in _dayStops[dayIndex])
        s.location.placeId ?? '${s.location.latitude},${s.location.longitude}',
    };
    final place = await showModalBottomSheet<NearbyPlace>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StopSearchSheet(existingPlaceIds: existingIds),
    );
    if (place == null) return;

    // Fetch the authoritative full record (opening hours, business
    // status, etc.) rather than trusting whatever the search endpoint's
    // lighter field mask happened to include.
    NearbyPlace details = place;
    try {
      details = await _placesService.getPlaceDetails(place.id);
    } catch (_) {
      // Fall back to the search-result data if Place Details fails.
    }

    final location = TripStopLocation.fromNearbyPlace(details);
    if (!mounted) return;

    if (!_isRegionAllowed(location)) {
      _showRegionBlocked(location);
      return;
    }

    final origin = _originForNextStop(dayIndex);
    final entry = _StopEntry(location);

    setState(() {
      _dayStops[dayIndex].add(entry);
      _dayTravel[dayIndex].add(
        origin == null ? _TravelSegment(noOrigin: true) : _TravelSegment(loading: true),
      );
    });

    if (dayIndex == _dayCount - 1) unawaited(_refreshTripEndTravel());
    if (dayIndex < _nightAccommodation.length) unawaited(_refreshAccommodationTravel(dayIndex));

    if (origin == null) {
      unawaited(_recheckWeatherForDay(dayIndex));
      return;
    }
    await _fetchTravelSegment(
      dayIndex: dayIndex,
      entry: entry,
      origin: origin,
      destination: location,
    );
  }

  Future<void> _fetchTravelSegment({
    required int dayIndex,
    required _StopEntry entry,
    required TripStopLocation origin,
    required TripStopLocation destination,
  }) async {
    Duration? duration;
    try {
      duration = await _fetchDuration(origin, destination);
    } catch (_) {
      duration = null;
    }
    if (!mounted) return;
    // The stop may have moved or been removed while the request was in
    // flight — look it up by identity rather than trusting the original
    // index.
    if (dayIndex >= _dayStops.length) return;
    final index = _dayStops[dayIndex].indexOf(entry);
    if (index == -1 || index >= _dayTravel[dayIndex].length) return;
    setState(() {
      _dayTravel[dayIndex][index] = _TravelSegment(duration: duration);
    });
    if (dayIndex < _dayDates.length) unawaited(_recheckWeatherForDay(dayIndex));
  }

  /// Re-derives every outdoor/mixed stop's arrival→end window for
  /// [dayIndex] and re-checks each against forecast rain — called
  /// whenever something that could shift those windows changes (a travel
  /// leg resolving, a duration edit, a reorder, a removal, or the day's
  /// start time). Indoor stops are never checked at all. A stop moved off
  /// this day (removed) has its stale check dropped rather than left to
  /// show against a window that no longer applies.
  Future<void> _recheckWeatherForDay(int dayIndex) async {
    if (dayIndex < 0 || dayIndex >= _dayStops.length || dayIndex >= _dayDates.length) return;
    final date = _dayDates[dayIndex];
    final stops = _dayStops[dayIndex];
    final startMinutes = _dayStartMinutesFor(dayIndex);
    final times = _computeDayTimes(startMinutes, stops, _dayTravel[dayIndex]);

    if (!StopWeatherService.isWithinForecastWindow(date)) {
      if (mounted) {
        setState(() {
          for (final stop in stops) {
            _stopWeather.remove(stop);
          }
        });
      }
      return;
    }

    for (var i = 0; i < stops.length; i++) {
      final entry = stops[i];
      final env = entry.location.environment;
      if (env != PlaceEnvironment.outdoor && env != PlaceEnvironment.mixed) {
        _stopWeather.remove(entry);
        continue;
      }
      setState(() => _stopWeather[entry] = null);
      final result = await _stopWeatherService.check(
        position: LatLng(entry.location.latitude, entry.location.longitude),
        date: date,
        arrivalMinutes: times.arrivals[i],
        endMinutes: times.ends[i],
      );
      if (!mounted) return;
      // The stop may have been removed/moved to another day while this
      // request was in flight.
      if (dayIndex >= _dayStops.length || !_dayStops[dayIndex].contains(entry)) continue;
      setState(() => _stopWeather[entry] = result);
    }
  }

  void _removeStop(int dayIndex, int stopIndex) {
    setState(() {
      final removed = _dayStops[dayIndex].removeAt(stopIndex);
      _dayTravel[dayIndex].removeAt(stopIndex);
      _stopWeather.remove(removed);
    });
    if (dayIndex == _dayCount - 1) unawaited(_refreshTripEndTravel());
    if (dayIndex < _nightAccommodation.length) unawaited(_refreshAccommodationTravel(dayIndex));
    unawaited(_recheckWeatherForDay(dayIndex));
  }

  void _changeDuration(int dayIndex, int stopIndex, int deltaMinutes) {
    setState(() {
      final entry = _dayStops[dayIndex][stopIndex];
      final next = entry.visitMinutes + deltaMinutes;
      entry.visitMinutes = next.clamp(15, 12 * 60);
    });
    unawaited(_recheckWeatherForDay(dayIndex));
  }

  /// Manual drag-and-drop reorder within a day. The existing travel
  /// segments described the *old* order's pairwise legs, which no longer
  /// match once stops are shuffled — rather than show a now-wrong
  /// duration, they're cleared and immediately refetched for the new order.
  void _reorderStops(int dayIndex, int oldIndex, int newIndex) {
    setState(() {
      final stops = _dayStops[dayIndex];
      final moved = stops.removeAt(oldIndex);
      stops.insert(newIndex, moved);
      _dayTravel[dayIndex] = [for (final _ in stops) _TravelSegment(stale: true)];
    });
    unawaited(_refetchDayTravel(dayIndex));
    if (dayIndex == _dayCount - 1) unawaited(_refreshTripEndTravel());
    if (dayIndex < _nightAccommodation.length) unawaited(_refreshAccommodationTravel(dayIndex));
    unawaited(_recheckWeatherForDay(dayIndex));
  }

  /// Refetches every stop-to-stop travel leg for [dayIndex] in its
  /// current order — each stop's origin is the stop before it (or the
  /// day's own origin for the first stop). Used after anything that
  /// changes stop order (manual reorder, [_optimizeDay]) or invalidates
  /// every leg at once ([_changeTransportMode]), so a recalculated order
  /// always shows real travel times rather than leaving them marked
  /// stale until some later, unrelated action happens to refetch them.
  Future<void> _refetchDayTravel(int dayIndex) async {
    final stops = _dayStops[dayIndex];
    TripStopLocation? previous;
    for (var i = 0; i < stops.length; i++) {
      final entry = stops[i];
      final origin = previous ?? _dayOrigin(dayIndex);
      if (origin == null) {
        setState(() => _dayTravel[dayIndex][i] = _TravelSegment(noOrigin: true));
      } else {
        setState(() => _dayTravel[dayIndex][i] = _TravelSegment(loading: true));
        unawaited(
          _fetchTravelSegment(dayIndex: dayIndex, entry: entry, origin: origin, destination: entry.location),
        );
      }
      previous = entry.location;
    }
  }

  /// Placeholder for the real weather/opening-hours/route optimizer.
  /// Reorders day [dayIndex]'s stops for travel efficiency via
  /// [RouteOptimizerService] — starting from the day's own start (trip
  /// starting location on Day 1, previous night's accommodation
  /// otherwise) through to its end (that night's accommodation, or the
  /// trip's ending location on the last day). Weather suitability and
  /// opening-hours fit aren't factored in yet — this is travel order
  /// only.
  Future<void> _optimizeDay(int dayIndex) async {
    if (_optimizingDays.contains(dayIndex)) return;
    final stops = _dayStops[dayIndex];
    if (stops.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Add at least two stops to this day to optimize its route.'),
        ),
      );
      return;
    }
    final origin = _dayOrigin(dayIndex);
    if (origin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            dayIndex == 0
                ? 'Set the trip\'s starting location first.'
                : 'Set the previous night\'s accommodation first.',
          ),
        ),
      );
      return;
    }
    final destination =
        dayIndex == _dayCount - 1 ? _endingLocation : _nightAccommodation[dayIndex];

    setState(() => _optimizingDays.add(dayIndex));
    try {
      final orderedLocations = await _routeOptimizerService.optimize(
        origin: origin,
        stops: [for (final entry in stops) entry.location],
        destination: destination,
        useTransit: _transportMode == _TransportMode.transit,
      );
      if (!mounted) return;
      // The day may have changed (stops added/removed) while this was in
      // flight — bail rather than apply an order computed for a stale set.
      if (!_sameStopSet(_dayStops[dayIndex], orderedLocations)) return;

      setState(() {
        final byLocation = {for (final entry in stops) entry.location: entry};
        _dayStops[dayIndex] = [for (final loc in orderedLocations) byLocation[loc]!];
        _dayTravel[dayIndex] = [for (final _ in orderedLocations) _TravelSegment(stale: true)];
      });
      unawaited(_refetchDayTravel(dayIndex));
      if (dayIndex == _dayCount - 1) unawaited(_refreshTripEndTravel());
      if (dayIndex < _nightAccommodation.length) unawaited(_refreshAccommodationTravel(dayIndex));
      unawaited(_recheckWeatherForDay(dayIndex));
    } finally {
      if (mounted) setState(() => _optimizingDays.remove(dayIndex));
    }
  }

  /// True if [entries] and [locations] contain exactly the same set of
  /// locations (regardless of order) — used to detect that a day's stop
  /// list hasn't changed while an optimize request was in flight.
  bool _sameStopSet(List<_StopEntry> entries, List<TripStopLocation> locations) {
    if (entries.length != locations.length) return false;
    final entryLocations = entries.map((e) => e.location).toSet();
    return locations.every(entryLocations.contains);
  }

  /// Switches [_transportMode] and refetches every already-computed leg
  /// under the new mode — stop-to-stop, each day's accommodation leg, and
  /// the trip-end leg — since a driving duration and a transit duration
  /// between the same two points aren't interchangeable.
  Future<void> _changeTransportMode(_TransportMode mode) async {
    if (mode == _transportMode) return;
    setState(() => _transportMode = mode);

    for (var d = 0; d < _dayStops.length; d++) {
      TripStopLocation? previous;
      for (final entry in _dayStops[d]) {
        final origin = previous ?? _dayOrigin(d);
        final index = _dayStops[d].indexOf(entry);
        if (origin == null) {
          setState(() => _dayTravel[d][index] = _TravelSegment(noOrigin: true));
        } else {
          setState(() => _dayTravel[d][index] = _TravelSegment(loading: true));
          unawaited(
            _fetchTravelSegment(dayIndex: d, entry: entry, origin: origin, destination: entry.location),
          );
        }
        previous = entry.location;
      }
      if (d < _nightAccommodation.length) unawaited(_refreshAccommodationTravel(d));
    }
    unawaited(_refreshTripEndTravel());
  }

  void _setNightAccommodation(int nightIndex, TripStopLocation? location) {
    if (location != null && !_isRegionAllowed(location)) {
      _showRegionBlocked(location);
      return;
    }
    setState(() => _nightAccommodation[nightIndex] = location);
    unawaited(_refreshAccommodationTravel(nightIndex));
    // The next day's accommodation leg origins from here too, but only if
    // that day is still empty (otherwise it origins from its own last
    // stop instead, which this change doesn't affect).
    if (nightIndex + 1 < _nightAccommodation.length && _dayStops[nightIndex + 1].isEmpty) {
      unawaited(_refreshAccommodationTravel(nightIndex + 1));
    }
    // Only matters if the last day is still empty — then this
    // accommodation *is* its origin, which the trip-end leg routes from.
    if (nightIndex == _dayCount - 2) unawaited(_refreshTripEndTravel());
  }

  /// True once every required field is filled: trip name (via [_formKey]),
  /// both dates, starting location, trip start time, trip end location,
  /// and every night's accommodation. Trip end *time* stays optional (it's
  /// just an informational target).
  bool get _isFormComplete =>
      (_formKey.currentState?.validate() ?? false) &&
      _startDate != null &&
      _endDate != null &&
      _startingLocation != null &&
      _tripStartTime != null &&
      _endingLocation != null &&
      _nightAccommodation.every((a) => a != null);

  /// Flattens the whole trip's current on-screen state — every day's
  /// dates/start-time override, every stop with its computed arrival/end
  /// time and weather check, and every travel leg — into the plain input
  /// lists [TripService.saveTripSchedule] persists. Only ever called from
  /// [_submit], after [_isFormComplete] confirmed the starting location,
  /// every night's accommodation, and the ending location are all set —
  /// so [_dayOrigin] is guaranteed non-null for every day here.
  ({List<TripDayInput> days, List<TripStopInput> stops, List<TripTravelSegmentInput> segments})
  _buildScheduleInputs() {
    final days = <TripDayInput>[];
    final stops = <TripStopInput>[];
    final segments = <TripTravelSegmentInput>[];
    final transportMode = _transportMode.name;

    for (var d = 0; d < _dayCount; d++) {
      final dayNumber = d + 1;
      final override = d > 0 && d < _dayStartOverride.length ? _dayStartOverride[d] : null;
      days.add(
        TripDayInput(
          dayNumber: dayNumber,
          date: _dayDates[d],
          startTimeOverride: override == null
              ? null
              : _minutesToClock(_timeOfDayToMinutes(override)),
        ),
      );

      final dayStops = _dayStops[d];
      final dayTravel = _dayTravel[d];
      final times = _computeDayTimes(_dayStartMinutesFor(d), dayStops, dayTravel);
      var previous = _dayOrigin(d)!;

      for (var i = 0; i < dayStops.length; i++) {
        final entry = dayStops[i];
        final weather = _stopWeather[entry];
        stops.add(
          TripStopInput(
            dayNumber: dayNumber,
            sequence: i,
            location: entry.location,
            visitMinutes: entry.visitMinutes,
            arrivalMinutes: times.arrivals[i],
            endMinutes: times.ends[i],
            weatherFlagged: weather?.isBad ?? false,
            weatherBadPeriods: weather?.badPeriods.map((p) => p.name).toList() ?? const [],
            weatherForecastPhrase: weather?.forecast?.summaryForecast,
            weatherCheckedAt: (weather?.isResolved ?? false) ? DateTime.now() : null,
          ),
        );
        segments.add(
          TripTravelSegmentInput(
            dayNumber: dayNumber,
            sequence: i,
            fromName: previous.name,
            fromLatitude: previous.latitude,
            fromLongitude: previous.longitude,
            toName: entry.location.name,
            toLatitude: entry.location.latitude,
            toLongitude: entry.location.longitude,
            legKind: TripLegKind.stop,
            transportMode: transportMode,
            durationMinutes: i < dayTravel.length ? dayTravel[i].duration?.inMinutes : null,
          ),
        );
        previous = entry.location;
      }

      final isLastDay = d == _dayCount - 1;
      final destination = isLastDay
          ? _endingLocation
          : (d < _nightAccommodation.length ? _nightAccommodation[d] : null);
      if (destination != null) {
        final trailing = isLastDay
            ? _tripEndTravel
            : (d < _accommodationTravel.length ? _accommodationTravel[d] : null);
        segments.add(
          TripTravelSegmentInput(
            dayNumber: dayNumber,
            sequence: dayStops.length,
            fromName: previous.name,
            fromLatitude: previous.latitude,
            fromLongitude: previous.longitude,
            toName: destination.name,
            toLatitude: destination.latitude,
            toLongitude: destination.longitude,
            legKind: isLastDay ? TripLegKind.tripEnd : TripLegKind.accommodation,
            transportMode: transportMode,
            durationMinutes: trailing?.duration?.inMinutes,
          ),
        );
      }
    }

    return (days: days, stops: stops, segments: segments);
  }

  Future<void> _submit() async {
    final complete = _isFormComplete;
    setState(() => _showValidation = true);
    if (!complete) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Please fill in every required field, highlighted in red.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final accommodations = [
        for (final a in _nightAccommodation) ?a,
      ];
      final tripId = await _tripService.createTrip(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        startLocationName: _startingLocation?.name,
        startAddress: _startingLocation?.address,
        startLatitude: _startingLocation?.latitude,
        startLongitude: _startingLocation?.longitude,
        endLocationName: _endingLocation?.name,
        endAddress: _endingLocation?.address,
        endLatitude: _endingLocation?.latitude,
        endLongitude: _endingLocation?.longitude,
        startDate: _startDate,
        endDate: _endDate,
        startTime: _formatTimeOfDay(_tripStartTime),
        endTime: _tripEndTime == null ? null : _formatTimeOfDay(_tripEndTime),
        totalBudget: 0,
        transportMode: _transportMode.name,
        accommodations: accommodations,
      );
      final schedule = _buildScheduleInputs();
      await _tripService.saveTripSchedule(
        tripId: tripId,
        days: schedule.days,
        stops: schedule.stops,
        segments: schedule.segments,
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
    final dayDates = _dayDates;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Create Trip',
              subtitle: 'Plan it day by day',
            ),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _FieldLabel('Trip Name *'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      autovalidateMode: _showValidation ? AutovalidateMode.always : AutovalidateMode.disabled,
                      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
                      decoration: _inputDecoration(context, hint: 'e.g. Penang Adventure'),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Give your trip a name'
                          : null,
                    ),
                    const SizedBox(height: 20),
                    _FieldLabel('Trip Description'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      style: TextStyle(fontWeight: FontWeight.w500, color: context.colors.ink),
                      decoration: _inputDecoration(context, hint: 'What is this trip about?'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel('Start Date *'),
                              const SizedBox(height: 8),
                              _DateField(
                                value: _startDate,
                                placeholder: 'Start date',
                                onTap: _pickStartDate,
                                hasError: _showValidation && _startDate == null,
                              ),
                              if (_showValidation && _startDate == null) const _ErrorCaption(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _FieldLabel('End Date *'),
                              const SizedBox(height: 8),
                              _DateField(
                                value: _endDate,
                                placeholder: 'End date',
                                onTap: _pickEndDate,
                                hasError: _showValidation && _endDate == null,
                              ),
                              if (_showValidation && _endDate == null) const _ErrorCaption(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _FieldLabel('Starting Location *'),
                    const SizedBox(height: 4),
                    Text(
                      'Where Day 1\'s first stop routes from.',
                      style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 8),
                    LocationSearchField(
                      value: _startingLocation,
                      onChanged: (v) {
                        if (v != null && !_isRegionAllowed(v)) {
                          _showRegionBlocked(v);
                          return;
                        }
                        setState(() => _startingLocation = v);
                        if (_nightAccommodation.isNotEmpty) {
                          unawaited(_refreshAccommodationTravel(0));
                        }
                        unawaited(_refreshTripEndTravel());
                      },
                      hintText: 'Where does the trip start?',
                    ),
                    if (_showValidation && _startingLocation == null) const _ErrorCaption(),
                    const SizedBox(height: 10),
                    _FieldLabel('Trip Start Time *'),
                    const SizedBox(height: 4),
                    Text(
                      'The time you leave your starting location — also used as the time you leave each day\'s accommodation.',
                      style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 8),
                    _TimeField(
                      value: _tripStartTime,
                      onTap: _pickTripStartTime,
                      hasError: _showValidation && _tripStartTime == null,
                    ),
                    if (_showValidation && _tripStartTime == null) const _ErrorCaption(),
                    const SizedBox(height: 20),
                    _FieldLabel('Trip Ends At *'),
                    const SizedBox(height: 4),
                    Text(
                      'Your final stop for the trip — e.g. the airport.',
                      style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 8),
                    LocationSearchField(
                      value: _endingLocation,
                      onChanged: (v) {
                        if (v != null && !_isRegionAllowed(v)) {
                          _showRegionBlocked(v);
                          return;
                        }
                        setState(() => _endingLocation = v);
                        unawaited(_refreshTripEndTravel());
                      },
                      hintText: 'Where does the trip end?',
                      selectedIcon: Icons.flag_rounded,
                    ),
                    if (_showValidation && _endingLocation == null) const _ErrorCaption(),
                    if (_endingLocation != null) ...[
                      const SizedBox(height: 10),
                      _FieldLabel('Trip End Time'),
                      const SizedBox(height: 4),
                      Text(
                        'Target time to reach it — e.g. a flight departure.',
                        style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                      ),
                      const SizedBox(height: 8),
                      _TimeField(value: _tripEndTime, onTap: _pickTripEndTime),
                    ],
                    if (_dayCount > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        '$_dayCount day${_dayCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _TransportModeToggle(
                        mode: _transportMode,
                        onChanged: (m) => unawaited(_changeTransportMode(m)),
                      ),
                      const SizedBox(height: 16),
                      _DayTabBar(
                        dates: dayDates,
                        selected: _selectedDay,
                        onSelect: (i) => setState(() => _selectedDay = i),
                      ),
                      const SizedBox(height: 16),
                      if (_dayStops.length > _selectedDay)
                        _DayTimelinePanel(
                          dayNumber: _selectedDay + 1,
                          date: dayDates[_selectedDay],
                          dayStartMinutes: _dayStartMinutesFor(_selectedDay),
                          startTimeIsSet: _selectedDay == 0
                              ? _tripStartTime != null
                              : (_dayStartOverride.length > _selectedDay &&
                                      _dayStartOverride[_selectedDay] != null) ||
                                  _tripStartTime != null,
                          canEditStartTime: _selectedDay != 0,
                          onEditStartTime: _selectedDay == 0 ? null : () => _pickDayStartOverride(_selectedDay),
                          originLabel: _originLabel(_selectedDay),
                          stops: _dayStops[_selectedDay],
                          travel: _dayTravel[_selectedDay],
                          isLastDay: _selectedDay == _dayCount - 1,
                          accommodation: _selectedDay < _nightAccommodation.length
                              ? _nightAccommodation[_selectedDay]
                              : null,
                          accommodationTravel: _selectedDay < _accommodationTravel.length
                              ? _accommodationTravel[_selectedDay]
                              : null,
                          previousNightAccommodation: _selectedDay > 0 && _selectedDay - 1 < _nightAccommodation.length
                              ? _nightAccommodation[_selectedDay - 1]
                              : null,
                          showValidation: _showValidation,
                          weatherForecastAvailable: StopWeatherService.isWithinForecastWindow(
                            dayDates[_selectedDay],
                          ),
                          weatherFor: (entry) => _stopWeather[entry],
                          tripEndLocation: _selectedDay == _dayCount - 1 ? _endingLocation : null,
                          tripEndTravel: _selectedDay == _dayCount - 1 ? _tripEndTravel : null,
                          tripEndTargetMinutes: _selectedDay == _dayCount - 1 && _tripEndTime != null
                              ? _timeOfDayToMinutes(_tripEndTime!)
                              : null,
                          onAddStop: () => _addStop(_selectedDay),
                          onRemoveStop: (i) => _removeStop(_selectedDay, i),
                          onChangeDuration: (i, d) => _changeDuration(_selectedDay, i, d),
                          onReorderStops: (from, to) => _reorderStops(_selectedDay, from, to),
                          isOptimizing: _optimizingDays.contains(_selectedDay),
                          onOptimize: () => _optimizeDay(_selectedDay),
                          onAccommodationChanged: _selectedDay < _nightAccommodation.length
                              ? (v) => _setNightAccommodation(_selectedDay, v)
                              : null,
                        ),
                      const SizedBox(height: 20),
                    ] else
                      const SizedBox(height: 32),
                    GradientButton(
                      label: 'Save Trip',
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

  /// Label for the timeline's origin node — the trip starting location for
  /// Day 1, the previous night's accommodation for a later day, or a
  /// "not set" placeholder so the traveler knows why travel ETAs to the
  /// first stop aren't showing.
  String _originLabel(int dayIndex) {
    final origin = _dayOrigin(dayIndex);
    if (origin != null) return origin.name;
    return dayIndex == 0
        ? 'Starting location not set'
        : 'Previous night\'s accommodation not set';
  }
}

InputDecoration _inputDecoration(BuildContext context, {required String hint}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: context.colors.muted, fontWeight: FontWeight.w500),
    filled: true,
    fillColor: context.colors.card,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w700, fontSize: 13.5),
    );
  }
}

/// Small red "Required" caption shown under a field once
/// [_CreateTripScreenState._showValidation] is true and that field is
/// still empty.
class _ErrorCaption extends StatelessWidget {
  const _ErrorCaption();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 4, left: 4),
      child: Text(
        'Required',
        style: TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.placeholder,
    required this.onTap,
    this.hasError = false,
  });

  final DateTime? value;
  final String placeholder;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final date = value;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(16),
          border: hasError ? Border.all(color: Colors.red, width: 1.4) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded, color: context.colors.muted, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date == null ? placeholder : _formatDate(date),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: date == null ? context.colors.muted : context.colors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({required this.value, required this.onTap, this.hasError = false});

  final TimeOfDay? value;
  final VoidCallback onTap;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(16),
          border: hasError ? Border.all(color: Colors.red, width: 1.4) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.access_time_rounded, color: context.colors.muted, size: 16),
            const SizedBox(width: 8),
            Text(
              _formatTimeOfDay(value),
              style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w600, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Driving vs transit toggle for every travel leg in the timeline —
/// applies to the whole trip, not per-day. Switching it refetches every
/// leg already computed under the previous mode.
class _TransportModeToggle extends StatelessWidget {
  const _TransportModeToggle({required this.mode, required this.onChanged});

  final _TransportMode mode;
  final ValueChanged<_TransportMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: context.colors.card, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Expanded(
            child: _TransportModeButton(
              label: 'Driving',
              icon: Icons.directions_car_rounded,
              selected: mode == _TransportMode.driving,
              onTap: () => onChanged(_TransportMode.driving),
            ),
          ),
          Expanded(
            child: _TransportModeButton(
              label: 'Transit',
              icon: Icons.directions_bus_filled_rounded,
              selected: mode == _TransportMode.transit,
              onTap: () => onChanged(_TransportMode.transit),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportModeButton extends StatelessWidget {
  const _TransportModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : context.colors.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : context.colors.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayTabBar extends StatelessWidget {
  const _DayTabBar({required this.dates, required this.selected, required this.onSelect});

  final List<DateTime> dates;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = i == selected;
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
                  Text(
                    'Day ${i + 1}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatShortDate(dates[i]),
                    style: TextStyle(
                      color: isSelected ? Colors.white.withValues(alpha: 0.9) : context.colors.muted,
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

/// A single day's vertical timeline: an origin node (starting location or
/// previous night's accommodation), then alternating travel connectors and
/// stop nodes, purely in the order stops were added — no reordering or
/// route optimization happens here.
class _DayTimelinePanel extends StatelessWidget {
  const _DayTimelinePanel({
    required this.dayNumber,
    required this.date,
    required this.dayStartMinutes,
    this.startTimeIsSet = true,
    this.canEditStartTime = false,
    this.onEditStartTime,
    required this.originLabel,
    required this.stops,
    required this.travel,
    required this.isLastDay,
    required this.accommodation,
    this.accommodationTravel,
    this.previousNightAccommodation,
    required this.showValidation,
    required this.weatherForecastAvailable,
    required this.weatherFor,
    this.tripEndLocation,
    this.tripEndTravel,
    this.tripEndTargetMinutes,
    required this.onAddStop,
    required this.onRemoveStop,
    required this.onChangeDuration,
    required this.onReorderStops,
    required this.onOptimize,
    this.isOptimizing = false,
    required this.onAccommodationChanged,
  });

  final int dayNumber;
  final DateTime date;
  final int dayStartMinutes;

  /// False when [dayStartMinutes] is just the 8am placeholder default,
  /// not a value the traveler actually chose (e.g. their pick was
  /// rejected as already past for today) — shown as "--:--" instead of a
  /// real time, so an unset start time never *looks* accepted.
  final bool startTimeIsSet;

  /// False for Day 1, whose clock is always [_CreateTripScreenState._tripStartTime]
  /// set up top — every later day can override it here instead.
  final bool canEditStartTime;
  final VoidCallback? onEditStartTime;

  final String originLabel;
  final List<_StopEntry> stops;
  final List<_TravelSegment> travel;
  final bool isLastDay;
  final TripStopLocation? accommodation;

  /// Travel leg from this day's current end to [accommodation] — set even
  /// with zero stops, so an empty day still shows a direct "yesterday's
  /// accommodation → tonight's accommodation" leg.
  final _TravelSegment? accommodationTravel;

  /// The previous night's accommodation, if any — lets this day offer a
  /// one-tap "Same as previous night" to stay at the same place multiple
  /// nights running, instead of re-searching for it.
  final TripStopLocation? previousNightAccommodation;

  /// True once the traveler has attempted to save — turns on the red
  /// "Required" caption under this day's accommodation field.
  final bool showValidation;

  /// False when [date] is beyond MET Malaysia's forecast window — every
  /// outdoor/mixed stop then shows "forecast not available yet" instead
  /// of attempting a check.
  final bool weatherForecastAvailable;

  /// The weather check for a given stop, if any — null while in flight or
  /// if it hasn't been checked yet (e.g. an indoor stop, never checked at
  /// all).
  final StopWeatherCheck? Function(_StopEntry entry) weatherFor;

  /// Only set on the last day: the trip's final destination (e.g. the
  /// airport), the travel leg reaching it, and an optional target arrival
  /// time to compare the computed one against.
  final TripStopLocation? tripEndLocation;
  final _TravelSegment? tripEndTravel;
  final int? tripEndTargetMinutes;

  final VoidCallback onAddStop;
  final void Function(int stopIndex) onRemoveStop;
  final void Function(int stopIndex, int deltaMinutes) onChangeDuration;

  /// Drag-and-drop reorder within this day, in [ReorderableListView]'s raw
  /// (oldIndex, newIndex) form.
  final void Function(int oldIndex, int newIndex) onReorderStops;

  /// "Optimize Day N" — reorders this day's stops via
  /// [RouteOptimizerService] for travel efficiency (weather suitability
  /// and opening-hours fit aren't factored in yet).
  final VoidCallback onOptimize;

  /// True while this day's optimize request is in flight — shows a
  /// spinner on the button and blocks a second concurrent tap.
  final bool isOptimizing;

  final ValueChanged<TripStopLocation?>? onAccommodationChanged;

  @override
  Widget build(BuildContext context) {
    final times = _computeDayTimes(dayStartMinutes, stops, travel);
    final arrivals = times.arrivals;
    final ends = times.ends;
    final clock = ends.isEmpty ? dayStartMinutes : ends.last;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: context.colors.card, borderRadius: BorderRadius.circular(18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Day $dayNumber — ${_formatShortDate(date)}',
            style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 14),
          _OriginNode(
            time: startTimeIsSet ? _minutesToClock(dayStartMinutes) : '--:--',
            label: originLabel,
            onEditTime: canEditStartTime ? onEditStartTime : null,
          ),
          if (!startTimeIsSet) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 62),
              child: Text(
                canEditStartTime
                    ? 'Pick a start time for this day — times below are placeholders.'
                    : 'Pick a valid Trip Start Time above — times below are placeholders.',
                style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (stops.isNotEmpty)
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: stops.length,
              onReorderItem: onReorderStops,
              itemBuilder: (context, i) {
                return Column(
                  key: ValueKey(stops[i]),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TravelConnector(segment: i < travel.length ? travel[i] : null),
                    _StopNode(
                      entry: stops[i],
                      index: i,
                      arrivalLabel: _minutesToClock(arrivals[i]),
                      endLabel: _minutesToClock(ends[i]),
                      weatherForecastAvailable: weatherForecastAvailable,
                      weather: weatherFor(stops[i]),
                      onRemove: () => onRemoveStop(i),
                      onChangeDuration: (delta) => onChangeDuration(i, delta),
                    ),
                  ],
                );
              },
            ),
          if (tripEndLocation case final ending?) ...[
            _TravelConnector(segment: tripEndTravel),
            _TripEndNode(
              location: ending,
              arrivalLabel: _minutesToClock(clock + (tripEndTravel?.duration?.inMinutes ?? 0)),
              targetLabel: tripEndTargetMinutes == null ? null : _minutesToClock(tripEndTargetMinutes!),
              isLate: tripEndTargetMinutes != null &&
                  clock + (tripEndTravel?.duration?.inMinutes ?? 0) > tripEndTargetMinutes!,
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onAddStop,
            icon: const Icon(Icons.add_location_alt_rounded, size: 18),
            label: const Text('Add Stop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              minimumSize: const Size(double.infinity, 0),
            ),
          ),
          if (stops.length > 1) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: isOptimizing ? null : onOptimize,
              icon: isOptimizing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: context.colors.muted),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(isOptimizing ? 'Optimizing Day $dayNumber…' : 'Optimize Day $dayNumber'),
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.ink,
                side: BorderSide(color: context.colors.muted.withValues(alpha: 0.4)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ],
          if (onAccommodationChanged case final onChanged?) ...[
            const SizedBox(height: 18),
            Divider(color: context.colors.surface, height: 1),
            const SizedBox(height: 14),
            Text(
              'Accommodation for tonight *',
              style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Used as the starting point for Day ${dayNumber + 1}.',
              style: TextStyle(color: context.colors.muted, fontSize: 11.5),
            ),
            if (previousNightAccommodation case final previous?
                when previous != accommodation) ...[
              const SizedBox(height: 8),
              _SameAsPreviousChip(
                location: previous,
                onTap: () => onChanged(previous),
              ),
            ],
            const SizedBox(height: 8),
            _TravelConnector(segment: accommodationTravel),
            LocationSearchField(
              value: accommodation,
              onChanged: onChanged,
              hintText: 'Search a hotel or stay',
              selectedIcon: Icons.hotel_rounded,
            ),
            if (showValidation && accommodation == null) const _ErrorCaption(),
          ] else if (isLastDay) ...[
            const SizedBox(height: 18),
            Divider(color: context.colors.surface, height: 1),
            const SizedBox(height: 14),
            Text(
              'The trip ends today — no accommodation needed.',
              style: TextStyle(color: context.colors.muted, fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }
}

class _OriginNode extends StatelessWidget {
  const _OriginNode({required this.time, required this.label, this.onEditTime});
  final String time;
  final String label;

  /// Null for Day 1 (its clock is fixed to the trip's Start Time above) —
  /// non-null for any later day, letting the traveler override when that
  /// day's plan actually begins.
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
            style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        Icon(Icons.flag_circle_rounded, color: AppColors.accent, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
        if (onEditTime != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onEditTime,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.edit_rounded, size: 15, color: context.colors.muted),
            ),
          ),
      ],
    );
  }
}

/// The trip's final leg — arrival at [location] (e.g. the airport). Shown
/// only on the last day, after every stop. If a target arrival time was
/// set, it's shown alongside the computed one and flagged when the
/// computed arrival is later than the target.
class _TripEndNode extends StatelessWidget {
  const _TripEndNode({
    required this.location,
    required this.arrivalLabel,
    required this.targetLabel,
    required this.isLate,
  });

  final TripStopLocation location;
  final String arrivalLabel;
  final String? targetLabel;
  final bool isLate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            arrivalLabel,
            style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.flag_rounded, color: Color(0xFFE53935), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trip Ends — ${location.name}',
                style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w700, fontSize: 13.5),
              ),
              if (targetLabel != null) ...[
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Target: $targetLabel',
                      style: TextStyle(color: context.colors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    if (isLate) _Tag('May be too late', warning: true),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TravelConnector extends StatelessWidget {
  const _TravelConnector({required this.segment});
  final _TravelSegment? segment;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 52),
          const SizedBox(width: 10),
          Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: context.colors.muted),
          const SizedBox(width: 6),
          Text(
            _travelLabel(segment),
            style: TextStyle(color: context.colors.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StopNode extends StatelessWidget {
  const _StopNode({
    required this.entry,
    required this.index,
    required this.arrivalLabel,
    required this.endLabel,
    required this.weatherForecastAvailable,
    required this.weather,
    required this.onRemove,
    required this.onChangeDuration,
  });

  final _StopEntry entry;

  /// This stop's position in its day — the drag handle needs it to tell
  /// the enclosing [ReorderableListView] which item is being dragged.
  final int index;
  final String arrivalLabel;
  final String endLabel;

  /// False when this stop's day is beyond MET Malaysia's forecast window
  /// — shown as "forecast not available yet" instead of attempting a
  /// check. Irrelevant for an indoor stop, which never shows a weather
  /// row at all.
  final bool weatherForecastAvailable;

  /// Null while a check is in flight, or if this stop hasn't been
  /// checked (always true for an indoor stop).
  final StopWeatherCheck? weather;

  final VoidCallback onRemove;
  final void Function(int deltaMinutes) onChangeDuration;

  @override
  Widget build(BuildContext context) {
    final location = entry.location;
    final env = location.environment;
    final hours = location.openingHours;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 52,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                arrivalLabel,
                style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        ReorderableDragStartListener(
          index: index,
          child: Icon(Icons.drag_indicator_rounded, color: context.colors.muted, size: 18),
        ),
        const SizedBox(width: 6),
        Icon(Icons.trip_origin, color: AppColors.accent, size: 14),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(location.categoryIcon, color: AppColors.accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            location.name,
                            style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                          const SizedBox(height: 2),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _Tag(_environmentLabel(env)),
                              _Tag(location.category),
                              if (location.businessStatus == 'CLOSED_PERMANENTLY')
                                _Tag('Permanently closed', warning: true),
                              if (location.businessStatus == 'CLOSED_TEMPORARILY')
                                _Tag('Temporarily closed', warning: true),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: context.colors.muted,
                      tooltip: 'Remove',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Visit: ${_durationLabel(entry.visitMinutes)}',
                      style: TextStyle(color: context.colors.muted, fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                    const Spacer(),
                    _DurationStepper(
                      onDecrease: () => onChangeDuration(-15),
                      onIncrease: () => onChangeDuration(15),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Ends $endLabel',
                  style: TextStyle(color: context.colors.muted, fontWeight: FontWeight.w600, fontSize: 12),
                ),
                if (hours != null && hours.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule_rounded, size: 14, color: context.colors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          hours.first,
                          style: TextStyle(color: context.colors.muted, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(
                    'Opening hours unavailable',
                    style: TextStyle(color: context.colors.muted, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
                if (env == PlaceEnvironment.outdoor || env == PlaceEnvironment.mixed) ...[
                  const SizedBox(height: 6),
                  _StopWeatherRow(available: weatherForecastAvailable, check: weather),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Weather line for an outdoor/mixed stop only — indoor stops never show
/// one at all, matching the "indoor places matter less for weather"
/// framing from the original planning spec.
class _StopWeatherRow extends StatelessWidget {
  const _StopWeatherRow({required this.available, required this.check});

  final bool available;
  final StopWeatherCheck? check;

  @override
  Widget build(BuildContext context) {
    if (!available) {
      return Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 14, color: context.colors.muted),
          const SizedBox(width: 6),
          Text(
            'Weather forecast not available yet',
            style: TextStyle(color: context.colors.muted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }
    final result = check;
    if (result == null || !result.isResolved) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: context.colors.muted),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking weather…',
            style: TextStyle(color: context.colors.muted, fontSize: 12, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }
    final forecast = result.forecast!;
    final phrase = result.periodsSpanned.isEmpty
        ? forecast.summaryForecast
        : forecast.phraseFor(result.periodsSpanned.first);
    if (result.isBad) {
      final periods = result.badPeriods.map(_periodLabel).join(' & ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(weatherIconFor(forecast.phraseFor(result.badPeriods.first)), size: 14, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Weather: ${translateWeather(forecast.phraseFor(result.badPeriods.first))}',
                  style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              'Rain expected in the $periods — move this stop to a different day or time.',
              style: const TextStyle(color: Colors.red, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
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
            style: TextStyle(color: context.colors.muted, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({required this.onDecrease, required this.onIncrease});

  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(icon: Icons.remove_rounded, onTap: onDecrease),
        const SizedBox(width: 4),
        _StepperButton(icon: Icons.add_rounded, onTap: onIncrease),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: context.colors.card, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 15, color: context.colors.ink),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.warning = false});
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? Colors.red : context.colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// One-tap "stay here again tonight" — lets the same accommodation cover
/// multiple consecutive nights without re-searching for it each time.
class _SameAsPreviousChip extends StatelessWidget {
  const _SameAsPreviousChip({required this.location, required this.onTap});

  final TripStopLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.repeat_rounded, size: 15, color: AppColors.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Same as previous night — ${location.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Search sheet for adding a stop — fuzzy free-text search via
/// [GooglePlacesService.textSearch] (Google Places already fuzzy-matches
/// server-side; this just debounces keystrokes rather than hitting the API
/// on every character), plotted live on a small map as results are picked.
/// Returns the confirmed [NearbyPlace] so the caller can hydrate it with
/// full Place Details. [existingPlaceIds] flags a result already on this
/// day's timeline (by Places ID, or coordinates for a result with none) so
/// it can't be added twice.
class _StopSearchSheet extends StatefulWidget {
  const _StopSearchSheet({required this.existingPlaceIds});

  final Set<String> existingPlaceIds;

  @override
  State<_StopSearchSheet> createState() => _StopSearchSheetState();
}

class _StopSearchSheetState extends State<_StopSearchSheet> {
  final _controller = TextEditingController();
  final _placesService = GooglePlacesService();
  final _mapController = MapController();
  Timer? _debounce;

  List<NearbyPlace> _results = [];
  NearbyPlace? _selected;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String _idFor(NearbyPlace place) => place.id;

  bool _isDuplicate(NearbyPlace place) => widget.existingPlaceIds.contains(_idFor(place));

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(_searchDebounce, () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    try {
      // Every Places category is already eligible (no `includedType` is
      // ever sent) — request the API's max per query so a broad term
      // ("food", "clinic", "temple", ...) surfaces a wide spread rather
      // than just the handful of top-ranked, often tourism-heavy hits.
      final results = await _placesService.textSearch(query, maxResultCount: 20);
      if (!mounted) return;
      setState(() {
        _results = [for (final r in results) if (!_isAddressOnly(r)) r];
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Search failed: $e';
        _loading = false;
      });
    }
  }

  bool _isAddressOnly(NearbyPlace place) => TripStopLocation.fromNearbyPlace(place).isAddressOnly;

  void _selectResult(NearbyPlace place) {
    setState(() => _selected = place);
    _mapController.move(LatLng(place.latitude, place.longitude), 15);
  }

  void _confirm() {
    final selected = _selected;
    if (selected == null || _isDuplicate(selected)) return;
    Navigator.of(context).pop(selected);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final duplicate = selected != null && _isDuplicate(selected);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.colors.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add Stop',
                style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  height: 160,
                  child: _SearchMap(mapController: _mapController, selected: selected),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onQueryChanged,
                style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Search a place',
                  hintStyle: TextStyle(color: context.colors.muted),
                  prefixIcon: Icon(Icons.search_rounded, color: context.colors.muted),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  filled: true,
                  fillColor: context.colors.card,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                )
              else
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final place = _results[index];
                      final isSelected = selected != null && _idFor(selected) == _idFor(place);
                      final isDuplicate = _isDuplicate(place);
                      return ListTile(
                        tileColor: isSelected ? AppColors.accent.withValues(alpha: 0.12) : context.colors.card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: isSelected
                              ? const BorderSide(color: AppColors.accent, width: 1.5)
                              : BorderSide.none,
                        ),
                        leading: Icon(place.icon, color: AppColors.accent),
                        title: Text(
                          place.name,
                          style: TextStyle(color: context.colors.ink, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          isDuplicate ? 'Already added to this day' : place.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDuplicate ? Colors.red : context.colors.muted,
                            fontSize: 12,
                            fontWeight: isDuplicate ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        onTap: () => _selectResult(place),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
              if (duplicate)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'This place is already on this day\'s timeline.',
                    style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              Opacity(
                opacity: (selected == null || duplicate) ? 0.5 : 1,
                child: GradientButton(
                  label: 'Add Stop',
                  icon: Icons.add_location_alt_rounded,
                  onPressed: (selected == null || duplicate) ? () {} : _confirm,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchMap extends StatelessWidget {
  const _SearchMap({required this.mapController, required this.selected});

  final MapController mapController;
  final NearbyPlace? selected;

  @override
  Widget build(BuildContext context) {
    final place = selected;
    final center = place == null
        ? const LatLng(3.1390, 101.6869) // Kuala Lumpur fallback
        : LatLng(place.latitude, place.longitude);
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: place == null ? 11 : 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(urlTemplate: _osmTileUrl, userAgentPackageName: _osmUserAgent),
        if (place != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(place.latitude, place.longitude),
                width: 34,
                height: 34,
                alignment: Alignment.center,
                child: const _IconPin(icon: Icons.location_on_rounded, color: Color(0xFFE53935)),
              ),
            ],
          ),
      ],
    );
  }
}

class _IconPin extends StatelessWidget {
  const _IconPin({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
      ),
      child: Icon(icon, color: Colors.white, size: 17),
    );
  }
}
