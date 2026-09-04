import 'package:flutter/material.dart';

import '../../models/group_member.dart';
import '../../models/trip.dart';
import '../../models/trip_stop_location.dart';
import '../../services/group_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
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

/// Trip hub: overview, itinerary stops, and a tools grid linking out to
/// scheduling, map, weather, transport, budget, and group screens. Stop
/// counts and the "Activity" preview are now backed by the real
/// AI-Planner-generated schedule (`trip_schedule_stops`) and the real
/// traveler count (`trip_members`) rather than mock data; a stop's
/// "completed" checkmark is still local-only (there's no persisted
/// completion state in the schema yet), and the day-by-day timeline
/// itself (reached via "Activity"'s See All / the Tools Grid) is still
/// the old UI-only screen — not rebuilt here.
class TripDetailsScreen extends StatefulWidget {
  const TripDetailsScreen({super.key, required this.trip});

  final Trip trip;

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  final _tripService = TripService();
  late Future<List<TripStopLocation>> _stopsFuture = _tripService
      .getTripStops(widget.trip.id)
      .then(
        (stops) => stops
            .where(
              (s) =>
                  s.visitPurpose != VisitPurpose.accommodation &&
                  s.id != widget.trip.startLocationStopId &&
                  s.id != widget.trip.endLocationStopId,
            )
            .toList(),
      );
  late Future<List<TripScheduleRow>> _scheduleFuture = _tripService.getSchedule(
    widget.trip.id,
  );

  void _reloadSchedule() {
    if (!mounted) return;
    setState(() {
      _stopsFuture = _tripService
          .getTripStops(widget.trip.id)
          .then(
            (stops) => stops
                .where(
                  (s) =>
                      s.visitPurpose != VisitPurpose.accommodation &&
                      s.id != widget.trip.startLocationStopId &&
                      s.id != widget.trip.endLocationStopId,
                )
                .toList(),
          );
      _scheduleFuture = _tripService.getSchedule(widget.trip.id);
      _completedIndices.clear();
    });
  }

  /// Which schedule rows (by index into the fetched list) the traveler
  /// has checked off — local-only, since `trip_schedule_stops` has no
  /// completion column yet; resets if this screen is rebuilt/reopened.
  final Set<int> _completedIndices = {};

  void _toggleComplete(int index) =>
      setState(() => _completedIndices.add(index));

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
                          MaterialPageRoute(builder: (_) => EditTripScreen()),
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
                        _StatsRow(trip: widget.trip, stopsFuture: _stopsFuture),
                        SizedBox(height: 28),
                        SectionHeader(title: 'Trip Tools'),
                        SizedBox(height: 14),
                        _ToolsGrid(
                          tripId: widget.trip.id,
                          onScheduleEdited: _reloadSchedule,
                        ),
                        SizedBox(height: 28),
                        SectionHeader(
                          title: 'Activity',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  DailyTimelineScreen(tripId: widget.trip.id),
                            ),
                          ),
                        ),
                        SizedBox(height: 14),
                        FutureBuilder<List<TripScheduleRow>>(
                          future: _scheduleFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const _ActivityLoading();
                            }
                            final schedule = snapshot.data;
                            if (snapshot.hasError ||
                                schedule == null ||
                                schedule.isEmpty) {
                              return const _ActivityEmpty();
                            }
                            int? upcomingIndex;
                            int? completedIndex;
                            for (var i = 0; i < schedule.length; i++) {
                              if (upcomingIndex == null &&
                                  !_completedIndices.contains(i)) {
                                upcomingIndex = i;
                              }
                              if (_completedIndices.contains(i)) {
                                completedIndex = i;
                              }
                            }
                            final upcoming = upcomingIndex;
                            final completedAt = completedIndex;
                            return Column(
                              children: [
                                if (upcoming != null)
                                  _ActivityTile(
                                    row: schedule[upcoming],
                                    completed: false,
                                    onComplete: () => _toggleComplete(upcoming),
                                  ),
                                if (completedAt != null)
                                  _ActivityTile(
                                    row: schedule[completedAt],
                                    completed: true,
                                  ),
                              ],
                            );
                          },
                        ),
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

/// "Stops" (real `trip_stops`, accommodation excluded) and "Travelers"
/// (real `trip_members`, live via [GroupService.watchMembers]) are
/// resolved asynchronously; "Days"/"Budget" come straight off [trip],
/// already real.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.trip, required this.stopsFuture});

  final Trip trip;
  final Future<List<TripStopLocation>> stopsFuture;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        FutureBuilder<List<TripStopLocation>>(
          future: stopsFuture,
          builder: (context, snapshot) => _StatTile(
            icon: Icons.flag_rounded,
            label: 'Stops',
            value: snapshot.connectionState == ConnectionState.done
                ? '${snapshot.data?.length ?? 0}'
                : '—',
          ),
        ),
        _StatTile(
          icon: Icons.calendar_today_rounded,
          label: 'Days',
          value: '${trip.days}',
        ),
        _StatTile(
          icon: Icons.account_balance_wallet_rounded,
          label: 'Budget',
          value: 'RM${trip.totalBudget.toStringAsFixed(0)}',
        ),
        StreamBuilder<List<GroupMember>>(
          stream: GroupService().watchMembers(trip.id),
          builder: (context, snapshot) => _StatTile(
            icon: Icons.people_alt_rounded,
            label: 'Travelers',
            value: snapshot.hasData ? '${snapshot.data!.length}' : '—',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
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
      ),
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  const _ToolsGrid({required this.tripId, required this.onScheduleEdited});

  final String tripId;
  final VoidCallback onScheduleEdited;

  @override
  Widget build(BuildContext context) {
    final tools = [
      (
        label: 'Daily\nTimeline',
        icon: Icons.timeline_rounded,
        color: Color(0xFF5C6BC0),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DailyTimelineScreen(tripId: tripId),
          ),
        ),
      ),
      (
        label: 'Edit\nSchedule',
        icon: Icons.edit_calendar_rounded,
        color: Color(0xFF11998E),
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditScheduleScreen(tripId: tripId),
            ),
          );
          onScheduleEdited();
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

class _ActivityLoading extends StatelessWidget {
  const _ActivityLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}

class _ActivityEmpty extends StatelessWidget {
  const _ActivityEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        'No itinerary generated yet — this trip may not have travel '
        'dates set, or the AI Planner hasn\'t run for it.',
        style: TextStyle(color: context.colors.muted, fontSize: 12.5),
      ),
    );
  }
}

/// A simplified version of the Daily Timeline's activity row: status
/// tag + time, title, subtitle, a checkmark once done, and — only for
/// the upcoming stop — a Complete button. Backed by a real
/// [TripScheduleRow] from the AI-Planner-generated schedule.
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.row,
    required this.completed,
    this.onComplete,
  });

  final TripScheduleRow row;
  final bool completed;

  /// Present only for the stop that can currently be marked complete.
  final VoidCallback? onComplete;

  String get _timeLabel {
    final time = _parseTimeOfDay(
      row.scheduledVisitStart ?? row.scheduledArrival,
    );
    final dayLabel = 'Day ${row.dayNumber}';
    return time == null ? dayLabel : '$dayLabel · ${formatClockTime(time)}';
  }

  @override
  Widget build(BuildContext context) {
    const done = Color(0xFF11998E);
    final stop = row.stop;
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
                  : const LinearGradient(colors: AppColors.horizon),
              color: completed ? done.withValues(alpha: 0.15) : null,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              completed ? Icons.check_rounded : stop.categoryIcon,
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
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (completed ? done : AppColors.accent).withValues(
                          alpha: 0.12,
                        ),
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
                        _timeLabel,
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
                  stop.address,
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

/// Parses `trip_schedule_stops.scheduled_arrival`'s Postgres `time`
/// string (`"HH:mm:ss"`) into a [DateTime] carrying just that
/// time-of-day (date part is meaningless, only used with
/// [formatClockTime]) — null if [raw] is null or unparseable.
DateTime? _parseTimeOfDay(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return DateTime(2000, 1, 1, hour, minute);
}
