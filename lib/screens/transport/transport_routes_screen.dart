import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/transport_location.dart';
import '../../theme/app_theme.dart';
import '../../widgets/current_location_marker.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/map_label_pill.dart';
import '../../widgets/street_map_painter.dart';
import '../../widgets/transport_location_search_field.dart';
import '../explore/explore_tab.dart' show Place, places;
import 'fare_calculator_screen.dart';
import 'route_details_screen.dart';

/// One scheduled bus option from the traveler's current location to a
/// searched destination. UI-only mock data derived from the place's
/// approximate distance — no live transit/geo API involved.
class BusDeparture {
  const BusDeparture({
    required this.busNumber,
    required this.color,
    required this.waitMinutes,
    required this.rideMinutes,
    required this.fare,
    required this.nearestStop,
    required this.walkToStopMinutes,
    required this.destinationStop,
    required this.walkFromStopMinutes,
    required this.destinationName,
  });

  final String busNumber;
  final Color color;
  final int waitMinutes;
  final int rideMinutes;
  final String fare;
  final String nearestStop;
  final int walkToStopMinutes;
  final String destinationStop;
  final int walkFromStopMinutes;
  final String destinationName;

  int get totalMinutes =>
      walkToStopMinutes + waitMinutes + rideMinutes + walkFromStopMinutes;
}

const _currentLocationName = 'Komtar, George Town';

/// The traveler's next planned itinerary stop — mirrors the "Next Stop"
/// leg shown on the home dashboard and trip schedule (Komtar → Gurney
/// Drive & Plaza → Queensbay Mall), so the transport tab can proactively
/// offer directions to it.
final _nextStop = Place(
  name: 'Gurney Drive & Plaza',
  area: 'Gurney Drive, Penang',
  category: 'Shopping',
  rating: 0,
  reviews: 0,
  gradient: AppColors.dusk,
  icon: Icons.shopping_bag_rounded,
  description: 'Your next planned stop on this trip.',
  avgBudget: 'RM 20 – 50',
  distanceKm: 3.8,
);

const _busColors = [
  Color(0xFF5C6BC0),
  Color(0xFF11998E),
  Color(0xFFFF7A59),
];
const _busPool = ['101', '204', '305', '401', '502', '607'];
const _waitOptions = [4, 13, 26];

const _nearbyStops = [
  (name: 'Komtar Sentral', alignment: Alignment(0.05, 0.6)),
  (name: 'Prangin Mall Stop', alignment: Alignment(-0.55, 0.25)),
];

List<BusDeparture> _departuresFor(Place destination) {
  final distance = destination.distanceKm ?? 5.0;
  final rideMinutes = (distance * 3.4 + 7).round();
  final fareValue = 1.0 + distance * 0.18;
  final seed = destination.name.hashCode.abs();
  return List.generate(3, (i) {
    return BusDeparture(
      busNumber: _busPool[(seed + i * 7) % _busPool.length],
      color: _busColors[(seed + i) % _busColors.length],
      waitMinutes: _waitOptions[i],
      rideMinutes: rideMinutes + i * 2,
      fare: 'RM ${(fareValue + i * 0.2).toStringAsFixed(2)}',
      nearestStop: _nearbyStops.first.name,
      walkToStopMinutes: 4,
      destinationStop: '${destination.name} Stop',
      walkFromStopMinutes: 3,
      destinationName: destination.name,
    );
  });
}

/// UI-only transit planner: a stylized map centered on the traveler's
/// current location, a destination search, and the resulting bus
/// departures with full walk → wait → ride → alight instructions.
class TransportRoutesScreen extends StatefulWidget {
  const TransportRoutesScreen({super.key, this.showTripExtras = true});

  /// Whether to show the trip-specific extras — the "Next Up" stop
  /// suggestion and the "My Routes" saved-routes list. The home
  /// dashboard's entry point keeps it simpler: just the map, search,
  /// and results.
  final bool showTripExtras;

  @override
  State<TransportRoutesScreen> createState() => _TransportRoutesScreenState();
}

class _TransportRoutesScreenState extends State<TransportRoutesScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Place? _destination;

  final _favoriteStops = [places[3], places[4]];

  TransportLocation? _departure;
  TransportLocation? _selectedDestination;
  bool _locatingDeparture = false;
  String? _departureError;

  @override
  void initState() {
    super.initState();
    if (!widget.showTripExtras) _initDeparture();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Resolves the traveler's current GPS position as the default
  /// "Depart From" location, handling every permission/service outcome
  /// without ever blocking the screen — on any failure, "Depart From"
  /// just stays empty and searchable.
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
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _departure = TransportLocation(
          name: 'Current Location',
          address: '',
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _locatingDeparture = false;
      });
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

  Future<void> _addFavoriteStop() async {
    final picked = await showModalBottomSheet<Place>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FavoriteStopPicker(alreadyAdded: _favoriteStops),
    );
    if (picked == null) return;
    setState(() => _favoriteStops.add(picked));
  }

  void _removeFavoriteStop(Place place) {
    final index = _favoriteStops.indexOf(place);
    setState(() => _favoriteStops.remove(place));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text('${place.name} removed from favourite stops'),
        action: SnackBarAction(
          label: 'Undo',
          textColor: AppColors.accent,
          onPressed: () => setState(
            () => _favoriteStops.insert(
              index.clamp(0, _favoriteStops.length),
              place,
            ),
          ),
        ),
      ),
    );
  }

  List<Place> get _matches {
    if (_query.isEmpty) return const [];
    final q = _query.toLowerCase();
    return places.where((p) => p.name.toLowerCase().contains(q)).take(4).toList();
  }

  void _selectDestination(Place place) {
    FocusScope.of(context).unfocus();
    _searchController.text = place.name;
    setState(() {
      _destination = place;
      _query = '';
    });
  }

  void _clearDestination() {
    _searchController.clear();
    setState(() {
      _destination = null;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final destination = _destination;
    final departures = destination == null
        ? const <BusDeparture>[]
        : _departuresFor(destination);

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Transport',
              subtitle: 'Find your way around Penang',
              // trailing: IconButton(
              //   onPressed: () => Navigator.of(context).push(
              //     MaterialPageRoute(
              //       builder: (_) => const FareCalculatorScreen(),
              //     ),
              //   ),
              //   icon: Icon(
              //     Icons.calculate_outlined,
              //     color: context.colors.ink,
              //   ),
              // ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                children: [
                  if (widget.showTripExtras) ...[
                    if (destination?.name != _nextStop.name) ...[
                      _NextStopCard(
                        stopName: _nextStop.name,
                        onTap: () => _selectDestination(_nextStop),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'My Stops',
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
                      'Favourite places on this trip — tap one to see how to get there',
                      style: TextStyle(color: context.colors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    if (_favoriteStops.isEmpty)
                      Text(
                        'No favourite stops yet.',
                        style: TextStyle(color: context.colors.muted, fontSize: 12),
                      )
                    else
                      ..._favoriteStops.map(
                        (place) => _FavoriteStopCard(
                          place: place,
                          onTap: () => _selectDestination(place),
                          onRemove: () => _removeFavoriteStop(place),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                  if (widget.showTripExtras) ...[
                    _TransitMap(
                      destination: destination,
                      searchController: _searchController,
                      query: _query,
                      matches: _matches,
                      onQueryChanged: (v) => setState(() => _query = v),
                      onPick: _selectDestination,
                      onClear: _clearDestination,
                    ),
                    const SizedBox(height: 20),
                    if (destination == null)
                      const _EmptySearchState()
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Buses to ${destination.name}',
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            '${departures.length} options',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...departures.map(
                        (d) => _DepartureCard(
                          departure: d,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => RouteDetailsScreen(departure: d),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ] else ...[
                    const _FieldLabel('Depart From'),
                    const SizedBox(height: 8),
                    TransportLocationSearchField(
                      value: _departure,
                      onChanged: (loc) => setState(() {
                        _departure = loc;
                        if (loc != null) _departureError = null;
                      }),
                      hintText: _locatingDeparture
                          ? 'Getting your location…'
                          : 'Search departure location…',
                      selectedIcon: Icons.my_location_rounded,
                      helperText: _departureError,
                      externalLoading: _locatingDeparture,
                      quickActionLabel: 'Use current location',
                      onQuickAction: _initDeparture,
                    ),
                    const SizedBox(height: 18),
                    const _FieldLabel('Destination'),
                    const SizedBox(height: 8),
                    _TransportSearchMap(
                      value: _selectedDestination,
                      onChanged: (d) =>
                          setState(() => _selectedDestination = d),
                    ),
                    const SizedBox(height: 20),
                    if (_selectedDestination == null)
                      const _EmptyDestinationState()
                    else
                      _RouteEndpointsCard(
                        departure: _departure,
                        locatingDeparture: _locatingDeparture,
                        destination: _selectedDestination!,
                      ),
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
    required this.place,
    required this.onTap,
    required this.onRemove,
  });

  final Place place;
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
                    gradient: LinearGradient(colors: place.gradient),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(place.icon, color: Colors.white, size: 19),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tap for bus directions · ${place.area}',
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

/// Bottom sheet for picking a place to save as a favourite stop —
/// excludes places already saved.
class _FavoriteStopPicker extends StatefulWidget {
  const _FavoriteStopPicker({required this.alreadyAdded});

  final List<Place> alreadyAdded;

  @override
  State<_FavoriteStopPicker> createState() => _FavoriteStopPickerState();
}

class _FavoriteStopPickerState extends State<_FavoriteStopPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final available = places
        .where((p) => !widget.alreadyAdded.contains(p))
        .toList();
    final filtered = _query.isEmpty
        ? available
        : available
              .where(
                (p) => p.name.toLowerCase().contains(_query.toLowerCase()),
              )
              .toList();

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
                'Add a Favourite Stop',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Save a place on this trip for quick directions',
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: 'Search places…',
                  hintStyle: TextStyle(color: context.colors.muted),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: context.colors.muted,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: context.colors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 14,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          available.isEmpty
                              ? 'All places have already been added.'
                              : 'No matching places',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final place = filtered[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: place.gradient,
                                ),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                place.icon,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              place.name,
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                            subtitle: Text(
                              place.area,
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 11.5,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(place),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransitMap extends StatelessWidget {
  const _TransitMap({
    required this.destination,
    required this.searchController,
    required this.query,
    required this.matches,
    required this.onQueryChanged,
    required this.onPick,
    required this.onClear,
  });

  final Place? destination;
  final TextEditingController searchController;
  final String query;
  final List<Place> matches;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Place> onPick;
  final VoidCallback onClear;

  static const _currentLocation = Alignment(-0.2, 0.55);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 270,
        color: const Color(0xFFEFEDE6),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: StreetMapPainter()),
            ),
            for (final stop in _nearbyStops)
              Align(
                alignment: stop.alignment,
                child: _StopMarker(label: stop.name),
              ),
            const Align(
              alignment: _currentLocation,
              child: CurrentLocationMarker(),
            ),
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              child: _TransitSearchField(
                controller: searchController,
                hasDestination: destination != null,
                onChanged: onQueryChanged,
                onClear: onClear,
              ),
            ),
            if (query.isNotEmpty)
              Positioned(
                left: 10,
                right: 10,
                top: 58,
                child: _TransitSearchResults(matches: matches, onPick: onPick),
              ),
            Positioned(
              left: 10,
              bottom: 10,
              child: MapLabelPill(text: 'You are here · $_currentLocationName'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StopMarker extends StatelessWidget {
  const _StopMarker({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.directions_bus_filled_rounded,
              size: 13,
              color: Color(0xFF5C6BC0),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransitSearchField extends StatelessWidget {
  const _TransitSearchField({
    required this.controller,
    required this.hasDestination,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final bool hasDestination;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              hasDestination
                  ? Icons.directions_bus_filled_rounded
                  : Icons.search_rounded,
              color: const Color(0xFF6E7A93),
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                readOnly: hasDestination,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                decoration: const InputDecoration(
                  hintText: 'Where do you want to go?',
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

class _TransitSearchResults extends StatelessWidget {
  const _TransitSearchResults({required this.matches, required this.onPick});

  final List<Place> matches;
  final ValueChanged<Place> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: matches.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No matching destinations',
                  style: TextStyle(color: Color(0xFF6E7A93), fontSize: 12.5),
                ),
              )
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: [
                  for (final place in matches)
                    ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: Icon(
                        place.icon,
                        size: 18,
                        color: const Color(0xFF11998E),
                      ),
                      title: Text(
                        place.name,
                        style: const TextStyle(
                          color: Color(0xFF0B1D3A),
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        place.area,
                        style: const TextStyle(
                          color: Color(0xFF6E7A93),
                          fontSize: 11,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.directions_bus_filled_rounded,
                        size: 16,
                        color: Color(0xFF6E7A93),
                      ),
                      onTap: () => onPick(place),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: context.colors.muted.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.directions_bus_filled_rounded,
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
            'We\'ll show every bus option, when it arrives, and how to catch it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Map background (unchanged from [_TransitMap]'s painter/markers) with
/// the real, Photon-backed [TransportLocationSearchField] on top — used
/// only for the Transport screen's Home-page entry point, which has no
/// bus-departure mock or favourite stops to drive.
class _TransportSearchMap extends StatelessWidget {
  const _TransportSearchMap({required this.value, required this.onChanged});

  final TransportLocation? value;
  final ValueChanged<TransportLocation?> onChanged;

  static const _currentLocation = Alignment(-0.2, 0.55);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: 270,
        color: const Color(0xFFEFEDE6),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: StreetMapPainter()),
            ),
            for (final stop in _nearbyStops)
              Align(
                alignment: stop.alignment,
                child: _StopMarker(label: stop.name),
              ),
            const Align(
              alignment: _currentLocation,
              child: CurrentLocationMarker(),
            ),
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              child: TransportLocationSearchField(
                value: value,
                onChanged: onChanged,
                hintText: 'Where do you want to go?',
                selectedIcon: Icons.directions_transit_filled_rounded,
                maxDropdownHeight: 190,
              ),
            ),
            Positioned(
              left: 10,
              bottom: 10,
              child: MapLabelPill(text: 'You are here · $_currentLocationName'),
            ),
          ],
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
        border: Border.all(
          color: context.colors.muted.withValues(alpha: 0.15),
        ),
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

/// Confirms both endpoints once a destination has been picked — the
/// "Depart From → Destination" pair whose coordinates will be handed to
/// the Route API next. [departure] may still be null (GPS pending or
/// failed and the traveler hasn't searched one yet).
class _RouteEndpointsCard extends StatelessWidget {
  const _RouteEndpointsCard({
    required this.departure,
    required this.locatingDeparture,
    required this.destination,
  });

  final TransportLocation? departure;
  final bool locatingDeparture;
  final TransportLocation destination;

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
            name: departure?.name ?? (locatingDeparture ? 'Locating…' : 'Not set'),
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

class _DepartureCard extends StatelessWidget {
  const _DepartureCard({required this.departure, required this.onTap});

  final BusDeparture departure;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = departure;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
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
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: d.color.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        d.busNumber,
                        style: TextStyle(
                          color: d.color,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Bus ${d.busNumber}',
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Departs in ${d.waitMinutes} min · from ${d.nearestStop}',
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${d.totalMinutes} min',
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          d.fare,
                          style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  height: 1,
                  color: context.colors.muted.withValues(alpha: 0.12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      Icons.directions_walk_rounded,
                      size: 14,
                      color: context.colors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${d.walkToStopMinutes}m',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: context.colors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${d.waitMinutes}m wait',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.directions_bus_filled_rounded,
                      size: 14,
                      color: context.colors.muted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${d.rideMinutes}m ride',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.colors.muted,
                      size: 18,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
