import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/community_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/camera_support.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'crop_image_screen.dart';

/// Image formats [CropImageScreen] (behind `crop_your_image`) can decode —
/// same allow-list `AddPostScreen` uses. A camera capture is always a JPEG,
/// so it's always croppable; a gallery pick only skips the crop step for a
/// format outside this list (e.g. HEIC, which Flutter can't preview either
/// without a platform-specific codec).
const _croppableExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

/// Where a review photo came from — offered as a chooser sheet on mobile,
/// where a camera exists; desktop/web skip straight to gallery since
/// `image_picker` has no camera implementation there.
enum _PhotoSource { camera, gallery }

/// Star rating plus a written review submission form. Backed by
/// `reviews` — one review per *visit*, so submitting always adds a new
/// review rather than editing a previous one (see
/// [CommunityService.addReview]).
///
/// Only reachable from `ReviewDetailsScreen` once the user has got an
/// unused visit to spend, but re-checked here too as a safety net in case
/// something ever routes here directly. (The old `PlaceDetailsScreen` also
/// linked here before it was replaced by `ExplorePlaceDetailsScreen`, which
/// doesn't wire up reviews yet — see that class's doc comment.)
class AddReviewScreen extends StatefulWidget {
  const AddReviewScreen({super.key, required this.placeName});

  final String placeName;

  @override
  State<AddReviewScreen> createState() => _AddReviewScreenState();
}

class _AddReviewScreenState extends State<AddReviewScreen> {
  static const _minReviewLength = 10;
  static const _maxPhotos = 5;

  final _service = CommunityService();
  int _rating = 0;
  final _controller = TextEditingController();
  bool _submitting = false;

  final List<Uint8List> _photoBytes = [];
  final List<String> _photoExtensions = [];
  bool _pickingPhotos = false;
  String? _photoError;

  /// Set once the user has tried to submit at least once, so validation
  /// errors don't show up before they've interacted with the form.
  bool _showErrors = false;

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

  String? get _ratingError =>
      _rating > 0 ? null : 'Select a star rating before posting.';

  String? get _reviewError {
    final text = _controller.text.trim();
    if (text.isEmpty) return 'Write a few words about your experience.';
    if (text.length < _minReviewLength) {
      return 'Write at least $_minReviewLength characters.';
    }
    return null;
  }

  bool get _canSubmit =>
      _ratingError == null && _reviewError == null && !_submitting;

  /// Adds one review photo: picks a source (camera vs. gallery, or straight
  /// to gallery where there's no camera to offer), then routes the result
  /// through [CropImageScreen] before appending it — unlike the old
  /// multi-select picker, this only ever adds one photo per call so each
  /// one gets its own crop pass.
  Future<void> _addPhoto() async {
    if (_photoBytes.length >= _maxPhotos) return;

    final source = cameraAvailable
        ? await showModalBottomSheet<_PhotoSource>(
            context: context,
            backgroundColor: context.colors.card,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => const _PhotoSourceSheet(),
          )
        : _PhotoSource.gallery;
    if (source == null || !mounted) return;

    setState(() {
      _pickingPhotos = true;
      _photoError = null;
    });
    try {
      Uint8List bytes;
      String extension;
      if (source == _PhotoSource.camera) {
        final shot = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 90,
        );
        if (shot == null) return;
        bytes = await shot.readAsBytes();
        extension = 'jpg';
      } else {
        final file = await FilePicker.pickFile(type: FileType.image);
        if (file == null) return;
        bytes = await file.readAsBytes();
        extension = (file.extension ?? 'jpg').toLowerCase();
      }
      if (!mounted) return;

      var finalBytes = bytes;
      var finalExtension = extension;
      if (_croppableExtensions.contains(extension)) {
        final cropped = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(builder: (_) => CropImageScreen(imageBytes: bytes)),
        );
        if (!mounted) return;
        if (cropped != null) {
          finalBytes = cropped;
          finalExtension = 'jpg';
        }
      }

      setState(() {
        _photoBytes.add(finalBytes);
        _photoExtensions.add(finalExtension);
      });
    } catch (e) {
      if (mounted) setState(() => _photoError = 'Could not add photo: $e');
    } finally {
      if (mounted) setState(() => _pickingPhotos = false);
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photoBytes.removeAt(index);
      _photoExtensions.removeAt(index);
      _photoError = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      await _service.addReview(
        placeName: widget.placeName,
        rating: _rating,
        body: _controller.text.trim(),
        photos: [
          for (var i = 0; i < _photoBytes.length; i++)
            (_photoBytes[i], _photoExtensions[i]),
        ],
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
                  if (_showErrors && _ratingError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _ratingError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                      errorText: _showErrors ? _reviewError : null,
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
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.redAccent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Photos (optional)',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _PhotoPicker(
                    photos: _photoBytes,
                    picking: _pickingPhotos,
                    canAddMore: _photoBytes.length < _maxPhotos,
                    onPick: _addPhoto,
                    onRemove: _removePhoto,
                  ),
                  if (_photoError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _photoError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  GradientButton(
                    label: _submitting ? 'Posting…' : 'Post Review',
                    onPressed: _submit,
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

/// Horizontal row of picked-photo thumbnails (each removable) plus a
/// trailing "add" tile, for [AddReviewScreen]'s optional photo attachments.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.photos,
    required this.picking,
    required this.canAddMore,
    required this.onPick,
    required this.onRemove,
  });

  final List<Uint8List> photos;
  final bool picking;
  final bool canAddMore;
  final VoidCallback onPick;
  final ValueChanged<int> onRemove;

  static const _size = 84.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < photos.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    SizedBox(
                      width: _size,
                      height: _size,
                      child: Image.memory(photos[i], fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (canAddMore)
            GestureDetector(
              onTap: picking ? null : onPick,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: context.colors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: context.colors.muted.withValues(alpha: 0.25),
                  ),
                ),
                alignment: Alignment.center,
                child: picking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.add_photo_alternate_outlined,
                        color: context.colors.muted,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet offering "Take Photo" / "Choose from Gallery", shown before
/// [_AddReviewScreenState._addPhoto] opens either the camera or the file
/// picker.
class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Icon(Icons.photo_camera_rounded, color: context.colors.ink),
            title: Text(
              'Take Photo',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => Navigator.of(context).pop(_PhotoSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.photo_library_rounded, color: context.colors.ink),
            title: Text(
              'Choose from Gallery',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => Navigator.of(context).pop(_PhotoSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
