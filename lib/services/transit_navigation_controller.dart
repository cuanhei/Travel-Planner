import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/transit_route.dart';
import '../models/trip_stop_location.dart';
import '../utils/geo.dart';
import 'route_service.dart';

/// Distance (meters) within which the traveler is considered to have
/// reached a walking target (a boarding stop, a transfer stop, or the
/// final destination).
const kWalkArrivalThresholdMeters = 25.0;

/// Distance (meters) within which the traveler is considered to have
/// reached/boarded-off at a transit alighting stop. Larger than the walk
/// threshold since transit GPS fixes are noisier (moving vehicle, indoor).
const kTransitArrivalThresholdMeters = 60.0;

/// Distance (meters) at which "approaching alighting stop" is surfaced.
const kApproachingAlightThresholdMeters = 300.0;

/// How far (meters) off a walking step's polyline the traveler must
/// drift, sustained across [kOffRouteConfirmationSamples] fixes, before
/// a reroute is triggered.
const kOffRouteThresholdMeters = 45.0;
const kOffRouteConfirmationSamples = 3;

/// Minimum time between reroute requests, so a lingering off-route
/// traveler doesn't spam the Routes API on every GPS fix.
const kMinRerouteInterval = Duration(seconds: 20);

/// GPS distance filter — how far (meters) the device must move before a
/// new position is delivered, which is what actually keeps this feature
/// from reacting (and potentially rerouting) on every tiny GPS jitter.
const kPositionDistanceFilterMeters = 5;

enum NavigationStatus {
  /// [start] hasn't been called yet, or [stop] was called.
  idle,

  /// Waiting on location permission/GPS before the first fix arrives.
  starting,

  /// Actively walking toward a boarding stop, a transfer stop, or the
  /// final destination.
  walking,

  /// Riding a transit leg, not yet near the alighting stop.
  transit,

  /// Riding a transit leg and near enough to the alighting stop that the
  /// UI should tell the traveler to get ready.
  approachingAlight,

  /// The whole journey's final step has been completed.
  arrived,

  /// Location permission/service/GPS failed — navigation can't proceed.
  error,
}

/// Drives live public-transport navigation for one already-selected
/// [TransitRoute]: walks its `steps` (WALK/TRANSIT) in order, tracks the
/// traveler's live GPS position against the current step, and decides
/// when to advance, warn ("approaching alighting stop"), or reroute the
/// current walking segment. Deliberately reuses [TransitRoute] and its
/// step/leg models rather than a parallel navigation-specific structure.
///
/// API logic (Google Routes, via [RouteService]) and GPS logic (via
/// `geolocator`) are both owned here, kept out of the UI layer — screens
/// only ever read [status]/[currentStep]/etc. and call [start]/[stop].
class TransitNavigationController extends ChangeNotifier {
  TransitNavigationController({
    required this.route,
    required this.departure,
    required this.destination,
    RouteService? routeService,
  }) : _routeService = routeService ?? RouteService();

  final TransitRoute route;
  final TripStopLocation departure;
  final TripStopLocation destination;
  final RouteService _routeService;

  StreamSubscription<Position>? _positionSub;

  NavigationStatus _status = NavigationStatus.idle;
  NavigationStatus get status => _status;

  String? _error;
  String? get error => _error;

  int _currentStepIndex = 0;
  int get currentStepIndex => _currentStepIndex;

  TransitStep get currentStep => route.steps[_currentStepIndex];

  bool get isLastStep => _currentStepIndex == route.steps.length - 1;

  LatLng? _currentUserPosition;
  LatLng? get currentUserPosition => _currentUserPosition;

  /// Live-rerouted polyline for the current WALK step, when the
  /// traveler has drifted off the original one. Null means "use
  /// `currentStep.polylinePoints` as-is".
  List<LatLng>? _rerouteOverride;
  List<LatLng> get currentStepPolyline =>
      _rerouteOverride ?? currentStep.polylinePoints;

  /// Remaining distance (meters) to the current step's target — the
  /// next boarding stop, the alighting stop, or the final destination.
  double? _remainingDistanceMeters;
  double? get remainingDistanceMeters => _remainingDistanceMeters;

  /// Estimated stops remaining on the current TRANSIT step, derived from
  /// how far along the step's polyline the traveler has progressed.
  /// Null when the API didn't return a stop count for this leg.
  int? _stopsRemaining;
  int? get stopsRemaining => _stopsRemaining;

  /// True for a brief window once the traveler is close enough to the
  /// current TRANSIT step's alighting stop — the UI shows "Get off
  /// here" during this window, before automatically advancing.
  bool _showAlightBanner = false;
  bool get showAlightBanner => _showAlightBanner;
  Timer? _alightBannerTimer;

  bool _isRerouting = false;
  bool get isRerouting => _isRerouting;

  int _offRouteStreak = 0;
  DateTime? _lastRerouteAt;

  /// True once the final step has been completed.
  bool get hasArrived => _status == NavigationStatus.arrived;

  /// Starts listening to GPS and begins tracking [route] from its first
  /// step. Safe to call only once per controller instance; create a new
  /// controller to restart. Handles every permission/service outcome
  /// without throwing — failures surface via [status] == error and
  /// [error].
  Future<void> start() async {
    if (_status != NavigationStatus.idle) return;
    _status = NavigationStatus.starting;
    notifyListeners();

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fail('Location services are turned off.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _fail('Location permission is permanently denied. Enable it in Settings.');
        return;
      }
      if (permission == LocationPermission.denied) {
        _fail('Location permission is required for navigation.');
        return;
      }
    } catch (_) {
      _fail('Could not check location permission.');
      return;
    }

    _currentStepIndex = 0;
    _status = _statusForStepType(currentStep.type);
    notifyListeners();

    final settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: kPositionDistanceFilterMeters,
    );
    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(_onPosition, onError: (_) => _fail('Lost GPS signal.'));
  }

  /// Stops the GPS stream and resets to idle. Safe to call multiple
  /// times, and called automatically from [dispose].
  void stop() {
    _positionSub?.cancel();
    _positionSub = null;
    _alightBannerTimer?.cancel();
    if (_status != NavigationStatus.arrived) {
      _status = NavigationStatus.idle;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _alightBannerTimer?.cancel();
    super.dispose();
  }

  void _fail(String message) {
    _positionSub?.cancel();
    _positionSub = null;
    _alightBannerTimer?.cancel();
    _status = NavigationStatus.error;
    _error = message;
    notifyListeners();
  }

  NavigationStatus _statusForStepType(TransitStepType type) =>
      type == TransitStepType.walk
          ? NavigationStatus.walking
          : NavigationStatus.transit;

  void _onPosition(Position position) {
    _currentUserPosition = LatLng(position.latitude, position.longitude);
    if (currentStep.type == TransitStepType.walk) {
      _handleWalkProgress();
    } else {
      _handleTransitProgress();
    }
    notifyListeners();
  }

  /// The point the traveler is walking toward for the current WALK step:
  /// the next step's boarding stop if there is a following TRANSIT step,
  /// otherwise the trip's final destination.
  LatLng get walkTargetPosition {
    if (!isLastStep) {
      final next = route.steps[_currentStepIndex + 1];
      final target = next.details?.departureStopLocation ?? next.startLocation;
      if (target != null) return target;
    }
    return LatLng(destination.latitude, destination.longitude);
  }

  /// Human label for [walkTargetPosition] — the next boarding stop's
  /// name, or the trip's destination name for the final walk.
  String get walkTargetLabel {
    if (!isLastStep) {
      final next = route.steps[_currentStepIndex + 1];
      final name = next.details?.departureStop;
      if (name != null && name.isNotEmpty) return name;
    }
    return destination.name;
  }

  void _handleWalkProgress() {
    final user = _currentUserPosition;
    if (user == null) return;
    final target = walkTargetPosition;
    _remainingDistanceMeters = haversineMeters(user, target);
    _stopsRemaining = null;

    if (_remainingDistanceMeters! <= kWalkArrivalThresholdMeters) {
      _advanceStep();
      return;
    }

    _checkOffRoute(user);
  }

  void _checkOffRoute(LatLng user) {
    final polyline = currentStepPolyline;
    if (polyline.length < 2) return;
    final projection = projectOntoPolyline(user, polyline);
    if (projection == null) return;

    if (projection.distanceToLineMeters <= kOffRouteThresholdMeters) {
      _offRouteStreak = 0;
      return;
    }

    _offRouteStreak++;
    if (_offRouteStreak < kOffRouteConfirmationSamples) return;
    _offRouteStreak = 0;

    final now = DateTime.now();
    if (_isRerouting ||
        (_lastRerouteAt != null &&
            now.difference(_lastRerouteAt!) < kMinRerouteInterval)) {
      return;
    }
    _rerouteWalkFrom(user);
  }

  Future<void> _rerouteWalkFrom(LatLng user) async {
    _isRerouting = true;
    _lastRerouteAt = DateTime.now();
    notifyListeners();
    try {
      final walking = await _routeService.getWalkingRoute(
        origin: user,
        destination: walkTargetPosition,
      );
      if (walking != null && walking.polylinePoints.length > 1) {
        _rerouteOverride = walking.polylinePoints;
      }
    } catch (_) {
      // Keep the original polyline — off-route detection will simply
      // retry after the next reroute interval elapses.
    } finally {
      _isRerouting = false;
      notifyListeners();
    }
  }

  void _handleTransitProgress() {
    final user = _currentUserPosition;
    final details = currentStep.details;
    if (user == null || details == null) return;

    final alightPoint = details.arrivalStopLocation;
    if (alightPoint == null) {
      // No alighting coordinates from the API — fall back to duration-
      // based guidance only; the UI still shows line/stop names.
      return;
    }

    _remainingDistanceMeters = haversineMeters(user, alightPoint);

    final polyline = currentStep.polylinePoints;
    final totalStops = details.stopCount;
    if (totalStops != null && totalStops > 0 && polyline.length > 1) {
      final projection = projectOntoPolyline(user, polyline);
      if (projection != null) {
        _stopsRemaining =
            ((1 - projection.fraction) * totalStops).round().clamp(0, totalStops);
      }
    }

    if (_remainingDistanceMeters! <= kTransitArrivalThresholdMeters) {
      _status = NavigationStatus.approachingAlight;
      if (!_showAlightBanner) {
        _showAlightBanner = true;
        _alightBannerTimer?.cancel();
        _alightBannerTimer = Timer(const Duration(seconds: 4), () {
          _showAlightBanner = false;
          _advanceStep();
          notifyListeners();
        });
      }
      return;
    }

    _status = _remainingDistanceMeters! <= kApproachingAlightThresholdMeters
        ? NavigationStatus.approachingAlight
        : NavigationStatus.transit;
  }

  void _advanceStep() {
    _rerouteOverride = null;
    _offRouteStreak = 0;
    _stopsRemaining = null;
    _showAlightBanner = false;

    if (isLastStep) {
      _status = NavigationStatus.arrived;
      _positionSub?.cancel();
      _positionSub = null;
      return;
    }

    _currentStepIndex++;
    _status = _statusForStepType(currentStep.type);
  }
}
