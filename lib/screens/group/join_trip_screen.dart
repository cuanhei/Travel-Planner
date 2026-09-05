import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/join_request.dart';
import '../../models/trip.dart';
import '../../models/trip_invite_preview.dart';
import '../../services/group_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../trip/trip_details_screen.dart';

const _codeLength = 6;

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class JoinTripScreen extends StatefulWidget {
  const JoinTripScreen({super.key});

  @override
  State<JoinTripScreen> createState() => _JoinTripScreenState();
}

class _JoinTripScreenState extends State<JoinTripScreen> {
  final _controller = TextEditingController();
  final _groupService = GroupService();
  final _tripService = TripService();
  String _code = '';
  bool _isSubmitting = false;
  String? _openingTripId;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_isSubmitting) return;
    if (_code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Please enter an invite code.'),
        ),
      );
      return;
    }
    if (_code.length != _codeLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Invite code must be $_codeLength characters.'),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);

    try {
      final preview = await _groupService.getTripPreviewByCode(_code);
      if (preview != null) {
        final validationError = await _validateJoin(preview);
        if (validationError != null) {
          if (!mounted) return;
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 6),
              content: Text(validationError),
            ),
          );
          return;
        }
      }
    } catch (_) {}

    try {
      await _groupService.requestToJoin(_code);
    } on PostgrestException catch (e) {
      if (e.message.toLowerCase().contains('already a member')) {
        await _handleAlreadyMember();
        return;
      }
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      final isDateGuardError =
          e.message.toLowerCase().contains('already ended') ||
          e.message.toLowerCase().contains('clash');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: isDateGuardError
              ? const Duration(seconds: 6)
              : const Duration(seconds: 4),
          content: Text(e.message),
        ),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: const Text(
          'Request sent! Waiting for the organizer to approve.',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  Future<String?> _validateJoin(TripInvitePreview preview) async {
    final start = preview.startDate;
    final end = preview.endDate;

    if (end != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (today.isAfter(end)) {
        return '"${preview.name}" already ended (${preview.dateRangeLabel}) '
            "— you can only join a trip that's still current or upcoming.";
      }
    }

    if (start != null && end != null) {
      List<Trip> myTrips;
      try {
        myTrips = await _tripService.getMyTrips();
      } catch (_) {
        return null;
      }
      for (final trip in myTrips) {
        final tStart = trip.startDate;
        final tEnd = trip.endDate;
        if (tStart == null || tEnd == null) continue;

        if (!start.isAfter(tEnd) && !tStart.isAfter(end)) {
          return '"${preview.name}" (${preview.dateRangeLabel}) clashes with '
              'your trip "${trip.name}" (${trip.dateRangeLabel}) — you '
              "can't be in two trips at the same time.";
        }
      }
    }

    return null;
  }

  Future<void> _handleAlreadyMember() async {
    String? tripId;
    try {
      tripId = await _groupService.findMyTripByCode(_code);
    } catch (_) {
      tripId = null;
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        duration: const Duration(seconds: 5),
        content: Text(
          tripId == null
              ? "You're already in this trip!"
              : "You're already in this trip! Taking you there...",
        ),
      ),
    );
    if (tripId == null) return;

    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    try {
      final trip = await _tripService.getTrip(tripId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)),
      );
    } catch (_) {}
  }

  Future<void> _openTrip(String tripId) async {
    if (_openingTripId != null) return;
    setState(() => _openingTripId = tripId);
    try {
      final trip = await _tripService.getTrip(tripId);
      if (!mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => TripDetailsScreen(trip: trip)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not open trip: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingTripId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: 'Join a Trip',
              subtitle: 'Enter a friend\'s invite code',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.group_add_rounded,
                        color: AppColors.accent,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Invite Code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Ask the trip organizer for their 6-character code',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _controller,
                    onChanged: (v) => setState(() => _code = v),
                    maxLength: _codeLength,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [_UpperCaseFormatter()],
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                      letterSpacing: 10,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '••••••',
                      hintStyle: TextStyle(
                        color: context.colors.muted.withValues(alpha: 0.4),
                        letterSpacing: 10,
                      ),
                      filled: true,
                      fillColor: context.colors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: context.colors.ink,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                  const SizedBox(height: 28),
                  GradientButton(
                    label: 'Join Trip',
                    icon: Icons.group_add_rounded,
                    onPressed: _isSubmitting ? () {} : () => _join(),
                  ),
                  const SizedBox(height: 32),
                  StreamBuilder<List<MyJoinRequest>>(
                    stream: _groupService.watchMyRequests(),
                    builder: (context, snapshot) {
                      final requests = snapshot.data ?? const <MyJoinRequest>[];
                      if (requests.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your Requests',
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...requests.map(
                            (r) => _RequestStatusTile(
                              request: r,
                              isOpening: _openingTripId == r.tripId,
                              onTap: r.status == 'approved'
                                  ? () => _openTrip(r.tripId)
                                  : null,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestStatusTile extends StatelessWidget {
  const _RequestStatusTile({
    required this.request,
    this.onTap,
    this.isOpening = false,
  });

  final MyJoinRequest request;

  final VoidCallback? onTap;
  final bool isOpening;

  (Color, String) get _statusVisuals => switch (request.status) {
    'approved' => (const Color(0xFF11998E), 'Approved'),
    'rejected' => (Colors.redAccent, 'Declined'),
    'removed' => (Colors.grey, 'Removed'),
    _ => (const Color(0xFFFFB347), 'Pending'),
  };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _statusVisuals;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 5),
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              request.tripName ?? 'Trip',
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if ((request.destination ?? '').isNotEmpty)
                            request.destination!,
                          request.dateRangeLabel,
                        ].join(' · '),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      if (request.status == 'pending') ...[
                        const SizedBox(height: 4),
                        Text(
                          'Waiting for the organizer to approve',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (request.status == 'approved') ...[
                        const SizedBox(height: 4),
                        Text(
                          "You're in! This trip now appears in My Trips.",
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                      if (request.status == 'removed') ...[
                        const SizedBox(height: 4),
                        Text(
                          'You were removed from this trip by the organizer.',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (request.status == 'rejected') ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reason',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                (request.reason != null &&
                                        request.reason!.isNotEmpty)
                                    ? request.reason!
                                    : 'The organizer didn\'t leave a reason.',
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  if (isOpening)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.muted,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.colors.muted,
                      size: 20,
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
