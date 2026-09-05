import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip_stop_location.dart';
import '../../services/google_places_service.dart';
import '../../utils/malaysia_bounds.dart';
import '../../widgets/location_search_field.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';
const _stopMarkerColor = Color(0xFFFF7A59);
const _pendingMarkerColor = Color(0xFF1E88E5);
const _closeZoom = 15.0;
const _searchDebounce = Duration(milliseconds: 400);

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
  /// dismissing it. While non-null, [_GoogleStopSearchField] is unmounted
  /// (swapped for [_PendingStopRow]) rather than merely hidden, so it
  /// starts fresh — empty query, no stale results — the next time a
  /// traveler searches again.
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
          _GoogleStopSearchField(
            onChanged: (stop) => setState(() => _pendingStop = stop),
            isResultDisabled: widget.stops.contains,
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

/// Replaces [_GoogleStopSearchField] while a search result is staged but
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

/// Search-as-you-type field for picking a stop via Google Places Text
/// Search — same 46px white pill chrome and [LocationResultsDropdown] as
/// the shared Photon-backed [LocationSearchField], but never shows a
/// "selected" read-only state: picking a result here immediately calls
/// [onChanged] with the converted [TripStopLocation] (see
/// [TripStopLocation.fromNearbyPlace]) and the parent stages it as a
/// pending pin rather than this field holding a selection itself.
class _GoogleStopSearchField extends StatefulWidget {
  const _GoogleStopSearchField({
    required this.onChanged,
    required this.isResultDisabled,
  });

  final ValueChanged<TripStopLocation> onChanged;
  final bool Function(TripStopLocation) isResultDisabled;

  @override
  State<_GoogleStopSearchField> createState() => _GoogleStopSearchFieldState();
}

class _GoogleStopSearchFieldState extends State<_GoogleStopSearchField> {
  final _placesService = GooglePlacesService();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<TripStopLocation> _results = const [];
  bool _searching = false;
  String? _error;
  bool _hasSearched = false;

  /// True while fetching the full Place Details for a just-tapped result
  /// (see [_select]) — the search box shows a loading state instead of
  /// its normal query/results UI during this brief window.
  bool _fetchingDetails = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
        _hasSearched = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(_searchDebounce, () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    try {
      final places = await _placesService.textSearch(query);
      if (!mounted) return;
      setState(() {
        final all = [
          for (final p in places) TripStopLocation.fromNearbyPlace(p),
        ];
        // Prefer dropping address/administrative-area-only results (a
        // bare street, postal code, locality, ...) — useless as a trip
        // stop (no business status, no opening hours) and confusing
        // alongside an actual POI/business/attraction for the same
        // query. But if that would filter out *every* result — Google's
        // top matches for some landmark queries are occasionally
        // address-only with no separate POI entry returned at all — show
        // the unfiltered list instead of leaving the traveler with
        // nothing to pick.
        final poiOnly = all.where((s) => !s.isAddressOnly).toList();
        _results = poiOnly.isNotEmpty ? poiOnly : all;
        _searching = false;
        _error = null;
        _hasSearched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _error =
            'Could not search places. Check your connection and try again.';
        _hasSearched = true;
      });
    }
  }

  /// Fetches the full Place Details for the tapped [stop] (via its
  /// [TripStopLocation.placeId]) before staging it as pending, so the
  /// stop that actually gets added carries fresh, complete data rather
  /// than whatever the search result's field mask happened to include.
  /// Falls back to the lightweight search result if the details request
  /// fails, rather than blocking the traveler from adding the stop at
  /// all over a transient network error.
  Future<void> _select(TripStopLocation stop) async {
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _results = const [];
      _error = null;
      _hasSearched = false;
      _searching = false;
      _fetchingDetails = true;
    });

    var resolved = stop;
    final placeId = stop.placeId;
    if (placeId != null) {
      try {
        final details = await _placesService.getPlaceDetails(placeId);
        resolved = TripStopLocation.fromNearbyPlace(details);
      } catch (_) {
        // Keep the lightweight search-result stop as a fallback.
      }
    }

    if (!mounted) return;
    setState(() => _fetchingDetails = false);
    widget.onChanged(resolved);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _results = const [];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
  }

  bool get _showDropdown => _searching || _hasSearched || _error != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
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
                  Icons.search_rounded,
                  color: Color(0xFF6E7A93),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _onQueryChanged,
                    readOnly: _fetchingDetails,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      color: Color(0xFF0B1D3A),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: _fetchingDetails
                          ? 'Loading place details…'
                          : 'Search for a place to add…',
                      hintStyle: const TextStyle(
                        color: Color(0xFF6E7A93),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searching || _fetchingDetails)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: _clear,
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF6E7A93),
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_showDropdown) ...[
          const SizedBox(height: 8),
          LocationResultsDropdown(
            loading: _searching,
            error: _error,
            results: _results,
            maxHeight: 220,
            emptyText: 'No places found',
            isResultDisabled: widget.isResultDisabled,
            onPick: _select,
          ),
        ],
      ],
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
