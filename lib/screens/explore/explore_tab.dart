import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nearby_place.dart';
import '../../services/google_places_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/destination_search_bar.dart';
import '../../widgets/section_header.dart';
import 'categories_screen.dart';
import 'nearby_places_screen.dart';
import 'place_details_screen.dart';

class Place {
  Place({
    required this.name,
    required this.area,
    required this.category,
    required this.rating,
    required this.reviews,
    required this.gradient,
    required this.icon,
    required this.description,
    required this.avgBudget,
    this.distanceKm,
  });

  final String name;
  final String area;
  final String category;
  final double rating;
  final int reviews;
  final List<Color> gradient;
  final IconData icon;
  final String description;

  /// Roughly what a visit costs per person (entry fee, food, etc.) —
  /// a formatted range like "RM 30 – 50" or "Free".
  final String avgBudget;
  final double? distanceKm;
}

final places = [
  Place(
    name: 'Penang Hill',
    area: 'Air Itam, Penang',
    category: 'Nature',
    rating: 4.8,
    reviews: 2140,
    gradient: AppColors.lagoon,
    icon: Icons.terrain_rounded,
    description:
        'A hill station offering panoramic views of George Town, reached '
        'by a historic funicular railway. Cooler air, gardens, and a '
        'canopy walkway make it a favorite half-day trip.',
    avgBudget: 'RM 30 – 50',
    distanceKm: 8.2,
  ),
  Place(
    name: 'Batu Ferringhi',
    area: 'Tanjung Bungah, Penang',
    category: 'Beach',
    rating: 4.6,
    reviews: 1560,
    gradient: AppColors.sunset,
    icon: Icons.beach_access_rounded,
    description:
        'A lively beach strip lined with resorts, a night market, and '
        'water sports. Great for sunset walks and street food.',
    avgBudget: 'RM 20 – 60',
    distanceKm: 12.5,
  ),
  Place(
    name: 'Chew Jetty',
    area: 'George Town, Penang',
    category: 'Culture',
    rating: 4.7,
    reviews: 3980,
    gradient: AppColors.horizon,
    icon: Icons.holiday_village_rounded,
    description:
        'A centuries-old stilt village built over water by the Chew clan. '
        'Wander wooden boardwalks lined with shops, cafes, and sea views.',
    avgBudget: 'Free – RM 20',
    distanceKm: 2.1,
  ),
  Place(
    name: 'The Top Komtar',
    area: 'George Town, Penang',
    category: 'Shopping',
    rating: 4.5,
    reviews: 1120,
    gradient: AppColors.dusk,
    icon: Icons.visibility_rounded,
    description:
        'An observation deck and rooftop attraction atop Komtar Tower, '
        'with a glass walk and 360° views over George Town.',
    avgBudget: 'RM 30 – 80',
    distanceKm: 0.5,
  ),
  Place(
    name: 'Gurney Drive Hawker Centre',
    area: 'Gurney Drive, Penang',
    category: 'Food',
    rating: 4.7,
    reviews: 2670,
    gradient: AppColors.sunset,
    icon: Icons.restaurant_rounded,
    description:
        'A legendary open-air food court along the seafront, famous for '
        'char kway teow, laksa, and fresh seafood stalls.',
    avgBudget: 'RM 15 – 40',
    distanceKm: 3.4,
  ),
  Place(
    name: 'Upside Down Museum',
    area: 'George Town, Penang',
    category: 'Nightlife',
    rating: 4.4,
    reviews: 890,
    gradient: AppColors.lagoon,
    icon: Icons.nightlife_rounded,
    description:
        'A quirky photo-op museum with upside-down rooms — a fun evening '
        'stop for playful souvenir photos.',
    avgBudget: 'RM 40 – 60',
    distanceKm: 1.8,
  ),
];

final categories = [
  (label: 'Shopping', icon: Icons.shopping_bag_rounded),
  (label: 'Food', icon: Icons.restaurant_rounded),
  (label: 'Nature', icon: Icons.terrain_rounded),
  (label: 'Culture', icon: Icons.holiday_village_rounded),
  (label: 'Beach', icon: Icons.beach_access_rounded),
  (label: 'Nightlife', icon: Icons.nightlife_rounded),
];

/// "Explore" bottom-nav tab: category chips + popular destinations feed.
class ExploreTab extends StatefulWidget {
  const ExploreTab({super.key});

  @override
  State<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<ExploreTab> {
  String? _selectedCategory;

  final _placesService = GooglePlacesService();
  List<NearbyPlace> _nearbyPlaces = [];
  bool _nearbyLoading = true;
  String? _nearbyError;

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  /// Fetches real places around the traveler's current GPS position via
  /// Google Places API (New) Nearby Search — mirrors the permission
  /// handling other GPS-driven sections (Weather, Map View) already use.
  Future<void> _loadNearby() async {
    setState(() {
      _nearbyLoading = true;
      _nearbyError = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Location services are turned off.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission is permanently denied.');
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission is needed to find nearby places.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final results = await _placesService.nearbySearch(
        center: LatLng(position.latitude, position.longitude),
      );
      if (!mounted) return;
      setState(() {
        _nearbyPlaces = results;
        _nearbyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _nearbyLoading = false;
        _nearbyError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedCategory == null
        ? places
        : places.where((p) => p.category == _selectedCategory).toList();

    return SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
        children: [
          Text(
            'Explore',
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Discover more of Penang',
            style: TextStyle(color: context.colors.muted, fontSize: 13.5),
          ),
          SizedBox(height: 20),
          const DestinationSearchBar(),
          SizedBox(height: 20),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _CategoryChip(
                  label: 'All',
                  icon: Icons.apps_rounded,
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                SizedBox(width: 8),
                ...categories.map(
                  (c) => Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: c.label,
                      icon: c.icon,
                      selected: _selectedCategory == c.label,
                      onTap: () => setState(() => _selectedCategory = c.label),
                    ),
                  ),
                ),
                _CategoryChip(
                  label: 'Browse all',
                  icon: Icons.grid_view_rounded,
                  selected: false,
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => CategoriesScreen())),
                ),
              ],
            ),
          ),
          SizedBox(height: 24),
          SectionHeader(
            title: 'Nearby Places',
            onAction: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => NearbyPlacesScreen())),
          ),
          SizedBox(height: 14),
          _NearbyPlacesSection(
            loading: _nearbyLoading,
            error: _nearbyError,
            places: _nearbyPlaces,
            onRetry: _loadNearby,
          ),
          SizedBox(height: 28),
          Text(
            _selectedCategory == null
                ? 'Popular Destinations'
                : '$_selectedCategory Spots',
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 14),
          ...filtered.map((p) => _PlaceListCard(place: p)),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? context.colors.ink : context.colors.card,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : context.colors.muted,
            ),
            SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same 130-height horizontal strip the dummy version always occupied —
/// loading/error/empty states fill that same footprint so the page
/// doesn't jump around while GPS/the API resolve.
class _NearbyPlacesSection extends StatelessWidget {
  const _NearbyPlacesSection({
    required this.loading,
    required this.error,
    required this.places,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final List<NearbyPlace> places;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 130,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return SizedBox(
        height: 130,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: context.colors.muted,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                error!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.colors.muted, fontSize: 12),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (places.isEmpty) {
      return SizedBox(
        height: 130,
        child: Center(
          child: Text(
            'No nearby places found',
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
        ),
      );
    }
    return SizedBox(
      height: 130,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: places.length,
        separatorBuilder: (_, _) => SizedBox(width: 12),
        itemBuilder: (context, index) => _NearbyPlaceCard(place: places[index]),
      ),
    );
  }
}

class _NearbyPlaceCard extends StatelessWidget {
  const _NearbyPlaceCard({required this.place});

  final NearbyPlace place;

  static const _placeholderGradient = AppColors.horizon;

  @override
  Widget build(BuildContext context) {
    final hasPhoto = place.photoUrl != null;
    return Container(
      width: 108,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: hasPhoto
            ? null
            : const LinearGradient(colors: _placeholderGradient),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPhoto)
            Image.network(
              place.photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: _placeholderGradient),
                ),
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: _placeholderGradient),
                      ),
                    ),
            ),
          if (hasPhoto)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x8C000000)],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(place.icon, color: Colors.white, size: 22),
                Spacer(),
                Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  place.distanceLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 10.5,
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

class _PlaceListCard extends StatelessWidget {
  const _PlaceListCard({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlaceDetailsScreen(place: place)),
        ),
        child: Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: place.gradient),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(place.icon, color: Colors.white, size: 28),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      place.area,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFB347),
                          size: 15,
                        ),
                        SizedBox(width: 2),
                        Text(
                          '${place.rating} (${place.reviews})',
                          style: TextStyle(
                            color: context.colors.ink,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
