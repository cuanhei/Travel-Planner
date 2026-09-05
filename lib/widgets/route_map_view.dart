import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../utils/geo.dart';
import 'current_location_marker.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';

const _malaysiaFallbackCenter = LatLng(3.1390, 101.6869);

final _malaysiaBounds = LatLngBounds(
  const LatLng(0.5, 99.5),
  const LatLng(7.5, 119.5),
);

const _closeZoom = 16.0;

class RouteMapView extends StatelessWidget {
  const RouteMapView({
    super.key,
    this.source,
    this.destination,
    this.polylinePoints = const [],
    this.polylineColor = const Color(0xFF11998E),
    this.height = 240,
    this.borderRadius = 24,
    this.sourceIsCurrentLocation = false,
  });

  final LatLng? source;
  final LatLng? destination;
  final List<LatLng> polylinePoints;
  final Color polylineColor;

  final double? height;
  final double borderRadius;

  final bool sourceIsCurrentLocation;

  String _pointKey(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  String get _cameraKey {
    final parts = <String>[
      if (source != null) 's:${_pointKey(source!)}',
      if (destination != null) 'd:${_pointKey(destination!)}',
      if (polylinePoints.isNotEmpty)
        'p:${polylinePoints.length}:${_pointKey(polylinePoints.first)}:${_pointKey(polylinePoints.last)}',
    ];
    return parts.join('|');
  }

  @override
  Widget build(BuildContext context) {
    final validSource = source != null && isValidLatLng(source!)
        ? source
        : null;
    final validDestination = destination != null && isValidLatLng(destination!)
        ? destination
        : null;
    final validPolylinePoints = polylinePoints.where(isValidLatLng).toList();

    final points = [?validSource, ?validDestination, ...validPolylinePoints];
    final bounds = points.isEmpty ? null : LatLngBounds.fromPoints(points);

    final map = FlutterMap(
      key: ValueKey(_cameraKey),
      options: MapOptions(
        initialCenter: points.isEmpty
            ? _malaysiaFallbackCenter
            : (points.length == 1 ? points.first : bounds!.center),
        initialZoom: points.isEmpty ? 6 : _closeZoom,
        initialCameraFit: points.length > 1
            ? CameraFit.bounds(
                bounds: bounds!,
                padding: const EdgeInsets.all(44),
                maxZoom: _closeZoom,
              )
            : null,
        cameraConstraint: CameraConstraint.contain(bounds: _malaysiaBounds),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _osmTileUrl,
          userAgentPackageName: _osmUserAgent,
        ),
        if (validPolylinePoints.length > 1)
          PolylineLayer(
            polylines: [
              Polyline(
                points: validPolylinePoints,
                strokeWidth: 4.5,
                color: polylineColor,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            if (validSource != null)
              Marker(
                point: validSource,
                width: sourceIsCurrentLocation ? 54 : 34,
                height: sourceIsCurrentLocation ? 54 : 34,

                alignment: sourceIsCurrentLocation
                    ? Alignment.center
                    : Alignment.bottomCenter,
                child: sourceIsCurrentLocation
                    ? const CurrentLocationMarker()
                    : const Icon(
                        Icons.trip_origin_rounded,
                        color: Color(0xFF5C6BC0),
                        size: 28,
                      ),
              ),
            if (validDestination != null)
              Marker(
                point: validDestination,
                width: 40,
                height: 40,

                alignment: Alignment.bottomCenter,
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFFFF7A59),
                  size: 38,
                ),
              ),
          ],
        ),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: height == null
          ? SizedBox.expand(child: map)
          : SizedBox(height: height, child: map),
    );
  }
}
