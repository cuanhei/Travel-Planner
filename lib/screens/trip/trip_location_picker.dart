import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip_stop_location.dart';
import '../../utils/malaysia_bounds.dart';
import '../../widgets/google_place_search_field.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';
const _stopMarkerColor = Color(0xFFFF7A59);
const _pendingMarkerColor = Color(0xFF1E88E5);
const _closeZoom = 15.0;

/// Real map + place search for picking a trip's stops — search is via
/// Google Places API (New) Text Search (see [GooglePlacesService]), the
/// same backend Explore's Nearby Places uses, rather than Photon: a
/// picked stop carries its Google category and opening-hours data
/// (regular hours, near-term hours reflecting holiday closures, and
/// open-now) alongside name/coordinates (see
/// [TripStopLocation.fromNearbyPlace]) — Photon never had any of that.
/// Adapted here for picking *multiple* stops instead of a single
/// destination. Tapping a search result doesn't add it right away: it's
/// plotted on the map as a pending pin (distinct color) with an "Add to
/// Trip" button next to its name, so the traveler can see exactly where
/// it is before committing — tapping Add calls [onAdd] and the map
/// re-fits to show every stop picked so far. Removing a stop (via the
/// chip list below this widget, in the parent) is reflected the next
/// time [stops] changes.
class TripLocationPicker extends StatefulWidget {
  const TripLocationPicker({
    super.key,
    required this.stops,
    required this.onAdd,
  });

  final List<TripStopLocation> stops;
  final ValueChanged<TripStopLocation> onAdd;

  @override
  State<TripLocationPicker> createState() => _TripLocationPickerState();
}

class _TripLocationPickerState extends State<TripLocationPicker> {
  /// The result the traveler just tapped, plotted on the map but not yet
  /// added to the trip — cleared either by confirming (Add to Trip) or
  /// dismissing it. While non-null, [GooglePlaceSearchField] is
  /// unmounted (swapped for [_PendingStopRow]) rather than merely
  /// hidden, so it starts fresh — empty query, no stale results — the
  /// next time a traveler searches again.
  TripStopLocation? _pendingStop;

  void _confirmPending() {
    final stop = _pendingStop;
    if (stop == null) return;
    widget.onAdd(stop);
    setState(() => _pendingStop = null);
  }

  void _dismissPending() {
    setState(() => _pendingStop = null);
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingStop;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pending == null)
          GooglePlaceSearchField(
            onChanged: (stop) => setState(() => _pendingStop = stop),
            isResultDisabled: widget.stops.contains,
            hintText: 'Search for a place to add…',
          )
        else
          _PendingStopRow(
            stop: pending,
            onConfirm: _confirmPending,
            onDismiss: _dismissPending,
          ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 220,
            child: _StopsMap(stops: widget.stops, pendingStop: pending),
          ),
        ),
      ],
    );
  }
}

/// Replaces [GooglePlaceSearchField] while a search result is staged but
/// not yet added — same 46px white pill chrome, showing the pending
/// stop's name plus Add/dismiss actions instead of the search box.
class _PendingStopRow extends StatelessWidget {
  const _PendingStopRow({
    required this.stop,
    required this.onConfirm,
    required this.onDismiss,
  });

  final TripStopLocation stop;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              color: _pendingMarkerColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stop.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: const Color(0xFF11998E),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onConfirm,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 15, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'Add to Trip',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xFF6E7A93),
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plots every added [stops] as a marker, plus [pendingStop] (a just-
/// searched result not added yet) in a distinct color. Auto-fits the
/// camera: focuses closely on [pendingStop] when there is one (so the
/// traveler can see exactly where it is before adding it), otherwise
/// fits every added stop, falling back to a Malaysia-wide view when
/// there are none yet. Remounts (via a key derived from the camera
/// target) on every change so the camera fit recomputes; flutter_map's
/// tile layer doesn't reliably reload tiles for a new viewport
/// otherwise.
class _StopsMap extends StatelessWidget {
  const _StopsMap({required this.stops, required this.pendingStop});

  final List<TripStopLocation> stops;
  final TripStopLocation? pendingStop;

  @override
  Widget build(BuildContext context) {
    final points = [for (final s in stops) LatLng(s.latitude, s.longitude)];
    final bounds = points.isEmpty ? null : LatLngBounds.fromPoints(points);
    final pending = pendingStop;
    final pendingPoint = pending == null
        ? null
        : LatLng(pending.latitude, pending.longitude);

    final cameraKey = pendingPoint != null
        ? 'pending:${pendingPoint.latitude.toStringAsFixed(5)},${pendingPoint.longitude.toStringAsFixed(5)}'
        : 'stops:${stops.length}';

    return FlutterMap(
      key: ValueKey(cameraKey),
      options: MapOptions(
        initialCenter: pendingPoint ?? bounds?.center ?? malaysiaFallbackCenter,
        initialZoom: pendingPoint != null || bounds == null ? _closeZoom : 12,
        initialCameraFit: pendingPoint == null && bounds != null
            ? CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.all(36),
                maxZoom: _closeZoom,
              )
            : null,
        cameraConstraint: CameraConstraint.contain(bounds: malaysiaBounds),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: _osmTileUrl,
          userAgentPackageName: _osmUserAgent,
        ),
        MarkerLayer(
          markers: [
            for (final stop in stops)
              Marker(
                point: LatLng(stop.latitude, stop.longitude),
                width: 34,
                height: 34,
                alignment: Alignment.bottomCenter,
                child: const Icon(
                  Icons.location_on_rounded,
                  color: _stopMarkerColor,
                  size: 34,
                ),
              ),
            if (pendingPoint != null)
              Marker(
                point: pendingPoint,
                width: 38,
                height: 38,
                alignment: Alignment.bottomCenter,
                child: const Icon(
                  Icons.location_on_rounded,
                  color: _pendingMarkerColor,
                  size: 38,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
