import 'package:flutter/material.dart';

import '../../models/trip.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_header.dart';
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

/// "Trips" bottom-nav tab: the signed-in user's own trips (via Supabase
/// RLS — a trip only appears here if they're a member of it), bucketed
/// into Current / Upcoming / Past. Includes a search box that filters
/// trips by name, and the entry point for creating a new trip.
class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  final _searchController = TextEditingController();
  final _tripService = TripService();
  late Stream<List<Trip>> _tripsStream = _tripService.watchMyTrips();
  String _query = '';

  // This tab typically stays alive for the app's whole session (kept in
  // an IndexedStack by the bottom nav), so a stream that errors once —
  // e.g. a transient Supabase auth hiccup — would otherwise show that
  // error forever with no way to recover short of restarting the app.
  void _retry() => setState(() => _tripsStream = _tripService.watchMyTrips());

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: StreamBuilder<List<Trip>>(
        stream: _tripsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Couldn\'t load your trips',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final trips = snapshot.data ?? const <Trip>[];
          final q = _query.trim().toLowerCase();
          final searching = q.isNotEmpty;
          final filtered = searching
              ? trips.where((t) => t.name.toLowerCase().contains(q)).toList()
              : trips;

          final current = <Trip>[];
          final upcoming = <Trip>[];
          final past = <Trip>[];
          for (final t in filtered) {
            switch (t.status) {
              case TripStatus.current:
                current.add(t);
              case TripStatus.upcoming:
                upcoming.add(t);
              case TripStatus.past:
                past.add(t);
            }
          }

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
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CreateTripScreen(),
                        ),
                      ),
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
              const SizedBox(height: 26),
              if (noMatches)
                _NoSearchResults(query: _query.trim())
              else if (trips.isEmpty)
                const _EmptyTrips()
              else ...[
                if (current.isNotEmpty) ...[
                  SectionHeader(title: 'Current'),
                  const SizedBox(height: 14),
                  ..._tripCards(context, current, 'Ongoing'),
                  const SizedBox(height: 28),
                ],
                if (upcoming.isNotEmpty) ...[
                  SectionHeader(title: 'Upcoming'),
                  const SizedBox(height: 14),
                  ..._tripCards(context, upcoming, 'Upcoming'),
                  const SizedBox(height: 28),
                ],
                if (past.isNotEmpty) ...[
                  SectionHeader(title: 'Past Trips'),
                  const SizedBox(height: 14),
                  ..._tripCards(context, past, 'Completed'),
                ],
              ],
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
                              trip.destination.isEmpty
                                  ? 'No destination set'
                                  : trip.destination,
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
