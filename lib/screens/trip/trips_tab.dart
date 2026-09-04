import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import 'create_trip_screen.dart';
import 'trip_details_screen.dart';

/// Cycled by trip index purely for visual variety — trips don't store a
/// cover color/gradient of their own.
const _tripGradients = [
  AppColors.horizon,
  AppColors.sunset,
  AppColors.lagoon,
  AppColors.dusk,
];

List<Color> _gradientFor(int index) =>
    _tripGradients[index % _tripGradients.length];

const _statusFilters = [
  (status: TripStatus.current, label: 'Current', icon: Icons.explore_rounded),
  (
    status: TripStatus.upcoming,
    label: 'Upcoming',
    icon: Icons.schedule_rounded,
  ),
  (status: TripStatus.past, label: 'Past', icon: Icons.history_rounded),
];

/// Badge text shown on a trip card — distinct from the filter chip
/// labels above ("Current" reads as "Ongoing" once it's on a card).
String _badgeLabelFor(TripStatus status) => switch (status) {
  TripStatus.current => 'Ongoing',
  TripStatus.upcoming => 'Upcoming',
  TripStatus.past => 'Completed',
};

/// "Trips" bottom-nav tab: the signed-in user's own trips, bucketed into
/// Current / Upcoming / Past. Includes a search box that filters trips by
/// name, and the entry point for creating a new trip.
class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  final _searchController = TextEditingController();
  final _tripService = TripService();
  List<Trip> _trips = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  TripStatus _selectedStatus = TripStatus.current;

  @override
  void initState() {
    super.initState();
    _load();
    // Catches a trip created from anywhere other than this tab's own
    // "Create Trip" button (Home dashboard, Add to Trip, ...) — this
    // tab stays mounted in the bottom nav's IndexedStack the whole time,
    // so there's no push/pop of its own to hook a reload onto for those.
    TripService.tripsChanged.addListener(_load);
  }

  @override
  void dispose() {
    TripService.tripsChanged.removeListener(_load);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final trips = await _tripService.myTrips();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _openCreateTrip() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateTripScreen()));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Builder(
        builder: (context) {
          if (_loading) return const _TripsLoading();
          if (_error != null) {
            return _TripsError(message: _error!, onRetry: _load);
          }

          final trips = _trips;
          final q = _query.trim().toLowerCase();
          final searching = q.isNotEmpty;
          final filtered = searching
              ? trips.where((t) => t.name.toLowerCase().contains(q)).toList()
              : trips;

          final byStatus = <TripStatus, List<Trip>>{
            TripStatus.current: [],
            TripStatus.upcoming: [],
            TripStatus.past: [],
          };
          for (final t in filtered) {
            byStatus[t.status]!.add(t);
          }
          final displayed = byStatus[_selectedStatus]!;

          final noMatches = searching && filtered.isEmpty;

          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Trips',
                          style: TextStyle(
                            color: context.colors.ink,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${trips.length} trip${trips.length == 1 ? '' : 's'} planned so far',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: context.colors.ink,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _openCreateTrip,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.add_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _TripSearchField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
              ),
              const SizedBox(height: 16),
              if (!(noMatches || trips.isEmpty)) ...[
                _StatusFilterChips(
                  selected: _selectedStatus,
                  onSelected: (s) => setState(() => _selectedStatus = s),
                ),
                const SizedBox(height: 20),
              ],
              if (noMatches)
                _NoSearchResults(query: _query.trim())
              else if (trips.isEmpty)
                const _EmptyTrips()
              else if (displayed.isEmpty)
                _NoTripsInStatus(status: _selectedStatus)
              else
                ..._tripCards(context, displayed, _badgeLabelFor(_selectedStatus)),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _tripCards(
    BuildContext context,
    List<Trip> trips,
    String status,
  ) {
    return [
      for (var i = 0; i < trips.length; i++)
        _TripCard(
          trip: trips[i],
          status: status,
          gradient: _gradientFor(i),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TripDetailsScreen(trip: trips[i]),
            ),
          ),
        ),
    ];
  }
}

class _TripSearchField extends StatelessWidget {
  const _TripSearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: context.colors.muted, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: TextStyle(
                color: context.colors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: 'Search trips by name…',
                hintStyle: TextStyle(
                  color: context.colors.muted,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Icon(
                Icons.close_rounded,
                color: context.colors.muted,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }
}

/// Current / Upcoming / Past category filter — single-select, mirrors
/// [_CategoryChip]'s pill style from the Explore tab's category filter.
class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips({required this.selected, required this.onSelected});

  final TripStatus selected;
  final ValueChanged<TripStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final filter in _statusFilters) ...[
          Expanded(
            child: _StatusChip(
              label: filter.label,
              icon: filter.icon,
              selected: filter.status == selected,
              onTap: () => onSelected(filter.status),
            ),
          ),
          if (filter != _statusFilters.last) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 38,
        decoration: BoxDecoration(
          color: selected ? context.colors.ink : context.colors.card,
          borderRadius: BorderRadius.circular(19),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? Colors.white : context.colors.muted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoTripsInStatus extends StatelessWidget {
  const _NoTripsInStatus({required this.status});

  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    final label = _statusFilters
        .firstWhere((f) => f.status == status)
        .label
        .toLowerCase();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(Icons.event_busy_rounded, color: context.colors.muted, size: 30),
          const SizedBox(height: 10),
          Text(
            'No $label trips',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Trips will show up here once they match this category.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, color: context.colors.muted, size: 30),
          const SizedBox(height: 10),
          Text(
            'No trips named "$query"',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try a different trip name.',
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TripsLoading extends StatelessWidget {
  const _TripsLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _TripsError extends StatelessWidget {
  const _TripsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.muted,
              size: 30,
            ),
            const SizedBox(height: 10),
            Text(
              'Could not load your trips',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.status,
    required this.gradient,
    required this.onTap,
  });

  final Trip trip;
  final String status;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = status != 'Completed';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: context.colors.ink.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 16, 16, 18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: active ? 0.22 : 0.16,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white.withValues(alpha: 0.85),
                            size: 18,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        trip.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_rounded,
                            color: Colors.white.withValues(alpha: 0.85),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              trip.routeLabel ?? 'No destination set',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                  child: Row(
                    children: [
                      Icon(
                        Icons.event_rounded,
                        size: 14,
                        color: context.colors.muted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          trip.dateRangeLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatBadge(
                        icon: Icons.account_balance_wallet_rounded,
                        label: 'RM ${trip.totalBudget.toStringAsFixed(0)}',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.colors.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(Icons.luggage_rounded, color: context.colors.muted, size: 30),
          const SizedBox(height: 10),
          Text(
            'No trips yet',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap + to start planning your next adventure.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
