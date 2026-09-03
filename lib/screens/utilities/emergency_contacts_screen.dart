import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/trip_stop_location.dart';
import '../../services/emergency_contacts_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';

/// Local emergency numbers for the current trip's stops — switching
/// between stops (e.g. George Town → Alor Setar) switches which state's
/// numbers are shown, resolved from each stop's saved coordinates (see
/// [EmergencyContactsService]).
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final _tripService = TripService();
  final _emergencyService = EmergencyContactsService();

  String? _tripId;
  int _selectedIndex = 0;

  /// State label per stop, keyed by [TripStopLocation]'s own value
  /// equality (lat/lng/osmId) — populated lazily as stops arrive, so a
  /// stop is only reverse-geocoded once even as the stream re-emits.
  final _stateByStop = <TripStopLocation, String?>{};
  final _resolving = <TripStopLocation>{};

  @override
  void initState() {
    super.initState();
    _tripService.ensureDemoTrip().then((id) {
      if (mounted) setState(() => _tripId = id);
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
    final tripId = _tripId;
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
              child: tripId == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<List<TripStopLocation>>(
                      stream: _tripService.watchTripStops(tripId),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final stops = snapshot.data!;
                        if (stops.isEmpty) {
                          return _EmptyState(colors: context.colors);
                        }
                        if (_selectedIndex >= stops.length) _selectedIndex = 0;
                        final selected = stops[_selectedIndex];
                        // Kick off (idempotent) resolution for whichever
                        // stops don't have a cached state yet, without
                        // blocking this build.
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          for (final stop in stops) {
                            _resolveState(stop);
                          }
                        });
                        return _buildBody(context, stops, selected);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<TripStopLocation> stops,
    TripStopLocation selected,
  ) {
    final stateLabel = _stateByStop[selected];
    final resolving = !_stateByStop.containsKey(selected);
    final resolved = resolving
        ? null
        : _emergencyService.contactsForState(stateLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            scrollDirection: Axis.horizontal,
            itemCount: stops.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final stop = stops[index];
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
                    stop.name,
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
          child: resolving
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    Text(
                      'Local numbers for ${resolved!.stateLabel}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
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
                              color: const Color(
                                0xFF11998E,
                              ).withValues(alpha: 0.12),
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
