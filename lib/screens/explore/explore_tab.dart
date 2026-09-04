import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
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

  /// Identity is by [name] rather than every field, since translated
  /// fields (area, description, avgBudget) are recomputed fresh on each
  /// access to [places] — two instances for the same catalog entry must
  /// still compare equal across locale changes and rebuilds.
  @override
  bool operator ==(Object other) => other is Place && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

List<Place> get places => [
  Place(
    name: 'Penang Hill',
    area: tr('explore_area_air_itam'),
    category: 'Nature',
    rating: 4.8,
    reviews: 2140,
    gradient: AppColors.lagoon,
    icon: Icons.terrain_rounded,
    description: tr('explore_desc_penang_hill'),
    avgBudget: 'RM 30 – 50',
    distanceKm: 8.2,
  ),
  Place(
    name: 'Batu Ferringhi',
    area: tr('explore_area_tanjung_bungah'),
    category: 'Beach',
    rating: 4.6,
    reviews: 1560,
    gradient: AppColors.sunset,
    icon: Icons.beach_access_rounded,
    description: tr('explore_desc_batu_ferringhi'),
    avgBudget: 'RM 20 – 60',
    distanceKm: 12.5,
  ),
  Place(
    name: 'Chew Jetty',
    area: tr('explore_area_george_town'),
    category: 'Culture',
    rating: 4.7,
    reviews: 3980,
    gradient: AppColors.horizon,
    icon: Icons.holiday_village_rounded,
    description: tr('explore_desc_chew_jetty'),
    avgBudget: '${tr('explore_free_word')} – RM 20',
    distanceKm: 2.1,
  ),
  Place(
    name: 'The Top Komtar',
    area: tr('explore_area_george_town'),
    category: 'Shopping',
    rating: 4.5,
    reviews: 1120,
    gradient: AppColors.dusk,
    icon: Icons.visibility_rounded,
    description: tr('explore_desc_komtar'),
    avgBudget: 'RM 30 – 80',
    distanceKm: 0.5,
  ),
  Place(
    name: 'Gurney Drive Hawker Centre',
    area: tr('explore_area_gurney_drive'),
    category: 'Food',
    rating: 4.7,
    reviews: 2670,
    gradient: AppColors.sunset,
    icon: Icons.restaurant_rounded,
    description: tr('explore_desc_gurney'),
    avgBudget: 'RM 15 – 40',
    distanceKm: 3.4,
  ),
  Place(
    name: 'Upside Down Museum',
    area: tr('explore_area_george_town'),
    category: 'Nightlife',
    rating: 4.4,
    reviews: 890,
    gradient: AppColors.lagoon,
    icon: Icons.nightlife_rounded,
    description: tr('explore_desc_updown_museum'),
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
            tr('explore_title'),
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            tr('explore_subtitle'),
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
                  label: tr('explore_all'),
                  icon: Icons.apps_rounded,
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                SizedBox(width: 8),
                ...categories.map(
                  (c) => Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: _CategoryChip(
                      label: tr('explore_category_${c.label.toLowerCase()}'),
                      icon: c.icon,
                      selected: _selectedCategory == c.label,
                      onTap: () => setState(() => _selectedCategory = c.label),
                    ),
                  ),
                ),
                _CategoryChip(
                  label: tr('explore_browse_all'),
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
            title: tr('explore_nearby_places'),
            onAction: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => NearbyPlacesScreen())),
          ),
          SizedBox(height: 14),
          SizedBox(
            height: 130,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: places.length,
              separatorBuilder: (_, _) => SizedBox(width: 12),
              itemBuilder: (context, index) {
                final p = places[index];
                return _NearbyChip(place: p);
              },
            ),
          ),
          SizedBox(height: 28),
          Text(
            _selectedCategory == null
                ? tr('explore_popular_destinations')
                : '${tr('explore_category_${_selectedCategory!.toLowerCase()}')} '
                      '${tr('explore_spots_suffix')}',
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

class _NearbyChip extends StatelessWidget {
  const _NearbyChip({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlaceDetailsScreen(place: place)),
      ),
      child: Container(
        width: 108,
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: place.gradient),
          borderRadius: BorderRadius.circular(18),
        ),
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
              '${place.distanceKm} km',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
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
