import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../transport/transport_routes_screen.dart';

/// How the traveler gets from one timeline stop to the next.
enum _TransportMode { undecided, publicTransport, eHailing, walk }

extension on _TransportMode {
  String get label => switch (this) {
    _TransportMode.undecided => tr('trip_mode_choose'),
    _TransportMode.publicTransport => tr('trip_mode_public_transport'),
    _TransportMode.eHailing => tr('trip_mode_ehailing'),
    _TransportMode.walk => tr('trip_mode_walking'),
  };

  IconData get icon => switch (this) {
    _TransportMode.undecided => Icons.alt_route_rounded,
    _TransportMode.publicTransport => Icons.directions_bus_filled_rounded,
    _TransportMode.eHailing => Icons.local_taxi_rounded,
    _TransportMode.walk => Icons.directions_walk_rounded,
  };

  Color get color => switch (this) {
    _TransportMode.undecided => const Color(0xFF6E7A93),
    _TransportMode.publicTransport => const Color(0xFF5C6BC0),
    _TransportMode.eHailing => AppColors.accent,
    _TransportMode.walk => const Color(0xFF11998E),
  };
}

/// A node in a day's timeline — either a stop ([_Activity]) or the
/// commute between two stops ([_Transport]).
abstract class _TimelineEntry {}

class _Activity extends _TimelineEntry {
  _Activity(
    this.time,
    this.title,
    this.subtitle,
    this.icon, {
    this.completed = false,
  });

  final String time;
  final String title;
  final String subtitle;
  final IconData icon;
  bool completed;
}

class _Transport extends _TimelineEntry {
  _Transport(this.estimatedMinutes, {this.mode = _TransportMode.undecided});

  final int estimatedMinutes;
  _TransportMode mode;
}

/// UI-only vertical timeline of each day's activities for the trip,
/// with the commute between stops shown as its own tappable step where
/// the traveler picks public transport, e-hailing, or walking.
class DailyTimelineScreen extends StatefulWidget {
  const DailyTimelineScreen({super.key});

  @override
  State<DailyTimelineScreen> createState() => _DailyTimelineScreenState();
}

class _DailyTimelineScreenState extends State<DailyTimelineScreen> {
  int _day = 0;

  // A getter (not `static final`) so the day labels below re-run tr() on
  // every build and pick up language changes.
  List<({String label, String date, List<_TimelineEntry> items})> get _days => [
    (
      label: '${tr('trip_day_word')} 1',
      date: 'Aug 14',
      items: <_TimelineEntry>[
        _Activity(
          '8:00 AM',
          'Breakfast at hotel',
          'Start the day fueled up',
          Icons.free_breakfast_rounded,
          completed: true,
        ),
        _Transport(15, mode: _TransportMode.walk),
        _Activity(
          '10:00 AM',
          'Komtar, George Town',
          'Shopping & observation deck',
          Icons.location_city_rounded,
          completed: true,
        ),
        _Transport(4, mode: _TransportMode.walk),
        _Activity(
          '1:00 PM',
          'Lunch at Komtar food court',
          'Local Penang hawker food',
          Icons.restaurant_rounded,
          completed: true,
        ),
        _Transport(10, mode: _TransportMode.walk),
        _Activity(
          '4:00 PM',
          'Stroll George Town street art',
          'Free time exploring murals',
          Icons.palette_rounded,
          completed: true,
        ),
      ],
    ),
    (
      label: '${tr('trip_day_word')} 2',
      date: 'Aug 15',
      items: <_TimelineEntry>[
        _Activity(
          '9:30 AM',
          'Breakfast nearby',
          'Local kopitiam',
          Icons.coffee_rounded,
          completed: true,
        ),
        _Transport(18),
        _Activity(
          '1:00 PM',
          'Gurney Drive & Plaza',
          'Shopping and seaside walk',
          Icons.shopping_bag_rounded,
        ),
        _Transport(6, mode: _TransportMode.walk),
        _Activity(
          '6:30 PM',
          'Dinner at Gurney food stalls',
          'Famous hawker street food',
          Icons.restaurant_rounded,
        ),
      ],
    ),
    (
      label: '${tr('trip_day_word')} 3',
      date: 'Aug 16',
      items: <_TimelineEntry>[
        _Activity(
          '11:00 AM',
          'Check out & luggage drop',
          'Prep for last stop',
          Icons.luggage_rounded,
        ),
        _Transport(25),
        _Activity(
          '4:00 PM',
          'Queensbay Mall',
          'Final shopping & souvenirs',
          Icons.storefront_rounded,
        ),
        _Transport(30),
        _Activity(
          '8:00 PM',
          'Head to airport',
          'End of trip',
          Icons.flight_takeoff_rounded,
        ),
      ],
    ),
  ];

  Future<void> _pickTransportMode(_Transport transport) async {
    final selected = await showModalBottomSheet<_TransportMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TransportModeSheet(current: transport.mode),
    );
    if (selected == null) return;
    setState(() => transport.mode = selected);
    if (selected == _TransportMode.publicTransport && mounted) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const TransportRoutesScreen()));
    }
  }

  void _completeActivity(_Activity activity) {
    setState(() => activity.completed = true);
  }

  /// The first not-yet-completed stop in [items] — only this one gets a
  /// "Complete" button, so the traveler works through the day in order.
  _Activity? _firstUndone(List<_TimelineEntry> items) {
    for (final item in items) {
      if (item is _Activity && !item.completed) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final day = _days[_day];
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('trip_daily_timeline_title'),
              subtitle: tr('trip_daily_timeline_subtitle'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(_days.length, (i) {
                  final active = i == _day;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _day = i),
                      child: Container(
                        margin: EdgeInsets.only(
                          right: i < _days.length - 1 ? 10 : 0,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: active
                              ? context.colors.ink
                              : context.colors.card,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _days[i].label,
                              style: TextStyle(
                                color: active
                                    ? Colors.white
                                    : context.colors.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _days[i].date,
                              style: TextStyle(
                                color: active
                                    ? Colors.white70
                                    : context.colors.muted,
                                fontSize: 11,
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
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                itemCount: day.items.length,
                itemBuilder: (context, index) {
                  final item = day.items[index];
                  final isLast = index == day.items.length - 1;
                  if (item is _Activity) {
                    return _ActivityRow(
                      activity: item,
                      isLast: isLast,
                      showCompleteButton: identical(item, _firstUndone(day.items)),
                      onComplete: () => _completeActivity(item),
                    );
                  }
                  final transport = item as _Transport;
                  return _TransportRow(
                    transport: transport,
                    isLast: isLast,
                    onTap: () => _pickTransportMode(transport),
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

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.leading,
    required this.content,
    required this.isLast,
  });

  final Widget leading;
  final Widget content;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              leading,
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: context.colors.muted.withValues(alpha: 0.2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.activity,
    required this.isLast,
    required this.showCompleteButton,
    required this.onComplete,
  });

  final _Activity activity;
  final bool isLast;
  final bool showCompleteButton;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    const done = Color(0xFF11998E);
    return _TimelineRow(
      isLast: isLast,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: activity.completed
              ? done.withValues(alpha: 0.15)
              : AppColors.accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          activity.completed ? Icons.check_rounded : activity.icon,
          color: activity.completed ? done : AppColors.accent,
          size: 18,
        ),
      ),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                activity.time,
                style: TextStyle(
                  color: activity.completed ? context.colors.muted : AppColors.accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
              if (activity.completed) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: done.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tr('trip_done_badge'),
                    style: TextStyle(
                      color: done,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            activity.title,
            style: TextStyle(
              color: activity.completed
                  ? context.colors.muted
                  : context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            activity.subtitle,
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
          if (showCompleteButton) ...[
            const SizedBox(height: 10),
            Material(
              color: context.colors.ink,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onComplete,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded, color: Colors.white, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        tr('trip_complete_button'),
                        style: const TextStyle(
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
    );
  }
}

class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.transport,
    required this.isLast,
    required this.onTap,
  });

  final _Transport transport;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mode = transport.mode;
    return _TimelineRow(
      isLast: isLast,
      leading: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: mode.color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: mode.color.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Icon(mode.icon, color: mode.color, size: 15),
      ),
      content: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '~${transport.estimatedMinutes} ${tr('trip_min_transport_suffix')}',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mode.label,
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.colors.muted,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransportModeSheet extends StatelessWidget {
  const _TransportModeSheet({required this.current});

  final _TransportMode current;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('trip_transport_dialog_title'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tr('trip_transport_dialog_subtitle'),
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 18),
            _ModeOption(
              mode: _TransportMode.publicTransport,
              description: tr('trip_desc_public_transport'),
              selected: current == _TransportMode.publicTransport,
              onTap: () =>
                  Navigator.of(context).pop(_TransportMode.publicTransport),
            ),
            const SizedBox(height: 10),
            _ModeOption(
              mode: _TransportMode.eHailing,
              description: tr('trip_desc_ehailing'),
              selected: current == _TransportMode.eHailing,
              onTap: () => Navigator.of(context).pop(_TransportMode.eHailing),
            ),
            const SizedBox(height: 10),
            _ModeOption(
              mode: _TransportMode.walk,
              description: tr('trip_desc_walking'),
              selected: current == _TransportMode.walk,
              onTap: () => Navigator.of(context).pop(_TransportMode.walk),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final _TransportMode mode;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? mode.color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: mode.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(mode.icon, color: mode.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      mode.label,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.colors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
