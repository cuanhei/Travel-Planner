import 'package:flutter/material.dart';

import '../../models/nearby_place.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'explore_place_details_screen.dart';

class NearbyPlacesScreen extends StatelessWidget {
  const NearbyPlacesScreen({super.key, required this.places, this.category});

  final List<NearbyPlace> places;

  final String? category;

  @override
  Widget build(BuildContext context) {
    final sorted = [...places]
      ..sort((a, b) => (a.distanceKm ?? 0).compareTo(b.distanceKm ?? 0));

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Nearby Places',
              subtitle: category == null
                  ? 'Sorted by distance from you'
                  : '$category · sorted by distance from you',
            ),
            Expanded(
              child: sorted.isEmpty
                  ? Center(
                      child: Text(
                        category == null
                            ? 'No nearby places found'
                            : 'No nearby $category places found',
                        style: TextStyle(color: context.colors.muted),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: sorted.length,
                      itemBuilder: (context, index) => _NearbyPlaceListCard(
                        place: sorted[index],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ExplorePlaceDetailsScreen(place: sorted[index]),
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

class _NearbyPlaceListCard extends StatelessWidget {
  const _NearbyPlaceListCard({required this.place, required this.onTap});

  final NearbyPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photoUrl = place.photoUrl;
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
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
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: photoUrl == null
                      ? _Placeholder(icon: place.icon)
                      : Image.network(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _Placeholder(icon: place.icon),
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : _Placeholder(icon: place.icon),
                        ),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      place.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      place.distanceLabel,
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
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

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: AppColors.horizon),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }
}
