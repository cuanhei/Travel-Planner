import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/locale_service.dart';
import '../services/notification_prefs_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/coming_soon.dart';
import '../widgets/destination_search_bar.dart';
import '../widgets/section_header.dart';
import '../widgets/user_avatar.dart';
import 'activity_log_screen.dart';
import 'budget/budget_planner_screen.dart';
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

  // A getter, not `static final` — `tr()` must re-evaluate on every build.
  // A `static final` initializer runs exactly once per app session, so it
  // would freeze these labels to whatever language was active the first
  // time this class was ever touched.
  List<({IconData icon, String label})> get _tabs => [
    (icon: Icons.home_rounded, label: tr('common_nav_home')),
    (icon: Icons.luggage_rounded, label: tr('common_nav_trips')),
    (icon: Icons.explore_rounded, label: tr('common_nav_explore')),
    (icon: Icons.groups_rounded, label: tr('common_nav_community')),
    (icon: Icons.person_rounded, label: tr('common_nav_profile')),
  ];

  static final _bodies = [
    _DashboardBody(),
    TripsTab(),
    ExploreTab(),
    CommunityTab(),
    ProfileTab(),
  ];

  @override
  void initState() {
    super.initState();
    ProfileService.instance.load();
    NotificationPrefsService.instance.load();
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
                title: tr('auth_explore_destinations'),
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
              title: tr('auth_recent_activity'),
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
                    tr('auth_good_morning'),
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '${tr('auth_hi')} $name',
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
            UserAvatar(name: name, avatarUrl: profile?.avatarUrl, size: 46),
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
                  tr('auth_upcoming_trip'),
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
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => TripDetailsScreen()),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    child: Text(
                      tr('auth_view_itinerary'),
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
        label: tr('auth_new_trip'),
        color: AppColors.accent,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => CreateTripScreen())),
      ),
      (
        icon: Icons.train_rounded,
        label: tr('auth_transport'),
        color: Color(0xFF5C6BC0),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TransportRoutesScreen(showTripExtras: false),
          ),
        ),
      ),
      (
        icon: Icons.group_add_rounded,
        label: tr('auth_join_trip'),
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
        label: tr('auth_map'),
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

class _WeatherCard extends StatelessWidget {
  const _WeatherCard();

  static final _hourly = [
    (label: 'Now', icon: Icons.wb_sunny_rounded, temp: '31°'),
    (label: '1 PM', icon: Icons.wb_cloudy_rounded, temp: '30°'),
    (label: '3 PM', icon: Icons.cloud_rounded, temp: '29°'),
    (label: '5 PM', icon: Icons.grain_rounded, temp: '27°'),
  ];

  @override
  Widget build(BuildContext context) {
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
        child: Column(
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
                        'Penang, Malaysia',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '31°C',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Partly Cloudy · Feels like 34°C',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.wb_sunny_rounded, color: Colors.white, size: 44),
              ],
            ),
            SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _hourly.map((h) {
                return Column(
                  children: [
                    Text(
                      h.label,
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                    SizedBox(height: 6),
                    Icon(h.icon, color: Colors.white, size: 18),
                    SizedBox(height: 6),
                    Text(
                      h.temp,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
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

class _DestinationsCarousel extends StatelessWidget {
  const _DestinationsCarousel();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 24),
        itemCount: _destinations.length,
        separatorBuilder: (_, _) => SizedBox(width: 14),
        itemBuilder: (context, index) =>
            _DestinationCard(destination: _destinations[index]),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination});

  final _Destination destination;

  @override
  Widget build(BuildContext context) {
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
                      destination.rating.toStringAsFixed(1),
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
