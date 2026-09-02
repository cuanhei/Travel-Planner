import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip_stop_location.dart';
import '../../services/photon_service.dart';
import '../../utils/malaysia_bounds.dart';

const _debounceDuration = Duration(milliseconds: 400);
const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';
const _stopMarkerColor = Color(0xFFFF7A59);
const _pendingMarkerColor = Color(0xFF1E88E5);
const _closeZoom = 15.0;

/// Real map + fuzzy place search for picking a trip's stops — the same
/// OpenStreetMap/Photon-backed search pattern as the Home dashboard's map
/// (see `MapViewScreen`/`TransportLocationSearchField`), adapted for
/// picking *multiple* stops instead of a single destination. Tapping a
/// search result doesn't add it right away: it's plotted on the map as a
/// pending pin (distinct color) with an "Add to Trip" button next to its
/// name, so the traveler can see exactly where it is before committing —
/// tapping Add calls [onAdd] and the map re-fits to show every stop
/// picked so far. Removing a stop (via the chip list below this widget,
/// in the parent) is reflected the next time [stops] changes.
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
  final _photonService = PhotonService();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounce;

  List<TripStopLocation> _results = const [];
  bool _searching = false;
  String? _error;
  bool _hasSearched = false;

  /// The result the traveler just tapped, plotted on the map but not yet
  /// added to the trip — cleared either by confirming (Add to Trip) or
  /// dismissing it.
  TripStopLocation? _pendingStop;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
    _debounce = Timer(_debounceDuration, () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    try {
      final results = await _photonService.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
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
            'Could not search locations. Check your connection and try again.';
        _hasSearched = true;
      });
    }
  }

  void _selectPending(TripStopLocation stop) {
    _debounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _pendingStop = stop;
      _results = const [];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
  }

  void _confirmPending() {
    final stop = _pendingStop;
    if (stop == null) return;
    widget.onAdd(stop);
    _searchController.clear();
    setState(() => _pendingStop = null);
  }

  void _dismissPending() {
    _searchController.clear();
    setState(() => _pendingStop = null);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _results = const [];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
  }

  bool get _showDropdown =>
      _pendingStop == null && (_searching || _hasSearched || _error != null);

  @override
  Widget build(BuildContext context) {
    final pending = _pendingStop;
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
            child: pending == null
                ? _buildSearchRow()
                : _buildPendingRow(pending),
          ),
        ),
        if (_showDropdown) ...[
          const SizedBox(height: 8),
          _ResultsDropdown(
            loading: _searching,
            error: _error,
            results: _results,
            alreadyAdded: widget.stops,
            onPick: _selectPending,
          ),
        ],
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

  Widget _buildSearchRow() {
    return Row(
      children: [
        const Icon(Icons.search_rounded, color: Color(0xFF6E7A93), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onQueryChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(
              color: Color(0xFF0B1D3A),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: const InputDecoration(
              hintText: 'Search for a place to add…',
              hintStyle: TextStyle(
                color: Color(0xFF6E7A93),
                fontWeight: FontWeight.w500,
              ),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        if (_searching)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (_searchController.text.isNotEmpty)
          GestureDetector(
            onTap: _clearSearch,
            child: const Icon(
              Icons.close_rounded,
              color: Color(0xFF6E7A93),
              size: 18,
            ),
          ),
      ],
    );
  }

  Widget _buildPendingRow(TripStopLocation pending) {
    return Row(
      children: [
        const Icon(
          Icons.location_on_rounded,
          color: _pendingMarkerColor,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            pending.name,
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
            onTap: _confirmPending,
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
          onTap: _dismissPending,
          child: const Icon(
            Icons.close_rounded,
            color: Color(0xFF6E7A93),
            size: 18,
          ),
        ),
      ],
    );
  }
}

class _ResultsDropdown extends StatelessWidget {
  const _ResultsDropdown({
    required this.loading,
    required this.error,
    required this.results,
    required this.alreadyAdded,
    required this.onPick,
  });

  final bool loading;
  final String? error;
  final List<TripStopLocation> results;
  final List<TripStopLocation> alreadyAdded;
  final ValueChanged<TripStopLocation> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFE05A5A),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error!,
                style: const TextStyle(
                  color: Color(0xFF6E7A93),
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No places found',
          style: TextStyle(color: Color(0xFF6E7A93), fontSize: 12.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        final added = alreadyAdded.contains(r);
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(r.categoryIcon, size: 18, color: _stopMarkerColor),
          title: Text(
            r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0B1D3A),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          subtitle: Text(
            r.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF6E7A93), fontSize: 11),
          ),
          trailing: added
              ? const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Color(0xFF11998E),
                )
              : null,
          onTap: added ? null : () => onPick(r),
        );
      },
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
