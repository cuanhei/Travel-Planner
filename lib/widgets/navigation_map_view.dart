import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import 'current_location_marker.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';
const _followZoom = 17.0;

/// Live OpenStreetMap view for turn-by-turn navigation: the traveler's
/// live GPS position (reusing [CurrentLocationMarker]), the current
/// step's target stop, and its polyline. Follows the traveler by
/// default; a manual pan/zoom disengages follow mode and reveals a
/// recenter button, per the "allow the user to recenter" requirement.
class NavigationMapView extends StatefulWidget {
  const NavigationMapView({
    super.key,
    required this.userPosition,
    required this.targetPosition,
    this.targetLabel,
    this.polylinePoints = const [],
    this.polylineColor = const Color(0xFF11998E),
  });

  final LatLng? userPosition;
  final LatLng? targetPosition;
  final String? targetLabel;
  final List<LatLng> polylinePoints;
  final Color polylineColor;

  @override
  State<NavigationMapView> createState() => _NavigationMapViewState();
}

class _NavigationMapViewState extends State<NavigationMapView> {
  final _mapController = MapController();
  bool _following = true;
  LatLng? _lastFollowedPosition;

  @override
  void didUpdateWidget(covariant NavigationMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final user = widget.userPosition;
    if (_following &&
        user != null &&
        isValidLatLng(user) &&
        user != _lastFollowedPosition) {
      _lastFollowedPosition = user;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(user, _mapController.camera.zoom);
      });
    }
  }

  void _recenter() {
    final user = widget.userPosition;
    setState(() => _following = true);
    if (user != null && isValidLatLng(user)) {
      _lastFollowedPosition = user;
      _mapController.move(user, _followZoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.userPosition != null && isValidLatLng(widget.userPosition!)
        ? widget.userPosition
        : null;
    final target = widget.targetPosition != null && isValidLatLng(widget.targetPosition!)
        ? widget.targetPosition
        : null;
    final polylinePoints = widget.polylinePoints.where(isValidLatLng).toList();
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter:
                user ?? target ?? const LatLng(3.1390, 101.6869),
            initialZoom: _followZoom,
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _following) {
                setState(() => _following = false);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: _osmTileUrl,
              userAgentPackageName: _osmUserAgent,
            ),
            if (polylinePoints.length > 1)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: polylinePoints,
                    strokeWidth: 5,
                    color: widget.polylineColor,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (target != null)
                  Marker(
                    point: target,
                    width: 42,
                    height: 42,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFFFF7A59),
                      size: 40,
                    ),
                  ),
                if (user != null)
                  Marker(
                    point: user,
                    width: 54,
                    height: 54,
                    child: const CurrentLocationMarker(),
                  ),
              ],
            ),
          ],
        ),
        if (!_following)
          Positioned(
            right: 14,
            bottom: 14,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _recenter,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(
                    Icons.my_location_rounded,
                    color: Color(0xFF0B1D3A),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
