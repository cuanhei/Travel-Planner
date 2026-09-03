import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nearby_place.dart';
import '../../theme/app_theme.dart';
import '../../widgets/route_map_view.dart';

/// Full profile for a real place — currently only reached from Explore's
/// Nearby Places (Google Places API (New) data), but named/shaped to
/// become the shared details screen once Popular Destinations moves off
/// its dummy `Place` catalog too. Shows every field the app actually has
/// (name, address, photo, type, open/closed status, distance, location).
/// No rating, reviews, description, or budget: those aren't part of the
/// Nearby Search field mask, and reviews specifically will come from
/// this app's own review system later, not Google's — so there's no
/// reviews section here at all yet, unlike `PlaceDetailsScreen` (which
/// stays untouched, still backing the dummy Popular Destinations catalog
/// for now).
class ExplorePlaceDetailsScreen extends StatefulWidget {
  const ExplorePlaceDetailsScreen({super.key, required this.place});

  final NearbyPlace place;

  @override
  State<ExplorePlaceDetailsScreen> createState() =>
      _ExplorePlaceDetailsScreenState();
}

class _ExplorePlaceDetailsScreenState
    extends State<ExplorePlaceDetailsScreen> {
  LatLng? _currentPosition;

  @override
  void initState() {
    super.initState();
    _locateCurrentPosition();
  }

  /// One-shot GPS fetch for the location map's "you are here" marker —
  /// mirrors the same permission handling used elsewhere (Map View,
  /// Nearby Places itself); never blocks the screen, since the map is
  /// still useful showing just the place if this fails or is denied.
  Future<void> _locateCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (_) {
      // Silently degrade — the map still shows the place itself.
    }
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final status = _statusVisuals(place.businessStatus);
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: AppColors.horizon.last,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.25),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _HeroImage(place: place),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (place.address.isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.location_on_rounded,
                          color: context.colors.muted,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            place.address,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Tag(label: _formatType(place.primaryType)),
                      _Tag(label: place.distanceLabel, icon: Icons.near_me_rounded),
                      _StatusChip(label: status.label, color: status.color),
                      if (place.openNow != null)
                        _StatusChip(
                          label: place.openNow! ? 'Open Now' : 'Closed Now',
                          color: place.openNow!
                              ? const Color(0xFF11998E)
                              : Colors.redAccent,
                        ),
                      if (place.priceLevelLabel != null)
                        _Tag(
                          label: place.priceLevelLabel!,
                          icon: Icons.attach_money_rounded,
                        ),
                      if (place.priceRangeLabel != null)
                        _Tag(
                          label: place.priceRangeLabel!,
                          icon: Icons.sell_rounded,
                        ),
                    ],
                  ),
                  if (place.editorialSummary != null &&
                      place.editorialSummary!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'About',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      place.editorialSummary!,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                  if (place.openingHours != null &&
                      place.openingHours!.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Opening Hours',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in place.openingHours!)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                line,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Location',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  RouteMapView(
                    source: _currentPosition,
                    destination: LatLng(place.latitude, place.longitude),
                    sourceIsCurrentLocation: true,
                    height: 160,
                    borderRadius: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.place});

  final NearbyPlace place;

  @override
  Widget build(BuildContext context) {
    final photoUrl = place.photoUrl;
    if (photoUrl == null) {
      return _placeholder(place.icon);
    }
    return Image.network(
      photoUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _placeholder(place.icon),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder(place.icon),
    );
  }

  Widget _placeholder(IconData icon) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.horizon,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 72),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: AppColors.accent),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

({String label, Color color}) _statusVisuals(String? status) {
  switch (status) {
    case 'OPERATIONAL':
      return (label: 'Open', color: const Color(0xFF11998E));
    case 'CLOSED_TEMPORARILY':
      return (label: 'Temporarily Closed', color: const Color(0xFFFFB347));
    case 'CLOSED_PERMANENTLY':
      return (label: 'Permanently Closed', color: Colors.redAccent);
    default:
      return (label: 'Hours unknown', color: const Color(0xFF6E7A93));
  }
}

/// e.g. "tourist_attraction" -> "Tourist Attraction".
String _formatType(String? type) {
  if (type == null || type.isEmpty) return 'Place';
  return type
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
