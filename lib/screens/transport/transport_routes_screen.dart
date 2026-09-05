import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/drive_route.dart';
import '../../models/transit_route.dart';
import '../../models/trip_stop_location.dart';
import '../../services/route_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/transit_vehicle_display.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/location_search_field.dart';
import '../../widgets/route_map_view.dart';
import 'transit_route_details_screen.dart';

class TransportRoutesScreen extends StatefulWidget {
  const TransportRoutesScreen({
    super.key,
    this.showTripExtras = true,
    this.tripId,
  });

  final bool showTripExtras;

  final String? tripId;

  @override
  State<TransportRoutesScreen> createState() => _TransportRoutesScreenState();
}

class _TransportRoutesScreenState extends State<TransportRoutesScreen> {
  final _tripService = TripService();
  List<TripStopLocation> _favoriteStops = const [];
  bool _loadingFavorites = false;

  TripStopLocation? _nextStop;

  TripStopLocation? _departure;
  TripStopLocation? _selectedDestination;
  bool _locatingDeparture = false;
  String? _departureError;

  final _routeService = RouteService();
  List<TransitRoute> _transitRoutes = const [];
  DriveRoute? _driveRoute;
  bool _loadingRoutes = false;
  String? _routesError;
  int _selectedTransitIndex = 0;
  int _routeRequestId = 0;

  @override
  void initState() {
    super.initState();
    _initDeparture();
    if (widget.showTripExtras && widget.tripId != null) {
      _loadFavoriteStops();
      _loadNextStop();
    }
  }

  Future<void> _loadNextStop() async {
    final tripId = widget.tripId;
    if (tripId == null) return;
    try {
      final schedule = await _tripService.getTripSchedule(tripId);
      final now = DateTime.now();
      TripStopLocation? best;
      DateTime? bestArrival;
      for (final day in schedule.days) {
        final dayMidnight = DateTime(
          day.date.year,
          day.date.month,
          day.date.day,
        );
        for (final stop in day.stops) {
          final arrival = dayMidnight.add(
            Duration(minutes: stop.arrivalMinutes),
          );
          if (arrival.isBefore(now)) continue;
          if (bestArrival == null || arrival.isBefore(bestArrival)) {
            bestArrival = arrival;
            best = stop.location;
          }
        }
      }
      if (!mounted) return;
      setState(() => _nextStop = best);
    } catch (_) {}
  }

  Future<void> _loadFavoriteStops() async {
    final tripId = widget.tripId;
    if (tripId == null) return;
    setState(() => _loadingFavorites = true);
    try {
      final stops = await _tripService.getFavoriteStops(tripId);
      if (!mounted) return;
      setState(() {
        _favoriteStops = stops;
        _loadingFavorites = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingFavorites = false);
    }
  }

  Future<void> _initDeparture() async {
    setState(() {
      _locatingDeparture = true;
      _departureError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _failDeparture(
          'Location services are turned off. Search for a departure point instead.',
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _failDeparture(
          'Location permission is permanently denied. Enable it in Settings, or search for a departure point.',
        );
        return;
      }
      if (permission == LocationPermission.denied) {
        _failDeparture(
          'Location permission denied. Search for a departure point instead.',
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _departure = TripStopLocation(
          name: 'Current Location',
          address: '',
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _locatingDeparture = false;
      });
      _maybeFetchRoutes();
    } catch (_) {
      _failDeparture(
        'Unable to retrieve your current location. Search for a departure point instead.',
      );
    }
  }

  void _failDeparture(String message) {
    if (!mounted) return;
    setState(() {
      _locatingDeparture = false;
      _departureError = message;
    });
  }

  Future<void> _maybeFetchRoutes() async {
    final departure = _departure;
    final destination = _selectedDestination;
    if (departure == null || destination == null) {
      setState(() {
        _transitRoutes = const [];
        _driveRoute = null;
        _routesError = null;
        _loadingRoutes = false;
        _selectedTransitIndex = 0;
      });
      return;
    }

    final requestId = ++_routeRequestId;
    setState(() {
      _loadingRoutes = true;
      _routesError = null;
      _transitRoutes = const [];
      _driveRoute = null;
      _selectedTransitIndex = 0;
    });

    final origin = LatLng(departure.latitude, departure.longitude);
    final dest = LatLng(destination.latitude, destination.longitude);

    try {
      final transitRoutes = await _routeService.getTransitRoutes(
        origin: origin,
        destination: dest,
      );
      if (!mounted || requestId != _routeRequestId) return;
      setState(() {
        _transitRoutes = transitRoutes;
        _loadingRoutes = false;
        _routesError = transitRoutes.isEmpty
            ? 'No public transport routes found between these points.'
            : null;
      });
    } catch (_) {
      if (!mounted || requestId != _routeRequestId) return;
      setState(() {
        _loadingRoutes = false;
        _routesError =
            'Could not load public transport routes. Check your connection and try again.';
      });
    }

    try {
      final drive = await _routeService.getDriveRoute(
        origin: origin,
        destination: dest,
      );
      if (!mounted || requestId != _routeRequestId) return;
      setState(() => _driveRoute = drive);
    } catch (_) {}
  }

  List<LatLng> get _mapPolylinePoints {
    if (_transitRoutes.isEmpty) return const [];
    final index = _selectedTransitIndex.clamp(0, _transitRoutes.length - 1);
    return _transitRoutes[index].polylinePoints;
  }

  Color get _mapPolylineColor => const Color(0xFF11998E);

  Future<void> _addFavoriteStop() async {
    final tripId = widget.tripId;
    if (tripId == null) return;
    final picked = await showModalBottomSheet<TripStopLocation>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FavoriteStopPicker(alreadyAdded: _favoriteStops),
    );
    if (picked == null) return;
    try {
      final saved = await _tripService.addFavoriteStop(tripId, picked);
      if (!mounted) return;
      setState(() => _favoriteStops = [..._favoriteStops, saved]);
    } catch (e) {
      debugPrint('addFavoriteStop failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not save that stop: $e'),
        ),
      );
    }
  }

  Future<void> _removeFavoriteStop(TripStopLocation stop) async {
    final tripId = widget.tripId;
    final index = _favoriteStops.indexOf(stop);
    setState(() => _favoriteStops = [..._favoriteStops]..remove(stop));
    try {
      await _tripService.removeFavoriteStop(stop.id!);
    } catch (_) {
      if (!mounted) return;
      setState(
        () =>
            _favoriteStops = [..._favoriteStops]
              ..insert(index.clamp(0, _favoriteStops.length), stop),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not remove that stop. Try again.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text('${stop.name} removed from quick stops'),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppColors.accent,
          onPressed: () async {
            if (tripId == null) return;
            try {
              final restored = await _tripService.addFavoriteStop(tripId, stop);
              if (!mounted) return;
              setState(
                () =>
                    _favoriteStops = [..._favoriteStops]
                      ..insert(index.clamp(0, _favoriteStops.length), restored),
              );
            } catch (_) {}
          },
        ),
      ),
    );
  }

  void _selectFavoriteStop(TripStopLocation stop) {
    setState(() => _selectedDestination = stop);
    _maybeFetchRoutes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Transport',
              subtitle: 'Find your way around Malaysia',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  if (widget.showTripExtras) ...[
                    if (_nextStop case final nextStop?
                        when _selectedDestination != nextStop) ...[
                      _NextStopCard(
                        stopName: nextStop.name,
                        onTap: () => _selectFavoriteStop(nextStop),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (widget.tripId != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Quick Stops',
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _addFavoriteStop,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.add_circle_rounded,
                                  color: AppColors.accent,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Add',
                                  style: TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Places you commonly visit on this trip — added just for fast transport access, not part of your travel plan. Tap one to see how to get there.',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingFavorites)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_favoriteStops.isEmpty)
                        Text(
                          'No quick stops yet.',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                          ),
                        )
                      else
                        ..._favoriteStops.map(
                          (stop) => _FavoriteStopCard(
                            stop: stop,
                            onTap: () => _selectFavoriteStop(stop),
                            onRemove: () => _removeFavoriteStop(stop),
                          ),
                        ),
                      const SizedBox(height: 20),
                    ],
                  ],
                  const _FieldLabel('Depart From'),
                  const SizedBox(height: 8),
                  LocationSearchField(
                    value: _departure,
                    onChanged: (loc) {
                      setState(() {
                        _departure = loc;
                        if (loc != null) _departureError = null;
                      });
                      _maybeFetchRoutes();
                    },
                    hintText: _locatingDeparture
                        ? 'Getting your location…'
                        : 'Search departure location…',
                    selectedIcon: Icons.my_location_rounded,
                    helperText: _departureError,
                    externalLoading: _locatingDeparture,
                    quickActionLabel: 'Use current location',
                    onQuickAction: _initDeparture,
                  ),
                  // Departure locked to live GPS only — selection disabled.
                  // _LockedDepartureField(
                  //   departure: _departure,
                  //   locating: _locatingDeparture,
                  //   error: _departureError,
                  //   onRetry: _initDeparture,
                  // ),
                  const SizedBox(height: 18),
                  const _FieldLabel('Destination'),
                  const SizedBox(height: 8),
                  LocationSearchField(
                    value: _selectedDestination,
                    onChanged: (d) {
                      setState(() => _selectedDestination = d);
                      _maybeFetchRoutes();
                    },
                    hintText: 'Where do you want to go?',
                    selectedIcon: Icons.directions_transit_filled_rounded,
                  ),
                  const SizedBox(height: 18),
                  RouteMapView(
                    source: _departure == null
                        ? null
                        : LatLng(_departure!.latitude, _departure!.longitude),
                    destination: _selectedDestination == null
                        ? null
                        : LatLng(
                            _selectedDestination!.latitude,
                            _selectedDestination!.longitude,
                          ),
                    polylinePoints: _mapPolylinePoints,
                    polylineColor: _mapPolylineColor,
                    height: 270,
                  ),
                  const SizedBox(height: 20),
                  if (_selectedDestination == null)
                    const _EmptyDestinationState()
                  else ...[
                    _RouteEndpointsCard(
                      departure: _departure,
                      locatingDeparture: _locatingDeparture,
                      destination: _selectedDestination!,
                    ),
                    if (_departure != null) ...[
                      const SizedBox(height: 20),
                      _RouteResultsSection(
                        loading: _loadingRoutes,
                        error: _routesError,
                        transitRoutes: _transitRoutes,
                        driveRoute: _driveRoute,
                        selectedTransitIndex: _selectedTransitIndex,
                        onSelectTransit: (index) =>
                            setState(() => _selectedTransitIndex = index),
                        onViewDetails: (route) => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TransitRouteDetailsScreen(
                              route: route,
                              departure: _departure!,
                              destination: _selectedDestination!,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextStopCard extends StatelessWidget {
  const _NextStopCard({required this.stopName, required this.onTap});

  final String stopName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.dusk,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.dusk.last.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.next_plan_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'NEXT UP',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your next stop is $stopName. Do you want to go there?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'Yes, find me transport to $stopName',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 15,
                              color: context.colors.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteStopCard extends StatelessWidget {
  const _FavoriteStopCard({
    required this.stop,
    required this.onTap,
    required this.onRemove,
  });

  final TripStopLocation stop;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: context.colors.ink.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: AppColors.horizon),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(stop.categoryIcon, color: Colors.white, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stop.address.isEmpty
                            ? 'Tap for directions'
                            : 'Tap for directions · ${stop.address}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onRemove,
                  child: Icon(
                    Icons.close_rounded,
                    color: context.colors.muted,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FavoriteStopPicker extends StatelessWidget {
  const _FavoriteStopPicker({required this.alreadyAdded});

  final List<TripStopLocation> alreadyAdded;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          constraints: const BoxConstraints(maxHeight: 460),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add a Quick Stop',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add a place you\'d commonly visit on this trip — just for fast transport access, not part of your travel plan',
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              LocationSearchField(
                value: null,
                onChanged: (loc) {
                  if (loc != null) Navigator.of(context).pop(loc);
                },
                hintText: 'Search a place…',
                isResultDisabled: (r) => alreadyAdded.contains(r),
                emptyResultsText: 'No places found',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDestinationState extends StatelessWidget {
  const _EmptyDestinationState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.travel_explore_rounded,
            color: context.colors.muted,
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            'Search where you want to go',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Find any destination in Malaysia to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _LockedDepartureField extends StatelessWidget {
  const _LockedDepartureField({
    required this.departure,
    required this.locating,
    required this.error,
    required this.onRetry,
  });

  final TripStopLocation? departure;
  final bool locating;
  final String? error;
  final VoidCallback onRetry;

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
                  Icons.my_location_rounded,
                  color: Color(0xFF6E7A93),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: locating
                      ? const Text(
                          'Getting your location…',
                          style: TextStyle(
                            color: Color(0xFF6E7A93),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : Text(
                          departure?.name ?? 'Current location unavailable',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0B1D3A),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                if (locating)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (departure == null)
                  GestureDetector(
                    onTap: onRetry,
                    child: const Icon(
                      Icons.refresh_rounded,
                      color: Color(0xFF6E7A93),
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (!locating && error != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFB3541E), fontSize: 11.5),
            ),
          ),
        ],
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.ink,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
    );
  }
}

class _RouteEndpointsCard extends StatelessWidget {
  const _RouteEndpointsCard({
    required this.departure,
    required this.locatingDeparture,
    required this.destination,
  });

  final TripStopLocation? departure;
  final bool locatingDeparture;
  final TripStopLocation destination;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _EndpointRow(
            icon: Icons.trip_origin_rounded,
            iconColor: const Color(0xFF5C6BC0),
            label: 'DEPART FROM',
            name:
                departure?.name ??
                (locatingDeparture ? 'Locating…' : 'Not set'),
            address: departure?.address ?? '',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 16,
              color: context.colors.muted,
            ),
          ),
          _EndpointRow(
            icon: Icons.location_on_rounded,
            iconColor: AppColors.accent,
            label: 'DESTINATION',
            name: destination.name,
            address: destination.address,
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.name,
    required this.address,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String name;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                name,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  address,
                  style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteResultsSection extends StatelessWidget {
  const _RouteResultsSection({
    required this.loading,
    required this.error,
    required this.transitRoutes,
    required this.driveRoute,
    required this.selectedTransitIndex,
    required this.onSelectTransit,
    required this.onViewDetails,
  });

  final bool loading;
  final String? error;
  final List<TransitRoute> transitRoutes;
  final DriveRoute? driveRoute;
  final int selectedTransitIndex;
  final ValueChanged<int> onSelectTransit;
  final ValueChanged<TransitRoute> onViewDetails;

  @override
  Widget build(BuildContext context) {
    if (loading) return const _RoutesLoadingCard();
    if (transitRoutes.isEmpty) {
      return _RoutesErrorCard(
        message:
            error ?? 'No public transport routes found between these points.',
      );
    }

    final drive = driveRoute;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('Public Transport'),
        const SizedBox(height: 10),
        for (var i = 0; i < transitRoutes.length; i++) ...[
          _TransitRouteSummaryCard(
            route: transitRoutes[i],
            recommended: i == 0,
            selected: selectedTransitIndex == i,
            onTap: () {
              onSelectTransit(i);
              onViewDetails(transitRoutes[i]);
            },
          ),
          const SizedBox(height: 10),
        ],
        if (drive != null) ...[
          const SizedBox(height: 6),
          const _SectionLabel('Alternative'),
          const SizedBox(height: 10),
          _DriveRouteSummaryCard(route: drive),
        ],
      ],
    );
  }
}

class _RoutesLoadingCard extends StatelessWidget {
  const _RoutesLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Finding public transport routes…',
            style: TextStyle(
              color: context.colors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutesErrorCard extends StatelessWidget {
  const _RoutesErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: context.colors.muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.colors.ink,
        fontWeight: FontWeight.w800,
        fontSize: 15,
      ),
    );
  }
}

class _TransitRouteSummaryCard extends StatelessWidget {
  const _TransitRouteSummaryCard({
    required this.route,
    required this.recommended,
    required this.selected,
    required this.onTap,
  });

  final TransitRoute route;
  final bool recommended;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vehicles = route.vehicleSequence;
    final transferLabel = route.transferCount == 0
        ? 'Direct'
        : '${route.transferCount} transfer${route.transferCount == 1 ? '' : 's'}';

    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF11998E)
                  : context.colors.muted.withValues(alpha: 0.12),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (recommended)
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'RECOMMENDED',
                              style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        for (var i = 0; i < vehicles.length; i++) ...[
                          if (i > 0)
                            Text(
                              '+',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          Icon(
                            TransitVehicleDisplay.of(vehicles[i]).icon,
                            size: 17,
                            color: const Color(0xFF11998E),
                          ),
                          Text(
                            TransitVehicleDisplay.of(vehicles[i]).label,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${formatDuration(route.duration)} • $transferLabel',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriveRouteSummaryCard extends StatelessWidget {
  const _DriveRouteSummaryCard({required this.route});

  final DriveRoute route;

  @override
  Widget build(BuildContext context) {
    const driveColor = Color(0xFF5C6BC0);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: driveColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.directions_car_filled_rounded,
              color: driveColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Drive',
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDuration(route.duration)} • ${formatDistanceMeters(route.distanceMeters)}',
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
