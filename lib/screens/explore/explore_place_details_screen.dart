import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nearby_place.dart';
import '../../models/trip.dart';
import '../../models/trip_stop_location.dart';
import '../../services/community_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/route_map_view.dart';
import '../community/review_details_screen.dart';
import '../trip/edit_schedule_screen.dart';

/// Full profile for a real place — currently only reached from Explore's
/// Nearby Places (Google Places API (New) data), but named/shaped to
/// become the shared details screen once Popular Destinations moves off
/// its dummy `Place` catalog too. Shows every field the app actually has
/// (name, address, photo, type, open/closed status, distance, location).
/// No description or budget from Google: those aren't part of the Nearby
/// Search field mask. Ratings/reviews are this app's own review system
/// (`CommunityService`/`reviews` table), keyed by [NearbyPlace.name] the
/// same way `ReviewDetailsScreen` keys them by `place_name` elsewhere —
/// there's no separate place id to join on.
class ExplorePlaceDetailsScreen extends StatefulWidget {
  const ExplorePlaceDetailsScreen({super.key, required this.place});

  final NearbyPlace place;

  @override
  State<ExplorePlaceDetailsScreen> createState() =>
      _ExplorePlaceDetailsScreenState();
}

class _ExplorePlaceDetailsScreenState extends State<ExplorePlaceDetailsScreen> {
  final _reviewService = CommunityService();
  final _tripService = TripService();
  LatLng? _currentPosition;

  /// Whether the user can review this place — true once they have an
  /// unused visit (via [TripService.visitCount]) not yet spent on a review
  /// (via [CommunityService.myReviewCount]). Mirrors the gating on
  /// [ReviewDetailsScreen]'s "Write a Review" button, so the top-level
  /// "Add Review" button here reflects the same rule up front instead of
  /// only surfacing it after drilling in.
  bool _canReview = false;

  /// Whether the place has ever been visited at all, once loaded — used to
  /// pick the disabled-button message.
  bool _everVisited = false;

  @override
  void initState() {
    super.initState();
    _locateCurrentPosition();
    _loadCanReview();
  }

  /// Re-checked after returning from [ReviewDetailsScreen] — a review
  /// submitted there spends the visit that unlocked it, so this button
  /// needs to go back to disabled without requiring the user to leave and
  /// reopen this screen.
  Future<void> _loadCanReview() async {
    final results = await Future.wait([
      _tripService.visitCount(widget.place.name),
      _reviewService.myReviewCount(widget.place.name),
    ]);
    if (!mounted) return;
    final visits = results[0];
    final reviewsSoFar = results[1];
    setState(() {
      _everVisited = visits > 0;
      _canReview = visits > reviewsSoFar;
    });
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
                      _Tag(
                        label: place.distanceLabel,
                        icon: Icons.near_me_rounded,
                      ),
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
                    'Reviews',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ReviewsSummaryCard(
                    service: _reviewService,
                    placeName: place.name,
                  ),
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
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: Opacity(
                          opacity: _canReview ? 1 : 0.5,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              if (!_canReview) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    behavior: SnackBarBehavior.floating,
                                    content: Text(
                                      _everVisited
                                          ? "You've already reviewed this "
                                                'place — visit it again to '
                                                'write another review.'
                                          : 'You can review a destination '
                                                'after visiting it on a trip '
                                                "that's finished.",
                                    ),
                                  ),
                                );
                                return;
                              }
                              Navigator.of(context)
                                  .push(
                                    MaterialPageRoute(
                                      builder: (_) => ReviewDetailsScreen(
                                        placeName: place.name,
                                      ),
                                    ),
                                  )
                                  .then((_) => _loadCanReview());
                            },
                            icon: const Icon(
                              Icons.rate_review_outlined,
                              size: 18,
                            ),
                            label: const Text('Add Review'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.colors.ink,
                              side: BorderSide(
                                color: context.colors.muted.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GradientButton(
                          label: 'Add to Trip',
                          icon: Icons.playlist_add_rounded,
                          height: 48,
                          onPressed: () => _openAddToTripSheet(context, place),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddToTripSheet(
    BuildContext context,
    NearbyPlace place,
  ) async {
    final trip = await showModalBottomSheet<Trip>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddToTripSheet(place: place),
    );
    if (trip == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditScheduleScreen(
          tripId: trip.id,
          pendingStop: TripStopLocation.fromNearbyPlace(place),
        ),
      ),
    );
  }
}

/// Tappable "X.X ★ (N reviews)" summary — live via
/// [CommunityService.watchRatingSummaries] so a review submitted from
/// [ReviewDetailsScreen] updates this the moment its Realtime stream
/// picks up the new row. Shows a neutral "No reviews yet" state instead
/// of a bare 0.0 when [placeName] has none. Tapping either state opens
/// the full [ReviewDetailsScreen] (list + "Write a Review").
class _ReviewsSummaryCard extends StatelessWidget {
  const _ReviewsSummaryCard({required this.service, required this.placeName});

  final CommunityService service;
  final String placeName;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, ({double average, int count})>>(
      stream: service.watchRatingSummaries([placeName]),
      builder: (context, snapshot) {
        final summary = snapshot.data?[placeName];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReviewDetailsScreen(placeName: placeName),
            ),
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                if (summary != null) ...[
                  Text(
                    summary.average.toStringAsFixed(1),
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < summary.average.round()
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: const Color(0xFFFFB347),
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${summary.count} review${summary.count == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: Text(
                      'No reviews yet — be the first!',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Add to Trip" bottom sheet — lists the signed-in traveler's current +
/// upcoming trips where they're the organizer, since only an organizer
/// can add a place to a trip (a plain member can't). Tapping a trip just
/// picks it — [_openAddToTripSheet] takes the selection from here and
/// hands off to Edit Schedule, which stages the place as a new,
/// not-yet-saved stop on that trip's first upcoming day for the traveler
/// to actually confirm (or remove) there, rather than this sheet saving
/// it unreviewed.
class _AddToTripSheet extends StatefulWidget {
  const _AddToTripSheet({required this.place});

  // ignore: unused_field
  final NearbyPlace place;

  @override
  State<_AddToTripSheet> createState() => _AddToTripSheetState();
}

class _AddToTripSheetState extends State<_AddToTripSheet> {
  final _tripService = TripService();
  List<Trip>? _trips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _trips = null;
      _error = null;
    });
    try {
      final trips = await _tripService.organizerCurrentAndUpcomingTrips();
      if (!mounted) return;
      setState(() => _trips = trips);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your trips. Try again.');
    }
  }

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
          constraints: const BoxConstraints(maxHeight: 480),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add to Trip',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: context.colors.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Only the trip organizer can add a place — members '
                      "can't do this.",
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(child: _buildBody(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final trips = _trips;
    if (trips == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (trips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          "You don't organize any current or upcoming trips yet.",
          style: TextStyle(color: context.colors.muted, fontSize: 12.5),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: trips.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _TripOptionTile(
        trip: trips[i],
        onTap: () => Navigator.of(context).pop(trips[i]),
      ),
    );
  }
}

/// One organizer trip in the "Add to Trip" list — tapping it just picks
/// this trip (see [_AddToTripSheet]'s doc comment for what happens next).
class _TripOptionTile extends StatelessWidget {
  const _TripOptionTile({required this.trip, required this.onTap});

  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOngoing = trip.status == TripStatus.current;
    final badgeLabel = isOngoing ? 'Ongoing' : 'Upcoming';
    final badgeColor = isOngoing ? const Color(0xFF11998E) : AppColors.accent;
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trip.routeLabel ?? trip.dateRangeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),
              ),
            ],
          ),
        ),
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
