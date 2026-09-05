import 'package:flutter/material.dart';

import '../../services/community_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

/// Star rating plus a written review submission form. Backed by
/// `reviews` — one review per *visit*, so submitting always adds a new
/// review rather than editing a previous one (see
/// [CommunityService.addReview]).
///
/// Only reachable from `PlaceDetailsScreen`/`ReviewDetailsScreen` once
/// they've got an unused visit to spend, but re-checked here too as a
/// safety net in case something ever routes here directly.
class AddReviewScreen extends StatefulWidget {
  const AddReviewScreen({super.key, required this.placeName});

  final String placeName;

  @override
  State<AddReviewScreen> createState() => _AddReviewScreenState();
}

class _AddReviewScreenState extends State<AddReviewScreen> {
  final _service = CommunityService();
  int _rating = 0;
  final _controller = TextEditingController();
  bool _submitting = false;

  /// `null` while the visit/review counts are still loading. `true` once
  /// loaded means there's at least one visit not yet spent on a review —
  /// see [TripService.visitCount] / [CommunityService.myReviewCount].
  bool? _canReview;

  /// Whether the place has ever been visited at all, once loaded — used to
  /// pick between "never visited" and "already reviewed every visit" as
  /// the reason [_canReview] is false.
  bool _everVisited = false;

  @override
  void initState() {
    super.initState();
    Future.wait([
      TripService().visitCount(widget.placeName),
      _service.myReviewCount(widget.placeName),
    ]).then((results) {
      if (!mounted) return;
      final visits = results[0];
      final reviewsSoFar = results[1];
      setState(() {
        _everVisited = visits > 0;
        _canReview = visits > reviewsSoFar;
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _rating > 0 && _controller.text.trim().isNotEmpty && !_submitting;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      await _service.addReview(
        placeName: widget.placeName,
        rating: _rating,
        body: _controller.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.ink,
          content: Text('Review for ${widget.placeName} posted!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.ink,
          content: Text('Could not post review: $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_canReview != true) {
      return Scaffold(
        backgroundColor: context.colors.surface,
        body: SafeArea(
          child: Column(
            children: [
              DetailHeader(title: 'Write a Review', subtitle: widget.placeName),
              Expanded(
                child: _canReview == null
                    ? const Center(child: CircularProgressIndicator())
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.flight_takeoff_rounded,
                                color: context.colors.muted,
                                size: 40,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _everVisited
                                    ? "You've already reviewed "
                                          '${widget.placeName}'
                                    : "You haven't visited "
                                          '${widget.placeName} yet',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: context.colors.ink,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _everVisited
                                    ? 'Visit it again on another trip to '
                                          'write another review.'
                                    : 'You can review a destination once '
                                          "you've visited it on a trip "
                                          "that's finished.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Write a Review', subtitle: widget.placeName),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    'Your rating',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < _rating;
                      return IconButton(
                        onPressed: () => setState(() => _rating = i + 1),
                        icon: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: const Color(0xFFFFB347),
                          size: 36,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Your review',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    maxLines: 6,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(color: context.colors.ink),
                    decoration: InputDecoration(
                      hintText: 'Share details of your experience…',
                      hintStyle: TextStyle(color: context.colors.muted),
                      filled: true,
                      fillColor: context.colors.card,
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: context.colors.ink,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  GradientButton(
                    label: _submitting ? 'Posting…' : 'Post Review',
                    onPressed: _canSubmit ? _submit : () {},
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
