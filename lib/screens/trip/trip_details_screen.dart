import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../services/budget_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';
import '../budget/budget_planner_screen.dart';
import '../group/group_dashboard_screen.dart';
import '../transport/transport_routes_screen.dart';
import '../utilities/utilities_home_screen.dart';
import '../weather/transport_weather_screen.dart';
import 'daily_timeline_screen.dart';
import 'edit_schedule_screen.dart';
import 'edit_trip_screen.dart';
import 'trip_map_screen.dart';

class TripDetailsScreen extends StatefulWidget {
  const TripDetailsScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  final _tripService = TripService();
  late Trip _trip = widget.trip;
  int? _stopsCount;
  int? _travelerCount;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stops = await _tripService.getTripStops(_trip.id);
      final travelers = await _tripService.memberCount(_trip.id);
      if (!mounted) return;
      setState(() {
        _stopsCount = stops.length;
        _travelerCount = travelers;
      });
    } catch (e) {
      debugPrint('Loading trip stats failed: $e');
    }
  }

  Future<void> _openEditTrip() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditTripScreen(trip: _trip)),
    );
    if (updated != true || !mounted) return;
    try {
      final reloaded = await _tripService.getTrip(_trip.id);
      if (mounted) setState(() => _trip = reloaded);
    } catch (e) {
      debugPrint('Reloading trip after edit failed: $e');
    }
    _loadStats();
  }

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
                        onPressed: _openEditTrip,
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
                        _trip.name,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if ((_trip.description ?? '').trim().isNotEmpty) ...[
                        SizedBox(height: 4),
                        Text(
                          _trip.description!.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13,
                          ),
                        ),
                      ],
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
                            _trip.destination.isEmpty
                                ? _trip.dateRangeLabel
                                : '${_trip.destination} · ${_trip.dateRangeLabel}',
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
                        _StatsRow(
                          trip: _trip,
                          stopsCount: _stopsCount,
                          travelerCount: _travelerCount,
                        ),
                        SizedBox(height: 28),
                        SectionHeader(title: 'Trip Tools'),
                        SizedBox(height: 14),
                        _ToolsGrid(trip: _trip, onScheduleUpdated: _loadStats),
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
  const _StatsRow({
    required this.trip,
    required this.stopsCount,
    required this.travelerCount,
  });

  final Trip trip;

  final int? stopsCount;
  final int? travelerCount;

  @override
  Widget build(BuildContext context) {
    final stats = [
      (
        label: 'Stops',
        value: stopsCount == null ? '…' : '$stopsCount',
        icon: Icons.flag_rounded,
      ),
      (
        label: 'Days',
        value: trip.days == 0 ? '—' : '${trip.days}',
        icon: Icons.calendar_today_rounded,
      ),
      (
        label: 'Budget',
        value: 'RM${trip.totalBudget.toStringAsFixed(0)}',
        icon: Icons.account_balance_wallet_rounded,
      ),
      (
        label: 'Travelers',
        value: travelerCount == null ? '…' : '$travelerCount',
        icon: Icons.people_alt_rounded,
      ),
    ];

    Widget tile(IconData icon, String value, String label) {
      return Container(
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
            Icon(icon, color: AppColors.accent, size: 18),
            SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: context.colors.muted, fontSize: 10.5),
            ),
          ],
        ),
      );
    }

    return Row(
      children: stats.map((s) {
        if (s.label == 'Budget') {
          return Expanded(
            child: StreamBuilder<double>(
              stream: BudgetService().watchTotalBudget(trip.id),
              builder: (context, snapshot) => tile(
                s.icon,
                'RM${formatAmount(snapshot.data ?? trip.totalBudget)}',
                s.label,
              ),
            ),
          );
        }
        return Expanded(child: tile(s.icon, s.value, s.label));
      }).toList(),
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  const _ToolsGrid({required this.trip, required this.onScheduleUpdated});

  final Trip trip;

  final VoidCallback onScheduleUpdated;

  String get tripId => trip.id;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (
        label: 'Daily\nTimeline',
        icon: Icons.view_timeline_rounded,
        color: Color(0xFF2E9CCA),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DailyTimelineScreen(tripId: tripId),
          ),
        ),
      ),
      (
        label: 'Edit\nSchedule',
        icon: Icons.edit_calendar_rounded,
        color: Color(0xFFE0704E),
        onTap: () async {
          final updated = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => EditScheduleScreen(tripId: tripId),
            ),
          );
          if (updated == true) onScheduleUpdated();
        },
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
        label: 'Transport\nWeather',
        icon: Icons.cloudy_snowing,
        color: Color(0xFF2E9CCA),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TransportWeatherScreen(tripId: tripId),
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
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UtilitiesHomeScreen(tripId: tripId),
          ),
        ),
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
