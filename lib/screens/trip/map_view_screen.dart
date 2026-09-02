import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/transport_location.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/route_map_view.dart';
import '../../widgets/transport_location_search_field.dart';

/// Home dashboard's general map: a real OpenStreetMap centered on the
/// traveler's current GPS location with a Photon-backed search bar —
/// searching a place plots it as a single marker, replacing whichever
/// place was searched before. Unrelated to a specific trip's stops —
/// see `TripMapScreen` for that.
class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

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
    _locateCurrentPosition();
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
            const DetailHeader(
              title: 'Map View',
              subtitle: 'Search anywhere in Malaysia',
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TransportLocationSearchField(
                      value: _searchedLocation,
                      onChanged: (loc) =>
                          setState(() => _searchedLocation = loc),
                      hintText: 'Search a place in Malaysia…',
                      selectedIcon: Icons.location_on_rounded,
                    ),
                    if (_locatingCurrentPosition) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Getting your location…',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_locationError != null &&
                        _currentPosition == null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _locationError!,
                              style: const TextStyle(
                                color: Color(0xFFB3541E),
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _locateCurrentPosition,
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
                        source: _currentPosition,
                        destination: _searchedLocation == null
                            ? null
                            : LatLng(
                                _searchedLocation!.latitude,
                                _searchedLocation!.longitude,
                              ),
                        sourceIsCurrentLocation: true,
                        height: null,
                        borderRadius: 24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
