import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/trip_stop_location.dart';
import '../../services/emergency_contacts_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Local emergency numbers for the current trip's stops, grouped by state
/// (resolved from each stop's saved coordinates — see
/// [EmergencyContactsService]) rather than listed per stop, so e.g. Penang
/// Hill, Chew Jetty, and Batu Ferringhi — all in Penang — collapse into a
/// single "Penang" tab instead of repeating the same numbers three times.
/// Switching tabs (e.g. Penang → Kedah) switches which state's numbers are
/// shown.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _tripService = TripService();
  final _emergencyService = EmergencyContactsService();

  int _selectedIndex = 0;

  /// State label per stop, keyed by [TripStopLocation]'s own value
  /// equality (lat/lng/osmId) — populated lazily as stops arrive, so a
  /// stop is only reverse-geocoded once even as the stream re-emits.
  final _stateByStop = <TripStopLocation, String?>{};
  final _resolving = <TripStopLocation>{};

  /// Created once the demo trip's id resolves, not inline in [build] — a fresh
  /// `Stream` instance on every build would give `StreamBuilder` a
  /// changed `stream` identity each time, forcing it to tear down and
  /// resubscribe from scratch. Since [_resolveState] calls `setState` as
  /// each stop's geocode result lands, an inline stream would restart the
  /// whole fetch on every single one of those — which can keep resetting
  /// to "loading" indefinitely instead of ever settling.
  Stream<List<TripStopLocation>>? _stopsStream;

  @override
  void initState() {
    super.initState();
    _tripService.ensureDemoTrip().then((id) {
      if (mounted) {
        setState(() {
          _stopsStream = _tripService.watchTripStops(id);
        });
      }
    });
  }

  Future<void> _resolveState(TripStopLocation stop) async {
    if (_stateByStop.containsKey(stop) || _resolving.contains(stop)) return;
    _resolving.add(stop);
    final state = await _emergencyService.stateForStop(stop);
    _resolving.remove(stop);
    if (!mounted) return;
    setState(() => _stateByStop[stop] = state);
  }

  @override
  Widget build(BuildContext context) {
    final stopsStream = _stopsStream;
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'Emergency Contacts',
              subtitle: "Numbers for your trip's current stop",
            ),
            Expanded(
              child: stopsStream == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<List<TripStopLocation>>(
                      stream: stopsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return _ErrorState(colors: context.colors);
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final stops = snapshot.data!;
                        if (stops.isEmpty) {
                          return _EmptyState(colors: context.colors);
                        }
                        // Kick off (idempotent) resolution for whichever
                        // stops don't have a cached state yet, without
                        // blocking this build.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          for (final stop in stops) {
                            _resolveState(stop);
                          }
                        });
                        return _buildBody(context, stops);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, List<TripStopLocation> stops) {
    // Wait for every stop's state to resolve before grouping — building
    // groups incrementally as each one trickles in would make chips merge
    // and reorder under the traveler mid-scroll (e.g. a "Chew Jetty" chip
    // disappearing into "Penang" once its lookup finally lands).
    final allResolved = stops.every(_stateByStop.containsKey);
    if (!allResolved) {
      return const Center(child: CircularProgressIndicator());
    }

    // Stops sharing a state (e.g. Penang Hill, Chew Jetty, and Batu
    // Ferringhi all resolving to "Penang") collapse into one chip/tab
    // showing that state's numbers once, instead of repeating them per
    // stop. A stop whose state couldn't be resolved is dropped entirely
    // rather than lumped into a catch-all "Other" tab — nothing useful to
    // show for it beyond the national numbers every other tab already has.
    final groups = <String, List<TripStopLocation>>{};
    for (final stop in stops) {
      final state = _stateByStop[stop];
      if (state == null) continue;
      (groups[state] ??= []).add(stop);
    }
    if (groups.isEmpty) {
      return _EmptyState(colors: context.colors);
    }
    final groupKeys = groups.keys.toList();
    if (_selectedIndex >= groupKeys.length) _selectedIndex = 0;
    final selectedState = groupKeys[_selectedIndex];
    final stopsInGroup = groups[selectedState]!;
    final resolved = _emergencyService.contactsForState(selectedState);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            scrollDirection: Axis.horizontal,
            itemCount: groupKeys.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final isSelected = index == _selectedIndex;
              return GestureDetector(
                onTap: () => setState(() => _selectedIndex = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? context.colors.ink
                        : context.colors.card,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    groupKeys[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : context.colors.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Text(
                'Local numbers for ${resolved.stateLabel}',
                style: TextStyle(
                  color: context.colors.muted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                stopsInGroup.map((s) => s.name).join(' · '),
                style: TextStyle(color: context.colors.muted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              for (final c in resolved.contacts)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.colors.card,
                    borderRadius: BorderRadius.circular(18),
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
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: c.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(c.icon, color: c.color, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.label,
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              c.number,
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: const Color(0xFF11998E).withValues(alpha: 0.12),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _call(context, c.label, c.number),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.call_rounded,
                              color: Color(0xFF11998E),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens the device's phone dialer pre-filled with [rawNumber] via a
  /// `tel:` URI — non-digit formatting (spaces, dashes) is stripped since
  /// dialers expect a plain number (a leading `+` for international
  /// numbers is kept). Shows an error instead of failing silently if the
  /// platform has no dialer to hand off to (e.g. desktop/web).
  Future<void> _call(
    BuildContext context,
    String label,
    String rawNumber,
  ) async {
    final digits = rawNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri(scheme: 'tel', path: digits);
    var launched = false;
    try {
      launched = await launchUrl(uri);
    } catch (_) {
      launched = false;
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not start a call to $label on this device.'),
        ),
      );
    }
  }
}

/// Shown when [TripService.watchTripStops]'s stream errors — e.g. a
/// Realtime subscribe failure — instead of leaving the loading spinner
/// running forever, which is indistinguishable from "still loading" to
/// the traveler.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: colors.muted, size: 40),
            const SizedBox(height: 12),
            Text(
              "Couldn't load your trip's stops. Pull back and try again.",
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, color: colors.muted, size: 40),
            const SizedBox(height: 12),
            Text(
              'Add stops to your trip to see local emergency\n'
              "numbers for each one you visit.",
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.muted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
