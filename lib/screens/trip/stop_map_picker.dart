import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/trip_stop_location.dart';
import '../../services/photon_service.dart';

const _malaysiaCenter = LatLng(3.1390, 101.6869); // Kuala Lumpur
final _malaysiaBounds = LatLngBounds(
  const LatLng(0.5, 99.5),
  const LatLng(7.5, 119.5),
);
const _osmTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgent = 'com.example.travelplanner';

/// Google-Maps-style search-to-pick widget: type a place name (e.g.
/// "Komtar"), tap a Photon suggestion, confirm it on the map, and it's
/// added as a stop. Deliberately search-only — there is no tap-to-
/// drop-a-pin gesture on the map itself, so every stop comes from a real,
/// named place lookup rather than an arbitrary point.
///
/// A plain `StatefulWidget`, not a screen — size it with a `SizedBox`/
/// `Expanded` to embed it directly in a page (e.g. Create Trip), or wrap
/// it in a `Scaffold` for a dedicated picker screen (see
/// `StopSelectionScreen`).
class StopMapPicker extends StatefulWidget {
  const StopMapPicker({super.key, required this.markedStops, required this.onAdd});

  /// Stops already added — rendered as confirmed (green) markers so the
  /// map reflects the current selection.
  final List<TripStopLocation> markedStops;

  /// Called when the traveler taps "Add Stop" on the confirm card.
  final ValueChanged<TripStopLocation> onAdd;

  @override
  State<StopMapPicker> createState() => _StopMapPickerState();
}

class _StopMapPickerState extends State<StopMapPicker> {
  final _mapController = MapController();
  final _photonService = PhotonService();
  final _searchController = TextEditingController();

  List<TripStopLocation> _suggestions = const [];
  TripStopLocation? _pending;
  bool _searching = false;
  bool _locating = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      try {
        final results = await _photonService.search(
          value,
          near: _mapController.camera.center,
        );
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _searching = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _suggestions = const [];
          _searching = false;
        });
        _showMessage('Search failed: $e');
      }
    });
  }

  void _selectSuggestion(TripStopLocation stop) {
    FocusScope.of(context).unfocus();
    setState(() {
      _pending = stop;
      _suggestions = const [];
      _searchController.clear();
    });
    _mapController.move(LatLng(stop.latitude, stop.longitude), 16);
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('Location permission denied.');
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _showMessage('Turn on location services to use this.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final point = LatLng(position.latitude, position.longitude);
      _mapController.move(point, 16);
      final stop = await _photonService.reverse(point);
      if (!mounted) return;
      setState(() {
        _pending = stop ??
            TripStopLocation(
              name: 'My location',
              address:
                  '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
              latitude: point.latitude,
              longitude: point.longitude,
            );
      });
    } catch (e) {
      _showMessage('Could not get your location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirmPending() {
    final stop = _pending;
    if (stop == null) return;
    widget.onAdd(stop);
    setState(() => _pending = null);
  }

  void _dismissPending() => setState(() => _pending = null);

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.markedStops.isNotEmpty
                    ? LatLng(
                        widget.markedStops.last.latitude,
                        widget.markedStops.last.longitude,
                      )
                    : _malaysiaCenter,
                initialZoom: widget.markedStops.isEmpty ? 6 : 14,
                minZoom: 5,
                cameraConstraint: CameraConstraint.contain(
                  bounds: _malaysiaBounds,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: _osmTileUrl,
                  userAgentPackageName: _osmUserAgent,
                ),
                MarkerLayer(
                  markers: [
                    for (final stop in widget.markedStops)
                      Marker(
                        point: LatLng(stop.latitude, stop.longitude),
                        width: 32,
                        height: 32,
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF11998E),
                          size: 28,
                        ),
                      ),
                    if (_pending != null)
                      Marker(
                        point: LatLng(_pending!.latitude, _pending!.longitude),
                        width: 38,
                        height: 38,
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Color(0xFFFF7A59),
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: 10,
            child: _SearchBar(
              controller: _searchController,
              onChanged: _onQueryChanged,
              searching: _searching,
            ),
          ),
          if (_suggestions.isNotEmpty)
            Positioned(
              left: 10,
              right: 10,
              top: 58,
              child: _SuggestionsList(
                suggestions: _suggestions,
                onPick: _selectSuggestion,
              ),
            ),
          Positioned(
            right: 10,
            bottom: _pending != null ? 92 : 10,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _locating ? null : _useCurrentLocation,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _locating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.my_location_rounded,
                          color: Color(0xFF0B1D3A),
                          size: 20,
                        ),
                ),
              ),
            ),
          ),
          if (_pending != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _PendingStopCard(
                stop: _pending!,
                onConfirm: _confirmPending,
                onDismiss: _dismissPending,
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.searching,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
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
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: 'Search a place, e.g. Komtar…',
                  hintStyle: TextStyle(
                    color: Color(0xFF6E7A93),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (searching)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                child: const Icon(Icons.close_rounded, color: Color(0xFF6E7A93), size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionsList extends StatelessWidget {
  const _SuggestionsList({required this.suggestions, required this.onPick});

  final List<TripStopLocation> suggestions;
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
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: suggestions.length,
          itemBuilder: (context, i) {
            final s = suggestions[i];
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                s.categoryIcon,
                size: 18,
                color: const Color(0xFF11998E),
              ),
              title: Text(
                s.name,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(
                '${s.category} · ${s.address}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF6E7A93), fontSize: 11),
              ),
              onTap: () => onPick(s),
            );
          },
        ),
      ),
    );
  }
}

class _PendingStopCard extends StatelessWidget {
  const _PendingStopCard({
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
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(stop.categoryIcon, color: const Color(0xFF11998E), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0B1D3A),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${stop.category} · ${stop.address}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF6E7A93), fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, color: Color(0xFF6E7A93)),
            ),
            Material(
              color: const Color(0xFF0B1D3A),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onConfirm,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(
                    'Add Stop',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
