import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip_stop_location.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/malaysia_bounds.dart';
import '../../widgets/detail_header.dart';

const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';

const _stopMarkerRed = Color(0xFFE53935);
const _stopMarkerBlue = Color(0xFF1E88E5);
const _focusZoom = 16.0;

/// Read-only map of every stop already saved to one trip — NOT the
/// Transport module's routing/navigation map. No route calculation, no
/// polylines, no external place search: this only plots
/// [TripStopLocation]s already stored for [tripId] and lets the traveler
/// find one by name among them.
class TripMapScreen extends StatefulWidget {
  const TripMapScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _tripService = TripService();

  List<TripStopLocation> _stops = [];
  bool _loading = true;
  String? _error;

  /// Marker color/popup state — set either by picking a stop from the
  /// search dropdown or by tapping its marker directly on the map.
  TripStopLocation? _selectedMapStop;

  /// Non-null only right after a *search* selection — drives the map
  /// zooming to that stop. A direct marker tap updates [_selectedMapStop]
  /// without touching this, since the tapped marker is already visible.
  LatLng? _cameraFocus;

  String _searchQuery = '';
  bool _showDropdown = false;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (_searchFocusNode.hasFocus && _selectedMapStop == null) {
        setState(() => _showDropdown = true);
      }
    });
    _loadStops();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadStops() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stops = await _tripService.getTripStops(widget.tripId);
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<TripStopLocation> _filteredStops(List<TripStopLocation> all) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return all;
    return all.where((s) => s.name.toLowerCase().contains(query)).toList();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _searchQuery = value;
      _showDropdown = true;
    });
  }

  void _selectFromSearch(TripStopLocation stop) {
    _searchFocusNode.unfocus();
    _searchController.text = stop.name;
    setState(() {
      _selectedMapStop = stop;
      _cameraFocus = LatLng(stop.latitude, stop.longitude);
      _searchQuery = '';
      _showDropdown = false;
    });
  }

  void _selectFromMarker(TripStopLocation stop) {
    setState(() => _selectedMapStop = stop);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _selectedMapStop = null;
      _cameraFocus = null;
      _searchQuery = '';
      _showDropdown = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Trip Map',
              subtitle: 'Every stop on this trip',
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_loading) return const _StopsLoading();
                  if (_error != null) {
                    return _StopsError(message: _error!, onRetry: _loadStops);
                  }
                  final stops = _stops;

                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: stops.isEmpty
                        ? const _NoStopsState()
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _TripStopsMap(
                                    stops: stops,
                                    selected: _selectedMapStop,
                                    cameraFocus: _cameraFocus,
                                    onTapMarker: _selectFromMarker,
                                  ),
                                ),
                                Positioned(
                                  left: 10,
                                  right: 10,
                                  top: 10,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _TripStopSearchField(
                                        controller: _searchController,
                                        focusNode: _searchFocusNode,
                                        onChanged: _onQueryChanged,
                                        onClear: _clearSearch,
                                        hasSelection:
                                            _selectedMapStop != null,
                                      ),
                                      if (_showDropdown &&
                                          _selectedMapStop == null) ...[
                                        const SizedBox(height: 8),
                                        _TripStopDropdown(
                                          stops: _filteredStops(stops),
                                          onPick: _selectFromSearch,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripStopsMap extends StatelessWidget {
  const _TripStopsMap({
    required this.stops,
    required this.selected,
    required this.cameraFocus,
    required this.onTapMarker,
  });

  final List<TripStopLocation> stops;
  final TripStopLocation? selected;
  final LatLng? cameraFocus;
  final ValueChanged<TripStopLocation> onTapMarker;

  @override
  Widget build(BuildContext context) {
    final points = [for (final s in stops) LatLng(s.latitude, s.longitude)];
    final bounds = points.isEmpty ? null : LatLngBounds.fromPoints(points);
    final focus = cameraFocus;

    // Keyed on whether/where the camera should be focused, so selecting
    // a stop via search (or clearing back to "fit everything") remounts
    // the map with a correct initial camera — flutter_map's tile layer
    // doesn't reliably reload tiles for a new viewport when nudged via
    // MapController alone after the map is already mounted.
    final cameraKey = focus != null
        ? 'focus:${focus.latitude.toStringAsFixed(5)},${focus.longitude.toStringAsFixed(5)}'
        : 'all:${stops.length}';

    return FlutterMap(
      key: ValueKey(cameraKey),
      options: MapOptions(
        initialCenter: focus ?? bounds?.center ?? malaysiaFallbackCenter,
        // Only actually used when initialCameraFit is null (falls back to
        // the fit's own computed zoom otherwise) — kept >= minZoom below
        // regardless, so there's no zoom/minZoom mismatch either way.
        initialZoom: focus != null || bounds == null ? _focusZoom : 12,
        initialCameraFit: focus == null && bounds != null
            ? CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.fromLTRB(36, 90, 36, 36),
                maxZoom: _focusZoom,
              )
            : null,
        cameraConstraint: CameraConstraint.contain(bounds: malaysiaBounds),
        // A trip's stops sit within one city — zooming out further than
        // that only reaches OSM's coarser, generalized coastline tiles,
        // where a point genuinely near the shore (e.g. a jetty) can
        // render as if it's over water even though it isn't.
        minZoom: 10,
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
                width: 170,
                height: 76,
                alignment: Alignment.bottomCenter,
                child: _TripStopMarker(
                  name: stop.name,
                  isSelected: stop == selected,
                  onTap: () => onTapMarker(stop),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TripStopMarker extends StatelessWidget {
  const _TripStopMarker({
    required this.name,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isSelected) ...[
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
        ],
        GestureDetector(
          onTap: onTap,
          child: Icon(
            Icons.location_on_rounded,
            color: isSelected ? _stopMarkerBlue : _stopMarkerRed,
            size: 34,
          ),
        ),
      ],
    );
  }
}

class _TripStopSearchField extends StatelessWidget {
  const _TripStopSearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
    required this.hasSelection,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool hasSelection;

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
            const Icon(Icons.search_rounded, color: Color(0xFF6E7A93), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                readOnly: hasSelection,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search trip stops…',
                  hintStyle: TextStyle(
                    color: Color(0xFF6E7A93),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
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

class _TripStopDropdown extends StatelessWidget {
  const _TripStopDropdown({required this.stops, required this.onPick});

  final List<TripStopLocation> stops;
  final ValueChanged<TripStopLocation> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 220),
        child: stops.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No matching stops',
                  style: TextStyle(color: Color(0xFF6E7A93), fontSize: 12.5),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: stops.length,
                itemBuilder: (context, i) {
                  final stop = stops[i];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(
                      Icons.location_on_rounded,
                      size: 18,
                      color: _stopMarkerRed,
                    ),
                    title: Text(
                      stop.name,
                      style: const TextStyle(
                        color: Color(0xFF0B1D3A),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () => onPick(stop),
                  );
                },
              ),
      ),
    );
  }
}

class _StopsLoading extends StatelessWidget {
  const _StopsLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _StopsError extends StatelessWidget {
  const _StopsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.muted,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              'Could not load this trip\'s stops',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _NoStopsState extends StatelessWidget {
  const _NoStopsState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag_outlined, color: context.colors.muted, size: 34),
          const SizedBox(height: 10),
          Text(
            'No stops added yet',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add stops to this trip to see them on the map.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

