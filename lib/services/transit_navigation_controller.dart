import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/transit_route.dart';
import '../models/trip_stop_location.dart';
import '../utils/geo.dart';
import 'route_service.dart';

const kWalkArrivalThresholdMeters = 25.0;

const kTransitArrivalThresholdMeters = 60.0;

const kApproachingAlightThresholdMeters = 300.0;

const kOffRouteThresholdMeters = 45.0;
const kOffRouteConfirmationSamples = 3;

const kMinRerouteInterval = Duration(seconds: 20);

const kPositionDistanceFilterMeters = 5;

enum NavigationStatus {
  idle,

  starting,

  walking,

  transit,

  approachingAlight,

  arrived,

  error,
}

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

  List<LatLng>? _rerouteOverride;
  List<LatLng> get currentStepPolyline =>
      _rerouteOverride ?? currentStep.polylinePoints;

  double? _remainingDistanceMeters;
  double? get remainingDistanceMeters => _remainingDistanceMeters;

  int? _stopsRemaining;
  int? get stopsRemaining => _stopsRemaining;

  bool _showAlightBanner = false;
  bool get showAlightBanner => _showAlightBanner;
  Timer? _alightBannerTimer;

  bool _isRerouting = false;
  bool get isRerouting => _isRerouting;

  int _offRouteStreak = 0;
  DateTime? _lastRerouteAt;

  bool get hasArrived => _status == NavigationStatus.arrived;

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
        _fail(
          'Location permission is permanently denied. Enable it in Settings.',
        );
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
    _positionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(_onPosition, onError: (_) => _fail('Lost GPS signal.'));
  }

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

  LatLng get walkTargetPosition {
    if (!isLastStep) {
      final next = route.steps[_currentStepIndex + 1];
      final target = next.details?.departureStopLocation ?? next.startLocation;
      if (target != null) return target;
    }
    return LatLng(destination.latitude, destination.longitude);
  }

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
      return;
    }

    _remainingDistanceMeters = haversineMeters(user, alightPoint);

    final polyline = currentStep.polylinePoints;
    final totalStops = details.stopCount;
    if (totalStops != null && totalStops > 0 && polyline.length > 1) {
      final projection = projectOntoPolyline(user, polyline);
      if (projection != null) {
        _stopsRemaining = ((1 - projection.fraction) * totalStops)
            .round()
            .clamp(0, totalStops);
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
