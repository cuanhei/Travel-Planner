import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/nearby_place.dart';
import '../models/profile.dart';
import '../models/trip.dart';
import '../services/google_places_service.dart';
import '../services/photon_service.dart';
import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/profile_service.dart';
import '../services/trip_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../utils/weather_display.dart';
import '../widgets/destination_search_bar.dart';
import '../widgets/section_header.dart';
import '../widgets/user_avatar.dart';
import 'community/community_tab.dart';
import 'explore/explore_place_details_screen.dart';
import 'explore/explore_tab.dart';
import 'explore/nearby_places_screen.dart';
import 'group/join_trip_screen.dart';
import 'notifications_screen.dart';
import 'profile/edit_profile_screen.dart';
import 'profile/profile_tab.dart';
import 'transport/transport_routes_screen.dart';
import 'trip/create_trip_screen.dart';
import 'trip/map_view_screen.dart';
import 'trip/trip_details_screen.dart';
import 'trip/trips_tab.dart';
import 'weather/weather_forecast_screen.dart';

/// Time-of-day greeting for the dashboard header — matches the traveler's
/// device clock, not any trip's timezone.
String _greetingFor(DateTime time) {
  final hour = time.hour;
  if (hour < 5) return 'Good night 🌙';
  if (hour < 12) return 'Good morning ☀️';
  if (hour < 17) return 'Good afternoon 🌤️';
  if (hour < 21) return 'Good evening 🌇';
  return 'Good night 🌙';
}

/// UI-only home dashboard: greeting, upcoming trip, quick actions,
/// a trips carousel, and destination inspiration.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  // Not `static` — needs to reference this State's own key below, and a
  // GlobalKey is only ever meant to belong to one live State anyway.
  final _tripCardKey = GlobalKey<_UpcomingTripCardState>();
  final _destinationsKey = GlobalKey<_DestinationsCarouselState>();

  // Not static — labels must re-evaluate `tr()` on every rebuild so a
  // language change (which rebuilds the whole app, see `main.dart`)
  // actually retranslates them, instead of being frozen at whatever
  // language was active the first time this widget was ever built.
  List<({IconData icon, String label})> get _tabs => [
    (icon: Icons.home_rounded, label: tr('common_nav_home')),
    (icon: Icons.luggage_rounded, label: tr('common_nav_trips')),
    (icon: Icons.explore_rounded, label: tr('common_nav_explore')),
    (icon: Icons.groups_rounded, label: tr('common_nav_community')),
    (icon: Icons.person_rounded, label: tr('common_nav_profile')),

  ];

  late final _bodies = [
    _DashboardBody(tripCardKey: _tripCardKey, destinationsKey: _destinationsKey),
    TripsTab(),
    ExploreTab(),
    CommunityTab(),
    ProfileTab(),
  ];

  /// The dashboard's featured-trip card is inside an `IndexedStack`, which
  /// keeps it mounted (and its fetched trip cached) for the app's whole
  /// session — it would otherwise never notice trips created/changed
  /// elsewhere. Re-fetch whenever the traveler switches back to Home.
  void _onNavChanged(int i) {
    setState(() => _navIndex = i);
    if (i == 0) _tripCardKey.currentState?.reload();
  }

  @override
  void initState() {
    super.initState();
    ProfileService.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: IndexedStack(index: _navIndex, children: _bodies),
      ),
      bottomNavigationBar: _BottomNav(
        tabs: _tabs,
        index: _navIndex,
        onChanged: _onNavChanged,
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.tripCardKey, required this.destinationsKey});

  final GlobalKey<_UpcomingTripCardState> tripCardKey;
  final GlobalKey<_DestinationsCarouselState> destinationsKey;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
          sliver: SliverToBoxAdapter(child: _GreetingBar()),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
          sliver: SliverToBoxAdapter(child: DestinationSearchBar()),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 0),
          sliver: SliverToBoxAdapter(child: _UpcomingTripCard(key: tripCardKey)),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 0),
          sliver: SliverToBoxAdapter(
            child: _QuickActions(
              onTripCreated: () => tripCardKey.currentState?.reload(),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 0),
          sliver: SliverToBoxAdapter(child: _WeatherCard()),
        ),
        // SliverPadding(
        //   padding: EdgeInsets.fromLTRB(24, 28, 0, 0),
        //   sliver: SliverToBoxAdapter(
        //     child: Padding(
        //       padding: EdgeInsets.only(right: 24),
        //       child: SectionHeader(
        //         title: 'Trip Itinerary',
        //         onAction: () => showComingSoon(context, 'Full itinerary'),
        //       ),
        //     ),
        //   ),
        // ),
        // SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 28, 0, 0),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(right: 24),
              child: SectionHeader(
                title: tr('home_section_explore_destinations'),
                onAction: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NearbyPlacesScreen(
                      places: destinationsKey.currentState?.destinations ?? const [],
                      category: 'Tourist Attractions',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(child: _DestinationsCarousel(key: destinationsKey)),
        SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _GreetingBar extends StatelessWidget {
  const _GreetingBar();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile?>(
      valueListenable: ProfileService.instance.current,
      builder: (context, profile, _) {
        final name = profile?.fullName.isNotEmpty ?? false
            ? profile!.fullName
            : AuthService.instance.currentUserName;
        return Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('home_greeting'),
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${tr('home_hi')}, $name',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            _IconBadgeButton(
              icon: Icons.notifications_none_rounded,
              hasBadge: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => NotificationsScreen()),
              ),
            ),
            SizedBox(width: 12),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ),
                child: UserAvatar(
                  name: name,
                  avatarUrl: profile?.avatarUrl,
                  size: 46,
                  borderWidth: 2,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IconBadgeButton extends StatelessWidget {
  const _IconBadgeButton({
    required this.icon,
    required this.onTap,
    this.hasBadge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool hasBadge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      shape: CircleBorder(),
      child: InkWell(
        customBorder: CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, color: context.colors.ink, size: 22),
              if (hasBadge)
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
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


/// Featured trip on the dashboard: whichever trip is happening right now
/// (an "ongoing" ie. [TripStatus.current] one), or failing that the
/// soonest trip yet to start, or — if the traveler has neither — a
/// prompt to create one.
class _UpcomingTripCard extends StatefulWidget {
  const _UpcomingTripCard({super.key});

  @override
  State<_UpcomingTripCard> createState() => _UpcomingTripCardState();
}

class _UpcomingTripCardState extends State<_UpcomingTripCard> {
  late Future<Trip?> _tripFuture = _loadFeaturedTrip();

  @override
  void initState() {
    super.initState();
    // Belt-and-suspenders alongside the manual reload() calls (via
    // HomeScreen's GlobalKey) wired to Create Trip's specific entry
    // points below — this also catches a trip created/changed through
    // any other path (e.g. My Trips' own create button, joining a trip)
    // without needing every such path to remember to call reload() too.
    TripService.tripsChanged.addListener(reload);
  }

  @override
  void dispose() {
    TripService.tripsChanged.removeListener(reload);
    super.dispose();
  }

  /// Re-fetches the featured trip — called (via [HomeScreen]'s
  /// `GlobalKey`) whenever a trip may have changed elsewhere: switching
  /// back to the Home tab, or returning from Create Trip.
  void reload() {
    if (!mounted) return;
    setState(() => _tripFuture = _loadFeaturedTrip());
  }

  Future<Trip?> _loadFeaturedTrip() async {
    final trips = await TripService().myTrips();

    Trip? soonest(Iterable<Trip> candidates) {
      final list = candidates.toList()
        ..sort((a, b) {
          final aDate = a.startDate ?? a.createdAt;
          final bDate = b.startDate ?? b.createdAt;
          return aDate.compareTo(bDate);
        });
      return list.isEmpty ? null : list.first;
    }

    final ongoing = soonest(trips.where((t) => t.status == TripStatus.current));
    if (ongoing != null) return ongoing;
    return soonest(trips.where((t) => t.status == TripStatus.upcoming));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Trip?>(
      future: _tripFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _FeaturedTripLoading();
        }
        // Fetch failures fall back to the same "no trip" prompt rather
        // than a dedicated error card — but still logged, so a real
        // failure here doesn't silently masquerade as "you have no trips".
        if (snapshot.hasError) {
          debugPrint('Featured trip load failed: ${snapshot.error}');
        }
        final trip = snapshot.data;
        if (trip == null) {
          return _NoUpcomingTripCard(
            onCreateTrip: () async {
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => CreateTripScreen()));
              reload();
            },
          );
        }
        return _FeaturedTripCard(trip: trip);
      },
    );
  }
}

class _FeaturedTripCard extends StatelessWidget {
  const _FeaturedTripCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final isOngoing = trip.status == TripStatus.current;
    final route = trip.routeLabel;
    final subtitle = route == null
        ? trip.dateRangeLabel
        : '$route · ${trip.dateRangeLabel}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.horizon,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.horizon.last.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              isOngoing ? 'ONGOING TRIP' : 'UPCOMING TRIP',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.location_on_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 4),
              Expanded(
                child: Text(
                  trip.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            subtitle,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
          SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  trip.days == 0
                      ? 'Dates not set'
                      : '${trip.days} day${trip.days == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TripDetailsScreen(trip: trip),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    child: Text(
                      'View Itinerary',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeaturedTripLoading extends StatelessWidget {
  const _FeaturedTripLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 190,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.horizon,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      ),
    );
  }
}

class _NoUpcomingTripCard extends StatelessWidget {
  const _NoUpcomingTripCard({required this.onCreateTrip});

  final VoidCallback onCreateTrip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.horizon,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.horizon.last.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.card_travel_rounded, color: Colors.white, size: 28),
          SizedBox(height: 14),
          Text(
            tr('home_upcoming_trip_badge'),
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            tr('home_no_trip_subtitle'),
            style: TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
          SizedBox(height: 18),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onCreateTrip,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      color: context.colors.ink,
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      tr('home_create_trip_cta'),
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onTripCreated});

  /// Called after returning from Create Trip, so the dashboard's featured
  /// trip card (which doesn't otherwise know a trip was just added) can
  /// refresh itself.
  final VoidCallback onTripCreated;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        icon: Icons.add_rounded,
        label: tr('home_action_new_trip'),
        color: AppColors.accent,
        onTap: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => CreateTripScreen()));
          onTripCreated();
        },
      ),
      (
        icon: Icons.train_rounded,
        label: tr('home_action_transport'),
        color: Color(0xFF5C6BC0),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TransportRoutesScreen(showTripExtras: false),
          ),
        ),
      ),
      (
        icon: Icons.group_add_rounded,
        label: tr('home_action_join_trip'),
        color: Color(0xFF11998E),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const JoinTripScreen())),
      ),
      // (
      //   icon: Icons.explore_rounded,
      //   label: 'Explore',
      //   color: Color(0xFF11998E),
      //   onTap: () => showComingSoon(context, 'Explore'),
      // ),
      (
        icon: Icons.map_rounded,
        label: tr('home_action_map'),
        color: Color(0xFFFFB347),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => MapViewScreen())),
      ),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: actions.map((a) {
        return _QuickActionItem(
          icon: a.icon,
          label: a.label,
          color: a.color,
          onTap: a.onTap,
        );
      }).toList(),
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color.withValues(alpha: 0.12),
          shape: CircleBorder(),
          child: InkWell(
            customBorder: CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              child: Icon(icon, color: color, size: 24),
            ),
          ),
        ),
        SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: context.colors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Real forecast for the traveler's current location, via
/// [WeatherService] (MET Malaysia data through the government's open
/// API) — matched from GPS down to town level. Replaces what used to be
/// hardcoded "Penang, 31°C, Partly Cloudy" placeholder numbers.
class _WeatherCard extends StatefulWidget {
  const _WeatherCard();

  @override
  State<_WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<_WeatherCard> {
  final _weatherService = WeatherService();

  ResolvedWeather? _weather;
  bool _loading = true;
  String? _error;
  bool _outsideMalaysia = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _outsideMalaysia = false;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception(tr('home_location_services_off'));
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(tr('home_location_permission_denied_forever'));
      }
      if (permission == LocationPermission.denied) {
        throw Exception(tr('home_location_permission_needed'));
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final result = await _weatherService.getForecastForPosition(
        LatLng(position.latitude, position.longitude),
      );
      if (!mounted) return;
      setState(() {
        _weather = result;
        _loading = false;
      });
    } on LocationNotInMalaysiaException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _outsideMalaysia = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_outsideMalaysia) {
      return const _WeatherOutsideMalaysiaNotice();
    }
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => WeatherForecastScreen())),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2E9CCA), Color(0xFF6DD5FA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Color(0xFF2E9CCA).withValues(alpha: 0.3),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) return const _WeatherLoading();
    final error = _error;
    if (error != null) return _WeatherError(message: error, onRetry: _load);
    final weather = _weather;
    if (weather == null) {
      return _WeatherError(
        message: tr('home_weather_no_forecast'),
        onRetry: _load,
      );
    }
    return _WeatherContent(weather: weather);
  }
}

/// Shown instead of the weather card entirely when the traveler's
/// current location is confirmed to be outside Malaysia — this API only
/// covers Malaysia, so there's no forecast to show rather than an error
/// to retry.
class _WeatherOutsideMalaysiaNotice extends StatelessWidget {
  const _WeatherOutsideMalaysiaNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: context.colors.muted),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            tr('home_weather_outside_malaysia'),
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class _WeatherLoading extends StatelessWidget {
  const _WeatherLoading();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Text(
              tr('home_weather_loading'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherError extends StatelessWidget {
  const _WeatherError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: Colors.white, size: 20),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 11.5),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onRetry,
              child: Text(
                tr('home_weather_retry'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeatherContent extends StatelessWidget {
  const _WeatherContent({required this.weather});

  final ResolvedWeather weather;

  @override
  Widget build(BuildContext context) {
    final forecast = weather.forecast;
    final periods = [
      (label: tr('home_period_morning'), text: forecast.morningForecast),
      (label: tr('home_period_afternoon'), text: forecast.afternoonForecast),
      (label: tr('home_period_night'), text: forecast.nightForecast),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${weather.areaLabel}, ${tr('home_malaysia_word')}',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${forecast.minTemp}° – ${forecast.maxTemp}°C',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    translateWeather(forecast.summaryForecast),
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              weatherIconFor(forecast.summaryForecast),
              color: Colors.white,
              size: 44,
            ),
          ],
        ),
        SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < periods.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _PeriodTile(
                  label: periods[i].label,
                  forecastText: periods[i].text,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One Morning/Afternoon/Night slot — sized to share the card's width
/// equally with its siblings ([Expanded] from the parent `Row`) so a
/// long translated phrase (e.g. "Thunderstorms in Some Coastal Areas")
/// wraps within its own column instead of overflowing the row.
class _PeriodTile extends StatelessWidget {
  const _PeriodTile({required this.label, required this.forecastText});

  final String label;
  final String forecastText;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.white70, fontSize: 11),
        ),
        SizedBox(height: 6),
        Icon(weatherIconFor(forecastText), color: Colors.white, size: 18),
        SizedBox(height: 6),
        Text(
          translateWeather(forecastText),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Real tourist attractions near the traveler's current GPS position, via
/// Google Places API (New) Nearby Search (see [GooglePlacesService]) —
/// replaces what used to be 4 hardcoded Penang landmarks. Restricted
/// server-side to `tourist_attraction`, sorted client-side by distance,
/// and capped to the top 10 closest. Like [_WeatherCard], hides itself
/// behind an explanatory notice rather than showing anything when the
/// traveler's current location is confirmed to be outside Malaysia.
class _DestinationsCarousel extends StatefulWidget {
  const _DestinationsCarousel({super.key});

  @override
  State<_DestinationsCarousel> createState() => _DestinationsCarouselState();
}

class _DestinationsCarouselState extends State<_DestinationsCarousel> {
  final _placesService = GooglePlacesService();
  final _photon = PhotonService();

  List<NearbyPlace> _destinations = const [];
  bool _loading = true;
  String? _error;
  bool _outsideMalaysia = false;

  /// Exposed so [_DashboardBody]'s "See all" action can hand the same
  /// already-fetched list to [NearbyPlacesScreen] without re-fetching.
  List<NearbyPlace> get destinations => _destinations;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _outsideMalaysia = false;
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
        throw Exception(
          'Location permission is needed to suggest nearby destinations.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final center = LatLng(position.latitude, position.longitude);

      final area = await _photon.reverseAdministrative(center);
      if (area != null &&
          area.countryCode != null &&
          area.countryCode != 'MY') {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _outsideMalaysia = true;
        });
        return;
      }

      final results = await _placesService.nearbySearch(
        center: center,
        includedTypes: const {'tourist_attraction'},
      );
      results.sort(
        (a, b) =>
            (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity),
      );
      if (!mounted) return;
      setState(() {
        _destinations = results.take(10).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_outsideMalaysia) {
      return const _DestinationsOutsideMalaysiaNotice();
    }
    if (_loading) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return _DestinationsMessage(message: error, onRetry: _load);
    }
    if (_destinations.isEmpty) {
      return const _DestinationsMessage(
        message: 'No tourist attractions found nearby.',
      );
    }
    final destinations = _destinations;
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 24),
        itemCount: destinations.length,
        separatorBuilder: (_, _) => SizedBox(width: 14),
        itemBuilder: (context, index) => _DestinationCard(
          destination: destinations[index],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ExplorePlaceDetailsScreen(place: destinations[index]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the carousel when the traveler's current location is
/// confirmed to be outside Malaysia — this section only suggests places
/// around their current position, so there's nothing nearby to rank.
class _DestinationsOutsideMalaysiaNotice extends StatelessWidget {
  const _DestinationsOutsideMalaysiaNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: context.colors.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              "Oops, you're not in Malaysia right now — we can't suggest "
              'any nearby destinations.',
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _DestinationsMessage extends StatelessWidget {
  const _DestinationsMessage({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: context.colors.muted),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ),
          if (onRetry != null)
            GestureDetector(
              onTap: onRetry,
              child: Padding(
                padding: EdgeInsets.only(left: 8),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination, required this.onTap});

  final NearbyPlace destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final photoUrl = destination.photoUrl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: context.colors.ink.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              child: SizedBox(
                height: 120,
                width: double.infinity,
                child: photoUrl == null
                    ? _DestinationPlaceholder(icon: destination.icon)
                    : Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _DestinationPlaceholder(icon: destination.icon),
                        loadingBuilder: (context, child, progress) =>
                            progress == null
                            ? child
                            : _DestinationPlaceholder(icon: destination.icon),
                      ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    destination.distanceLabel,
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationPlaceholder extends StatelessWidget {
  const _DestinationPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: AppColors.horizon),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 34),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.tabs,
    required this.index,
    required this.onChanged,
  });

  final List<({IconData icon, String label})> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Container(
          height: 68,
          padding: EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final active = i == index;
              final tab = tabs[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 220),
                    margin: EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? context.colors.ink.withValues(alpha: 0.06)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          tab.icon,
                          color: active
                              ? context.colors.ink
                              : context.colors.muted,
                          size: 22,
                        ),
                        SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            color: active
                                ? context.colors.ink
                                : context.colors.muted,
                            fontSize: 10.5,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
