import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';
import '../budget/budget_planner_screen.dart';
import '../group/group_dashboard_screen.dart';
import '../transport/transport_routes_screen.dart';
import '../utilities/utilities_home_screen.dart';
import '../weather/weather_forecast_screen.dart';
import 'daily_timeline_screen.dart';
import 'edit_schedule_screen.dart';
import 'edit_trip_screen.dart';
import 'trip_map_screen.dart';

/// A single itinerary stop. Mutable `completed` flag so the "Activity"
/// section's Complete button can check a stop off — UI-only, no
/// persistence.
class _Stop {
  _Stop({
    required this.name,
    required this.time,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.completed = false,
  });

  final String name;
  final String time;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  bool completed;
}

/// Trip hub: overview, itinerary stops, and a tools grid linking out to
/// scheduling, map, weather, transport, budget, and group screens. The
/// itinerary stops/activity feed below are still UI-only mock data; the
/// Budget and Group tools are wired live to [trip].
class TripDetailsScreen extends StatefulWidget {
  const TripDetailsScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  final _stops = [
    _Stop(
      name: 'Komtar, George Town',
      time: 'Day 1 · 10:00 AM',
      subtitle: 'Shopping & observation deck',
      icon: Icons.location_city_rounded,
      gradient: AppColors.horizon,
      completed: true,
    ),
    _Stop(
      name: 'Gurney Drive & Plaza',
      time: 'Day 2 · 1:00 PM',
      subtitle: 'Shopping and seaside walk',
      icon: Icons.shopping_bag_rounded,
      gradient: AppColors.dusk,
    ),
    _Stop(
      name: 'Queensbay Mall',
      time: 'Day 3 · 4:00 PM',
      subtitle: 'Final shopping & souvenirs',
      icon: Icons.storefront_rounded,
      gradient: AppColors.sunset,
    ),
  ];

  /// The next stop that hasn't happened yet — falls back to the last
  /// stop if the whole trip is already complete.
  _Stop get _upcomingStop =>
      _stops.firstWhere((s) => !s.completed, orElse: () => _stops.last);

  /// The most recently completed stop — falls back to the first stop
  /// if nothing has been marked complete yet.
  _Stop get _completedStop =>
      _stops.lastWhere((s) => s.completed, orElse: () => _stops.first);

  void _completeStop(_Stop stop) => setState(() => stop.completed = true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: Stack(
        children: [
          Container(
            height: 230,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.horizon,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => EditTripScreen(),
                          ),
                        ),
                        icon: Icon(
                          Icons.edit_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(24, 8, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.trip.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: Colors.white.withValues(alpha: 0.8),
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            widget.trip.destination.isEmpty
                                ? widget.trip.dateRangeLabel
                                : '${widget.trip.destination} · ${widget.trip.dateRangeLabel}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    margin: EdgeInsets.only(top: 20),
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(32),
                      ),
                    ),
                    child: ListView(
                      children: [
                        _StatsRow(trip: widget.trip),
                        SizedBox(height: 28),
                        SectionHeader(title: 'Trip Tools'),
                        SizedBox(height: 14),
                        _ToolsGrid(tripId: widget.trip.id),
                        SizedBox(height: 28),
                        SectionHeader(
                          title: 'Activity',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DailyTimelineScreen(),
                            ),
                          ),
                        ),
                        SizedBox(height: 14),
                        _ActivityTile(
                          stop: _upcomingStop,
                          onComplete: () => _completeStop(_upcomingStop),
                        ),
                        _ActivityTile(stop: _completedStop),
                      ],
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

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (label: 'Stops', value: '3', icon: Icons.flag_rounded),
      (
        label: 'Days',
        value: '${trip.days == 0 ? 3 : trip.days}',
        icon: Icons.calendar_today_rounded,
      ),
      (
        label: 'Budget',
        value: 'RM${trip.totalBudget.toStringAsFixed(0)}',
        icon: Icons.account_balance_wallet_rounded,
      ),
      (label: 'Travelers', value: '2', icon: Icons.people_alt_rounded),
    ];

    return Row(
      children: stats.map((s) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: 10),
            padding: EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: context.colors.card,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: context.colors.ink.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Icon(s.icon, color: AppColors.accent, size: 18),
                SizedBox(height: 6),
                Text(
                  s.value,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  s.label,
                  style: TextStyle(color: context.colors.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  const _ToolsGrid({required this.tripId});

  final String tripId;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (
        label: 'Daily\nTimeline',
        icon: Icons.timeline_rounded,
        color: Color(0xFF5C6BC0),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => DailyTimelineScreen())),
      ),
      (
        label: 'Edit\nSchedule',
        icon: Icons.edit_calendar_rounded,
        color: Color(0xFF11998E),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => EditScheduleScreen())),
      ),
      (
        label: 'Map\nView',
        icon: Icons.map_rounded,
        color: Color(0xFFFFB347),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TripMapScreen(tripId: tripId)),
        ),
      ),
      (
        label: 'Weather',
        icon: Icons.wb_sunny_rounded,
        color: Color(0xFF2E9CCA),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => WeatherForecastScreen())),
      ),
      (
        label: 'Transport',
        icon: Icons.directions_bus_filled_rounded,
        color: Color(0xFF8E63CE),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransportRoutesScreen(tripId: tripId),
          ),
        ),
      ),
      (
        label: 'Budget',
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.accent,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BudgetPlannerScreen(tripId: tripId),
          ),
        ),
      ),
      (
        label: 'Utilities',
        icon: Icons.checklist_rounded,
        color: Color(0xFF11998E),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => UtilitiesHomeScreen())),
      ),
      (
        label: 'Group',
        icon: Icons.group_rounded,
        color: Color(0xFF5C6BC0),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GroupDashboardScreen(tripId: tripId),
          ),
        ),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: tools.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 14,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final t = tools[index];
        return GestureDetector(
          onTap: t.onTap,
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: t.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(t.icon, color: t.color, size: 22),
              ),
              SizedBox(height: 6),
              Text(
                t.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A simplified version of the Daily Timeline's activity row: status
/// tag + time, title, subtitle, a checkmark once done, and — only for
/// the upcoming stop — a Complete button.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.stop, this.onComplete});

  final _Stop stop;

  /// Present only for the stop that can currently be marked complete.
  final VoidCallback? onComplete;

  @override
  Widget build(BuildContext context) {
    const done = Color(0xFF11998E);
    final completed = stop.completed;
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 14),
      padding: EdgeInsets.all(16),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: completed
                  ? null
                  : LinearGradient(colors: stop.gradient),
              color: completed ? done.withValues(alpha: 0.15) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              completed ? Icons.check_rounded : stop.icon,
              color: completed ? done : Colors.white,
              size: 20,
            ),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: (completed ? done : AppColors.accent)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        completed ? 'COMPLETED' : 'UPCOMING',
                        style: TextStyle(
                          color: completed ? done : AppColors.accent,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        stop.time,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  stop.name,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  stop.subtitle,
                  style: TextStyle(color: context.colors.muted, fontSize: 12),
                ),
                if (onComplete != null) ...[
                  SizedBox(height: 12),
                  Material(
                    color: context.colors.ink,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onComplete,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Complete',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
