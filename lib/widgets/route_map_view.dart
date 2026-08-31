import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';

/// Kuala Lumpur — used to center the map when neither [RouteMapView.source]
/// nor [RouteMapView.destination] is known yet.
const _malaysiaFallbackCenter = LatLng(3.1390, 101.6869);

/// Read-only OpenStreetMap view (via flutter_map). Renders whichever of
/// [source]/[destination] are known — so the same widget instance can
/// stay mounted for the Transport screen's single persistent map area
/// across its whole lifecycle: an empty/current-location view before
/// both endpoints are picked, then source+destination markers, then a
/// route polyline once one is available. Also reused by the full
/// route-details view, where both endpoints and a polyline are always
/// present.
class RouteMapView extends StatelessWidget {
  const RouteMapView({
    super.key,
    this.source,
    this.destination,
    this.polylinePoints = const [],
    this.polylineColor = const Color(0xFF11998E),
    this.height = 240,
    this.borderRadius = 24,
  });

  final LatLng? source;
  final LatLng? destination;
  final List<LatLng> polylinePoints;
  final Color polylineColor;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final points = [?source, ?destination, ...polylinePoints];
    final bounds = points.isEmpty ? null : LatLngBounds.fromPoints(points);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: bounds?.center ?? _malaysiaFallbackCenter,
            initialZoom: bounds == null ? 6 : 14,
            initialCameraFit: bounds == null
                ? null
                : CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(44),
                    maxZoom: 16,
                  ),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
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
                    strokeWidth: 4.5,
                    color: polylineColor,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (source != null)
                  Marker(
                    point: source!,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.trip_origin_rounded,
                      color: Color(0xFF5C6BC0),
                      size: 28,
                    ),
                  ),
                if (destination != null)
                  Marker(
                    point: destination!,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.location_on_rounded,
                      color: Color(0xFFFF7A59),
                      size: 38,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
