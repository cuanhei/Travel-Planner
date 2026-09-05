import 'package:flutter/material.dart';

import '../../models/nearby_place.dart';
import '../../models/saved_place.dart';
import '../../services/locale_service.dart';
import '../../services/saved_places_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../explore/explore_place_details_screen.dart';

/// Bookmarked places — live per-user list backed by `saved_places`
/// (bookmarked from the "🔖" button on Explore's place details screen),
/// grouped as a simple grid.
class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  final _service = SavedPlacesService();
  late final Stream<List<SavedPlace>> _savedStream = _service
      .watchSavedPlaces();

  Future<void> _unsave(SavedPlace place) async {
    try {
      await _service.unsavePlace(place.placeId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not remove "${place.name}": $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('saved_places_title'),
              subtitle: tr('saved_places_subtitle'),
            ),
            Expanded(
              child: StreamBuilder<List<SavedPlace>>(
                stream: _savedStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Could not load saved places: ${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final results = snapshot.data!;
                  if (results.isEmpty) {
                    return Center(
                      child: Text(
                        tr('saved_places_empty'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                    itemCount: results.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 0.82,
                    ),
                    itemBuilder: (context, index) {
                      final place = results[index];
                      return _SavedPlaceCard(
                        place: place,
                        onUnsave: () => _unsave(place),
                      );
                    },
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

class _SavedPlaceCard extends StatelessWidget {
  const _SavedPlaceCard({required this.place, required this.onUnsave});

  final SavedPlace place;
  final VoidCallback onUnsave;

  static const _placeholderGradient = AppColors.horizon;

  @override
  Widget build(BuildContext context) {
    final nearbyPlace = place.toNearbyPlace();
    final hasPhoto = place.photoUrl != null;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExplorePlaceDetailsScreen(place: nearbyPlace),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: context.colors.ink.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  child: SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: hasPhoto
                        ? Image.network(
                            place.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _placeholderIcon(nearbyPlace),
                          )
                        : _placeholderIcon(nearbyPlace),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onUnsave,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.bookmark_rounded,
                        size: 14,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                  if (place.address.isNotEmpty) ...[
                    SizedBox(height: 3),
                    Text(
                      place.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
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

  Widget _placeholderIcon(NearbyPlace nearbyPlace) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: _placeholderGradient),
    ),
    child: Center(
      child: Icon(nearbyPlace.icon, color: Colors.white, size: 30),
    ),
  );
}
