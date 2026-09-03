import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'current_location_marker.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';

/// Kuala Lumpur — used to center the map when neither [RouteMapView.source]
/// nor [RouteMapView.destination] is known yet.
const _malaysiaFallbackCenter = LatLng(3.1390, 101.6869);

/// west,south,east,north — a loose box around all of Malaysia (mirrors
/// the same bbox used elsewhere for Photon search/`StopMapPicker`), so
/// none of this app's maps can be panned/zoomed out to see other
/// countries.
final _malaysiaBounds = LatLngBounds(
  const LatLng(0.5, 99.5),
  const LatLng(7.5, 119.5),
);

const _closeZoom = 16.0;

/// Guards against malformed coordinates (e.g. a corrupted polyline point
/// from a routing API response) reaching [LatLngBounds], whose
/// constructor throws an assertion error outside the valid lat/lng range
/// instead of failing gracefully.
bool _isValidLatLng(LatLng point) =>
    point.latitude.isFinite &&
    point.longitude.isFinite &&
    point.latitude >= -90 &&
    point.latitude <= 90 &&
    point.longitude >= -180 &&
    point.longitude <= 180;

/// Read-only OpenStreetMap view (via flutter_map), constrained to
/// Malaysia. Renders whichever of [source]/[destination] are known — so
/// the same widget instance can stay mounted for the Transport screen's
/// single persistent map area across its whole lifecycle: an empty/
/// current-location view before both endpoints are picked, then source+
/// destination markers, then a route polyline once one is available.
/// Also reused by the full route-details view and the Home dashboard's
/// map, where a plain search result is "plotted" the same way.
///
/// The inner `FlutterMap` is keyed off [source]/[destination]/the
/// polyline's start+end, so a meaningful change (GPS resolves, a new
/// place is searched, a different route is selected) tears down and
/// remounts it with a fresh `initialCenter`/`initialCameraFit` rather
/// than nudging the already-mounted map via `MapController`.
/// flutter_map's tile layer only reliably reloads tiles for a new
/// viewport when the map is (re)built with that viewport from the
/// start — moving an existing controller straight after a rebuild can
/// leave the tiles blank until the traveler manually pans/zooms.
/// Panning/zooming the traveler does themselves (with the same points
/// still in effect) doesn't change the key, so their manual view isn't
/// reset by unrelated rebuilds.
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

  /// Fixed height for the map. Pass null to instead fill whatever space
  /// the parent gives it (e.g. inside an `Expanded`) — a plain
  /// `SizedBox(height: double.infinity)` isn't safe to lay out.
  final double? height;
  final double borderRadius;

  /// When true, [source] is rendered as the pulsing "you are here" dot
  /// ([CurrentLocationMarker]) instead of the plain origin pin — for
  /// screens where `source` really is the traveler's live GPS position
  /// rather than a route's starting point.
  final bool sourceIsCurrentLocation;

  String _pointKey(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';

  /// A cheap signature of "what should the camera be framing" — the
  /// full polyline is represented by just its length + endpoints rather
  /// than scanned point-by-point, since only a materially different
  /// route (not e.g. a rebuild with the same one) should force a remount.
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
    final validSource = source != null && _isValidLatLng(source!) ? source : null;
    final validDestination =
        destination != null && _isValidLatLng(destination!) ? destination : null;
    final validPolylinePoints = polylinePoints.where(_isValidLatLng).toList();

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
