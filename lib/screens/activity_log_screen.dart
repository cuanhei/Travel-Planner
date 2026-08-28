import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/detail_header.dart';

/// A single recorded action — mirrors the home dashboard's "Recent
/// Activity" preview, but this screen shows the full history.
class ActivityEntry {
  ActivityEntry({
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

/// UI-only activity log: everything the traveler has done across the
/// app, grouped by when it happened. Reachable from the home
/// dashboard's "Recent Activity" section.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _groups = <String, List<ActivityEntry>>{
    'Today': [
      ActivityEntry(
        icon: Icons.add_location_alt_rounded,
        title: 'Added Queensbay Mall to your itinerary',
        time: '2h ago',
        color: AppColors.accent,
      ),
      ActivityEntry(
        icon: Icons.check_circle_rounded,
        title: 'Checked in at Komtar, George Town',
        time: '5h ago',
        color: const Color(0xFF11998E),
      ),
      ActivityEntry(
        icon: Icons.task_alt_rounded,
        title: 'Marked "Breakfast at Hotel" as complete',
        time: '8h ago',
        color: const Color(0xFF11998E),
      ),
    ],
    'Yesterday': [
      ActivityEntry(
        icon: Icons.star_rounded,
        title: 'Rated Gurney Drive & Plaza 4.5 stars',
        time: '1d ago',
        color: const Color(0xFFFFB347),
      ),
      ActivityEntry(
        icon: Icons.group_add_rounded,
        title: 'Joined the group "Penang Adventure"',
        time: '1d ago',
        color: const Color(0xFFEC407A),
      ),
      ActivityEntry(
        icon: Icons.directions_bus_filled_rounded,
        title: 'Saved Bus 401 (Hotel → Komtar) to My Routes',
        time: '1d ago',
        color: const Color(0xFF5C6BC0),
      ),
    ],
    'Earlier this week': [
      ActivityEntry(
        icon: Icons.flight_takeoff_rounded,
        title: 'Created trip "Penang Adventure"',
        time: '3d ago',
        color: const Color(0xFF10244A),
      ),
      ActivityEntry(
        icon: Icons.checklist_rounded,
        title: 'Added 5 items to the packing list',
        time: '4d ago',
        color: const Color(0xFF26A69A),
      ),
      ActivityEntry(
        icon: Icons.account_balance_wallet_rounded,
        title: 'Set the trip budget to RM 1,500',
        time: '5d ago',
        color: const Color(0xFFFFB300),
      ),
      ActivityEntry(
        icon: Icons.how_to_vote_rounded,
        title: 'Voted in "Where should we have dinner on Day 2?"',
        time: '6d ago',
        color: const Color(0xFFEC407A),
      ),
    ],
  };

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Clear activity log?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'This removes your entire activity history. This can\'t be undone.',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        for (final list in _groups.values) {
          list.clear();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _groups.values.every((list) => list.isEmpty);

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Activity Log',
              subtitle: 'Everything you\'ve done on this trip',
              trailing: IconButton(
                onPressed: isEmpty ? null : _confirmClear,
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  color: isEmpty
                      ? context.colors.muted.withValues(alpha: 0.4)
                      : context.colors.ink,
                ),
              ),
            ),
            Expanded(
              child: isEmpty
                  ? const _EmptyLog()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      children: [
                        for (final group in _groups.entries)
                          if (group.value.isNotEmpty) ...[
                            Text(
                              group.key,
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...group.value.map(
                              (activity) =>
                                  _ActivityLogTile(activity: activity),
                            ),
                            const SizedBox(height: 20),
                          ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityLogTile extends StatelessWidget {
  const _ActivityLogTile({required this.activity});

  final ActivityEntry activity;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: activity.color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(activity.icon, color: activity.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              activity.title,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            activity.time,
            style: TextStyle(color: context.colors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _EmptyLog extends StatelessWidget {
  const _EmptyLog();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_rounded, color: context.colors.muted, size: 44),
            const SizedBox(height: 16),
            Text(
              'No activity yet',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Things you do around the app will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
