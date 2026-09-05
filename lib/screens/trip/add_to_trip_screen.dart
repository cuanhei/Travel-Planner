import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show Place;
import 'create_trip_screen.dart';
import 'trip_data.dart';

class AddToTripScreen extends StatefulWidget {
  const AddToTripScreen({super.key, required this.place});

  final Place place;

  @override
  State<AddToTripScreen> createState() => _AddToTripScreenState();
}

class _AddToTripScreenState extends State<AddToTripScreen> {
  TripSummary? _selected;

  void _confirm() {
    final trip = _selected;
    if (trip == null) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text('Added ${widget.place.name} to "${trip.title}"'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Add to Trip', subtitle: widget.place.name),
            Expanded(
              child: upcomingTrips.isEmpty
                  ? _EmptyState(place: widget.place)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      children: [
                        Text(
                          'Choose which trip to add this stop to',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...upcomingTrips.map(
                          (trip) => _TripOption(
                            trip: trip,
                            selected: _selected == trip,
                            onTap: () => setState(() => _selected = trip),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _NewTripOption(place: widget.place),
                      ],
                    ),
            ),
            if (upcomingTrips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: GradientButton(
                  label: 'Add to Trip',
                  icon: Icons.playlist_add_check_rounded,
                  onPressed: _selected == null ? () {} : _confirm,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TripOption extends StatelessWidget {
  const _TripOption({
    required this.trip,
    required this.selected,
    required this.onTap,
  });

  final TripSummary trip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? context.colors.ink : Colors.transparent,
              width: 1.5,
            ),
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
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: trip.gradient),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Icon(trip.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.title,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${trip.place} · ${trip.dates}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? context.colors.ink : context.colors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewTripOption extends StatelessWidget {
  const _NewTripOption({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const CreateTripScreen())),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: context.colors.muted.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.colors.ink.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.add_rounded,
                color: context.colors.ink,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Create a new trip for ${place.name}',
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.luggage_rounded, color: context.colors.muted, size: 48),
          const SizedBox(height: 16),
          Text(
            'No upcoming trips yet',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Create a trip first, then add ${place.name} to it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 20),
          GradientButton(
            label: 'Create Trip',
            icon: Icons.add_rounded,
            expand: false,
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CreateTripScreen())),
          ),
        ],
      ),
    );
  }
}
