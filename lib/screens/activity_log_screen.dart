import 'package:flutter/material.dart';

import '../services/locale_service.dart';
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
  late final _groups = <String, List<ActivityEntry>>{
    tr('weather_day_today'): [
      ActivityEntry(
        icon: Icons.add_location_alt_rounded,
        title: tr('auth_activity_added_queensbay'),
        time: '2${tr('auth_hours_ago_suffix')}',
        color: AppColors.accent,
      ),
      ActivityEntry(
        icon: Icons.check_circle_rounded,
        title: tr('auth_activity_checked_in_komtar'),
        time: '5${tr('auth_hours_ago_suffix')}',
        color: const Color(0xFF11998E),
      ),
      ActivityEntry(
        icon: Icons.task_alt_rounded,
        title: tr('auth_activity_marked_breakfast_complete'),
        time: '8${tr('auth_hours_ago_suffix')}',
        color: const Color(0xFF11998E),
      ),
    ],
    tr('auth_yesterday_word'): [
      ActivityEntry(
        icon: Icons.star_rounded,
        title: tr('auth_activity_rated_gurney'),
        time: '1${tr('auth_d_ago_suffix')}',
        color: const Color(0xFFFFB347),
      ),
      ActivityEntry(
        icon: Icons.group_add_rounded,
        title: tr('auth_activity_joined_group'),
        time: '1${tr('auth_d_ago_suffix')}',
        color: const Color(0xFFEC407A),
      ),
      ActivityEntry(
        icon: Icons.directions_bus_filled_rounded,
        title: tr('auth_activity_saved_bus'),
        time: '1${tr('auth_d_ago_suffix')}',
        color: const Color(0xFF5C6BC0),
      ),
    ],
    tr('auth_earlier_this_week'): [
      ActivityEntry(
        icon: Icons.flight_takeoff_rounded,
        title: tr('auth_activity_created_trip'),
        time: '3${tr('auth_d_ago_suffix')}',
        color: const Color(0xFF10244A),
      ),
      ActivityEntry(
        icon: Icons.checklist_rounded,
        title: tr('auth_activity_added_packing_items'),
        time: '4${tr('auth_d_ago_suffix')}',
        color: const Color(0xFF26A69A),
      ),
      ActivityEntry(
        icon: Icons.account_balance_wallet_rounded,
        title: tr('auth_activity_set_budget'),
        time: '5${tr('auth_d_ago_suffix')}',
        color: const Color(0xFFFFB300),
      ),
      ActivityEntry(
        icon: Icons.how_to_vote_rounded,
        title: tr('auth_activity_voted_dinner'),
        time: '6${tr('auth_d_ago_suffix')}',
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
          tr('auth_clear_activity_confirm_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          tr('auth_clear_activity_confirm_body'),
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(tr('auth_clear_button')),
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
              title: tr('auth_activity_log_title'),
              subtitle: tr('auth_activity_log_subtitle'),
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
              tr('auth_no_activity_yet'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('auth_activity_empty_desc'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}
