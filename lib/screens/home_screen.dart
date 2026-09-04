import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../services/community_service.dart';
import '../services/trip_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../utils/weather_display.dart';
import '../widgets/coming_soon.dart';
import '../widgets/destination_search_bar.dart';
import '../widgets/section_header.dart';
import 'activity_log_screen.dart';
import 'community/community_tab.dart';
import 'explore/explore_tab.dart';
import 'group/join_trip_screen.dart';
import 'notifications_screen.dart';
import 'profile/profile_tab.dart';
import 'transport/transport_routes_screen.dart';
import 'trip/create_trip_screen.dart';
import 'trip/map_view_screen.dart';
import 'trip/trip_details_screen.dart';
import 'trip/trips_tab.dart';
import 'weather/weather_forecast_screen.dart';

/// UI-only home dashboard: greeting, upcoming trip, quick actions,
/// a trips carousel, and destination inspiration.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  static final _tabs = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.luggage_rounded, label: 'Trips'),
    (icon: Icons.explore_rounded, label: 'Explore'),
    (icon: Icons.groups_rounded, label: 'Community'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  static final _bodies = [
    _DashboardBody(),
    TripsTab(),
    ExploreTab(),
    CommunityTab(),
    ProfileTab(),
  ];

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
        onChanged: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody();

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
          sliver: SliverToBoxAdapter(child: _UpcomingTripCard()),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 0),
          sliver: SliverToBoxAdapter(child: _QuickActions()),
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
        // SliverToBoxAdapter(child: _TripsCarousel()),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 28, 0, 0),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(right: 24),
              child: SectionHeader(
                title: 'Explore Destinations',
                onAction: () => showComingSoon(context, 'Explore'),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 14)),
        SliverToBoxAdapter(child: _DestinationsCarousel()),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 0),
          sliver: SliverToBoxAdapter(
            child: SectionHeader(
              title: 'Recent Activity',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ActivityLogScreen()),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(24, 14, 24, 0),
          sliver: SliverToBoxAdapter(child: _RecentActivityList()),
        ),
        SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _GreetingBar extends StatelessWidget {
  const _GreetingBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good morning ☀️',
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Hi, Alex',
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
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => NotificationsScreen())),
        ),
        SizedBox(width: 12),
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: AppColors.sunset,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            'A',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
      ],
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

class _UpcomingTripCard extends StatelessWidget {
  const _UpcomingTripCard();

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
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'UPCOMING TRIP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              Spacer(),
              Icon(Icons.bookmark_rounded, color: Colors.white, size: 20),
            ],
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.location_on_rounded, color: Colors.white70, size: 18),
              SizedBox(width: 4),
              Text(
                'Penang, Malaysia',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            'Komtar → Gurney → Queensbay',
            style: TextStyle(color: Colors.white70, fontSize: 13.5),
          ),
          SizedBox(height: 22),
          Row(
            children: [
              _AvatarStack(),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '3 stops · 3 days',
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
                  onTap: () async {
                    final tripId = await TripService().ensureDemoTrip();
                    final trip = await TripService().getTrip(tripId);
                    if (!context.mounted) return;
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TripDetailsScreen(trip: trip),
                      ),
                    );
                  },
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

class _AvatarStack extends StatelessWidget {
  const _AvatarStack();

  @override
  Widget build(BuildContext context) {
    final colors = [Color(0xFFFF7A59), Color(0xFF38EF7D), Color(0xFFFFB347)];
    return SizedBox(
      width: 54,
      height: 28,
      child: Stack(
        children: List.generate(3, (i) {
          return Positioned(
            left: i * 16.0,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors[i],
                border: Border.all(color: Color(0xFF10244A), width: 2),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = [
      (
        icon: Icons.add_rounded,
        label: 'New Trip',
        color: AppColors.accent,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => CreateTripScreen())),
      ),
      (
        icon: Icons.train_rounded,
        label: 'Transport',
        color: Color(0xFF5C6BC0),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TransportRoutesScreen(showTripExtras: false),
          ),
        ),
      ),
      (
        icon: Icons.group_add_rounded,
        label: 'Join Trip',
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
        label: 'Map',
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
        throw Exception('Location permission is needed for local weather.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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
      return _WeatherError(message: 'No forecast available.', onRetry: _load);
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
            'Weather forecast will only show for your current location if '
            'you are in Malaysia.',
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
    return const SizedBox(
      height: 96,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Getting your local weather…',
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
              child: const Text(
                'Retry',
                style: TextStyle(
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
      (label: 'Morning', text: forecast.morningForecast),
      (label: 'Afternoon', text: forecast.afternoonForecast),
      (label: 'Night', text: forecast.nightForecast),
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
                    '${weather.areaLabel}, Malaysia',
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
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 11)),
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

class _Trip {
  _Trip({
    required this.city,
    required this.dates,
    required this.status,
    required this.gradient,
    required this.icon,
    this.highlight = false,
  });

  final String city;
  final String dates;
  final String status;
  final List<Color> gradient;
  final IconData icon;
  final bool highlight;
}

final _trips = [
  _Trip(
    city: 'Komtar, George Town',
    dates: 'Day 1 · Morning',
    status: 'First Stop',
    gradient: AppColors.horizon,
    icon: Icons.location_city_rounded,
    highlight: true,
  ),
  _Trip(
    city: 'Gurney Drive & Plaza',
    dates: 'Day 2 · Afternoon',
    status: 'Next Stop',
    gradient: AppColors.dusk,
    icon: Icons.shopping_bag_rounded,
  ),
  _Trip(
    city: 'Queensbay Mall',
    dates: 'Day 3 · Evening',
    status: 'Final Stop',
    gradient: AppColors.sunset,
    icon: Icons.storefront_rounded,
  ),
];

class _TripsCarousel extends StatelessWidget {
  const _TripsCarousel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 24),
        itemCount: _trips.length,
        separatorBuilder: (_, _) => SizedBox(width: 14),
        itemBuilder: (context, index) => _TripCard(trip: _trips[index]),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final _Trip trip;

  @override
  Widget build(BuildContext context) {
    final isUpcoming = trip.highlight;
    return Container(
      width: 210,
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: trip.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: trip.gradient.last.withValues(alpha: 0.3),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(
                    alpha: isUpcoming ? 0.22 : 0.14,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  trip.status,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Spacer(),
              Icon(
                trip.icon,
                color: Colors.white.withValues(alpha: 0.85),
                size: 20,
              ),
            ],
          ),
          Spacer(),
          Text(
            trip.city,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            trip.dates,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Destination {
  _Destination({
    required this.name,
    required this.country,
    required this.rating,
    required this.gradient,
    required this.icon,
  });

  final String name;
  final String country;
  final double rating;
  final List<Color> gradient;
  final IconData icon;
}

final _destinations = [
  _Destination(
    name: 'Penang Hill',
    country: 'Air Itam',
    rating: 4.8,
    gradient: AppColors.lagoon,
    icon: Icons.terrain_rounded,
  ),
  _Destination(
    name: 'Batu Ferringhi',
    country: 'Tanjung Bungah',
    rating: 4.6,
    gradient: AppColors.sunset,
    icon: Icons.beach_access_rounded,
  ),
  _Destination(
    name: 'Chew Jetty',
    country: 'George Town',
    rating: 4.7,
    gradient: AppColors.horizon,
    icon: Icons.holiday_village_rounded,
  ),
  _Destination(
    name: 'The Top Komtar',
    country: 'George Town',
    rating: 4.5,
    gradient: AppColors.dusk,
    icon: Icons.visibility_rounded,
  ),
];

class _DestinationsCarousel extends StatefulWidget {
  const _DestinationsCarousel();

  @override
  State<_DestinationsCarousel> createState() => _DestinationsCarouselState();
}

class _DestinationsCarouselState extends State<_DestinationsCarousel> {
  /// Live average rating + review count per destination name, from the
  /// `reviews` table — overrides each [_Destination]'s hardcoded seed
  /// `rating` once a place has any real reviews. Streamed so a review
  /// added elsewhere in the app shows up here without needing Home to be
  /// remounted (see [CommunityService.watchRatingSummaries]).
  late final Stream<Map<String, ({double average, int count})>> _ratingsStream =
      CommunityService().watchRatingSummaries(
        _destinations.map((d) => d.name).toList(),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, ({double average, int count})>>(
      stream: _ratingsStream,
      builder: (context, snapshot) {
        final ratings = snapshot.data ?? const {};
        return SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: 24),
            itemCount: _destinations.length,
            separatorBuilder: (_, _) => SizedBox(width: 14),
            itemBuilder: (context, index) => _DestinationCard(
              destination: _destinations[index],
              rating: ratings[_destinations[index].name],
            ),
          ),
        );
      },
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination, this.rating});

  final _Destination destination;

  /// Live rating summary from real reviews — `null`/absent means this
  /// place has no real reviews yet, shown as 0.0/0 rather than
  /// [_Destination]'s seed placeholder rating (see
  /// [_DestinationsCarouselState]).
  final ({double average, int count})? rating;

  @override
  Widget build(BuildContext context) {
    final displayRating = rating?.average ?? 0.0;
    final displayCount = rating?.count ?? 0;
    return Container(
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
          Stack(
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: destination.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
                alignment: Alignment.center,
                child: Icon(
                  destination.icon,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 34,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.favorite_border_rounded,
                    size: 14,
                    color: context.colors.ink,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination.name,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        destination.country,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.star_rounded,
                      color: Color(0xFFFFB347),
                      size: 14,
                    ),
                    SizedBox(width: 2),
                    Text(
                      displayRating.toStringAsFixed(1),
                      style: TextStyle(
                        color: context.colors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 2),
                    Text(
                      '($displayCount)',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Activity {
  _Activity({
    required this.icon,
    required this.title,
    required this.time,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String time;
  final Color color;
}

final _activities = [
  _Activity(
    icon: Icons.add_location_alt_rounded,
    title: 'Added Queensbay Mall to your itinerary',
    time: '2h ago',
    color: AppColors.accent,
  ),
  _Activity(
    icon: Icons.check_circle_rounded,
    title: 'Checked in at Komtar, George Town',
    time: '1d ago',
    color: Color(0xFF11998E),
  ),
  _Activity(
    icon: Icons.star_rounded,
    title: 'Rated Gurney Drive & Plaza 4.5 stars',
    time: '2d ago',
    color: Color(0xFFFFB347),
  ),
];

class _RecentActivityList extends StatelessWidget {
  const _RecentActivityList();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _activities.map((a) => _ActivityTile(activity: a)).toList(),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final _Activity activity;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
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
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: activity.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(activity.icon, color: activity.color, size: 19),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  activity.time,
                  style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
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
