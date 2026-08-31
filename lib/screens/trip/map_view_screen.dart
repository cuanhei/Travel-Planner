import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../models/transport_location.dart';
import '../../theme/app_theme.dart';
import '../../widgets/current_location_marker.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/map_label_pill.dart';
import '../../widgets/route_map_view.dart';
import '../../widgets/street_map_painter.dart';
import '../../widgets/transport_location_search_field.dart';

/// From the home dashboard (default), a real OpenStreetMap centered on
/// the traveler's current GPS location with a Photon-backed search bar —
/// searching a place plots it as a single marker, replacing whichever
/// place was searched before. From Trip Details, [showStops] instead
/// plots the trip's stops and the (still UI-only, stylized) route
/// between them — untouched by the home-dashboard map above.
class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key, this.showStops = false});

  /// When true, plots the trip's stops and the dashed route between
  /// them in addition to the current-location marker.
  final bool showStops;

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  LatLng? _currentPosition;
  bool _locatingCurrentPosition = false;
  String? _locationError;
  TransportLocation? _searchedLocation;

  @override
  void initState() {
    super.initState();
    if (!widget.showStops) _locateCurrentPosition();
  }

  /// One-shot GPS fetch for the "you are here" marker — mirrors the
  /// Transport screen's Depart From permission handling, and never
  /// blocks the map: on any failure the map just falls back to a
  /// Malaysia-wide view and search still works.
  Future<void> _locateCurrentPosition() async {
    setState(() {
      _locatingCurrentPosition = true;
      _locationError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _failLocate('Location services are turned off.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _failLocate(
          'Location permission is permanently denied. Enable it in Settings.',
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _failLocate('Location permission denied.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _locatingCurrentPosition = false;
      });
    } catch (_) {
      _failLocate('Unable to retrieve your current location.');
    }
  }

  void _failLocate(String message) {
    if (!mounted) return;
    setState(() {
      _locatingCurrentPosition = false;
      _locationError = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Map View',
              subtitle: widget.showStops
                  ? 'Your route across Penang'
                  : 'Search anywhere in Malaysia',
            ),
            Expanded(
              child: widget.showStops
                  ? const _TripStopsMapView()
                  : _HomeMapView(
                      currentPosition: _currentPosition,
                      locating: _locatingCurrentPosition,
                      locationError: _locationError,
                      searchedLocation: _searchedLocation,
                      onSearchedLocationChanged: (loc) =>
                          setState(() => _searchedLocation = loc),
                      onRetryLocate: _locateCurrentPosition,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeMapView extends StatelessWidget {
  const _HomeMapView({
    required this.currentPosition,
    required this.locating,
    required this.locationError,
    required this.searchedLocation,
    required this.onSearchedLocationChanged,
    required this.onRetryLocate,
  });

  final LatLng? currentPosition;
  final bool locating;
  final String? locationError;
  final TransportLocation? searchedLocation;
  final ValueChanged<TransportLocation?> onSearchedLocationChanged;
  final VoidCallback onRetryLocate;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TransportLocationSearchField(
            value: searchedLocation,
            onChanged: onSearchedLocationChanged,
            hintText: 'Search a place in Malaysia…',
            selectedIcon: Icons.location_on_rounded,
          ),
          if (locationError != null && currentPosition == null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    locationError!,
                    style: const TextStyle(
                      color: Color(0xFFB3541E),
                      fontSize: 11.5,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onRetryLocate,
                  child: Text(
                    'Retry',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: RouteMapView(
              source: currentPosition,
              destination: searchedLocation == null
                  ? null
                  : LatLng(
                      searchedLocation!.latitude,
                      searchedLocation!.longitude,
                    ),
              sourceIsCurrentLocation: true,
              height: null,
              borderRadius: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _TripStopsMapView extends StatelessWidget {
  const _TripStopsMapView();

  static const _currentLocationName = 'Komtar, George Town';
  static const _currentLocation = Alignment(0, -0.1);

  static List<({String name, double top, double left, Color color})> _pins(
    BuildContext context,
  ) => [
    (name: 'Komtar', top: 0.28, left: 0.30, color: context.colors.ink),
    (name: 'Gurney', top: 0.52, left: 0.68, color: Color(0xFF5C6BC0)),
    (name: 'Queensbay', top: 0.78, left: 0.40, color: Color(0xFFFF7A59)),
  ];

  @override
  Widget build(BuildContext context) {
    final pins = _pins(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          decoration: BoxDecoration(color: Color(0xFFEFEDE6)),
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: StreetMapPainter()),
              ),
              CustomPaint(
                size: Size.infinite,
                painter: _RoutePainter(
                  points: pins.map((p) => Offset(p.left, p.top)).toList(),
                  color: context.colors.ink,
                ),
              ),
              ...pins.map((pin) {
                return Align(
                  alignment: Alignment(pin.left * 2 - 1, pin.top * 2 - 1),
                  child: _MapPin(label: pin.name, color: pin.color),
                );
              }),
              Align(
                alignment: _currentLocation,
                child: const CurrentLocationMarker(),
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: MapLabelPill(
                  text: 'You are here · $_currentLocationName',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(height: 2),
        Icon(Icons.location_on_rounded, color: color, size: 30),
      ],
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.points, required this.color});

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(dashPath(path, dashLength: 6, gapLength: 5), paint);
  }

  Path dashPath(
    Path source, {
    required double dashLength,
    required double gapLength,
  }) {
    final dest = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var draw = true;
      while (distance < metric.length) {
        final len = draw ? dashLength : gapLength;
        final next = (distance + len).clamp(0, metric.length).toDouble();
        if (draw) {
          dest.addPath(metric.extractPath(distance, next), Offset.zero);
        }
        distance = next;
        draw = !draw;
      }
    }
    return dest;
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      color != oldDelegate.color || points != oldDelegate.points;
}
