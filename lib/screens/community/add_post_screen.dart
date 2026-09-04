import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/camera_support.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show categories;
import 'crop_image_screen.dart';
import 'post_card.dart' show communityGradients;

/// Accepted formats for a post's photo/video attachment. [FileType.media]
/// already restricts the native picker to images/videos, but that filter
/// isn't guaranteed on every platform, so the extension is checked again
/// against these explicit allow-lists before a pick is accepted.
const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif'};
const _videoExtensions = {'mp4', 'mov', 'webm', 'm4v', 'avi', 'mkv', '3gp'};

/// Image formats the `image` package (behind `crop_your_image`) can decode.
/// HEIC/HEIF are accepted for posting but skip the crop step — Flutter
/// itself can't preview them either without a platform-specific codec.
const _croppableExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

/// Where a post's media came from — offered as a chooser sheet on mobile
/// (camera photo, camera video, or gallery); desktop/web skip straight to
/// gallery since `image_picker` has no camera implementation there.
enum _MediaSource { camera, cameraVideo, gallery }

/// One picked file, normalized to bytes regardless of which of the three
/// [_MediaSource]s it came from.
typedef _PickedMedia = ({
  Uint8List bytes,
  String extension,
  String fileName,
  bool isVideo,
});

/// "New post" composer for the Community feed — caption, location, and a
/// category (sets the icon), with a live preview of the resulting post
/// card. Posts to `posts` on submit; a post with no photo/video falls back
/// to a gradient cover (see [communityGradients]).
class AddPostScreen extends StatefulWidget {
  const AddPostScreen({super.key});

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  final _service = CommunityService();
  final _captionController = TextEditingController();
  final _placeController = TextEditingController();
  int _categoryIndex = 0;
  final _gradientIndex = 0;
  bool _posting = false;

  late final _gradientKeys = communityGradients.keys.toList();

  Map<String, dynamic>? _myProfile;

  Uint8List? _mediaBytes;
  String? _mediaExtension;
  String? _mediaType;
  String? _mediaFileName;
  bool _pickingMedia = false;
  String? _mediaError;

  /// Picks a source (camera photo/video, or gallery — or straight to
  /// gallery where there's no camera to offer), normalizes whatever comes
  /// back to bytes via [_captureFromCamera]/[_pickFromGallery], then routes
  /// a croppable image through [CropImageScreen] before storing it.
  Future<void> _pickMedia() async {
    final source = cameraAvailable
        ? await showModalBottomSheet<_MediaSource>(
            context: context,
            backgroundColor: context.colors.card,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            builder: (_) => const _MediaSourceSheet(),
          )
        : _MediaSource.gallery;
    if (source == null || !mounted) return;

    setState(() {
      _pickingMedia = true;
      _mediaError = null;
    });
    try {
      final picked = switch (source) {
        _MediaSource.camera => await _captureFromCamera(isVideo: false),
        _MediaSource.cameraVideo => await _captureFromCamera(isVideo: true),
        _MediaSource.gallery => await _pickFromGallery(),
      };
      if (picked == null || !mounted) return;

      if (!picked.isVideo && _croppableExtensions.contains(picked.extension)) {
        final cropped = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(
            builder: (_) => CropImageScreen(imageBytes: picked.bytes),
          ),
        );
        if (!mounted) return;
        setState(() {
          _mediaBytes = cropped ?? picked.bytes;
          _mediaExtension = cropped != null ? 'jpg' : picked.extension;
          _mediaType = 'image';
          _mediaFileName = picked.fileName;
        });
      } else {
        setState(() {
          _mediaBytes = picked.bytes;
          _mediaExtension = picked.extension;
          _mediaType = picked.isVideo ? 'video' : 'image';
          _mediaFileName = picked.fileName;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _mediaError = 'Could not add media: $e');
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  /// Camera capture via `image_picker` — a photo (always JPEG) or a video,
  /// per [isVideo].
  Future<_PickedMedia?> _captureFromCamera({required bool isVideo}) async {
    final picker = ImagePicker();
    if (isVideo) {
      final clip = await picker.pickVideo(source: ImageSource.camera);
      if (clip == null) return null;
      final ext = clip.path.split('.').last.toLowerCase();
      return (
        bytes: await clip.readAsBytes(),
        extension: _videoExtensions.contains(ext) ? ext : 'mp4',
        fileName: clip.name,
        isVideo: true,
      );
    }
    final shot = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (shot == null) return null;
    return (
      bytes: await shot.readAsBytes(),
      extension: 'jpg',
      fileName: shot.name,
      isVideo: false,
    );
  }

  /// Gallery pick via `file_picker` — the original single-picker flow, now
  /// just one of [_MediaSource]'s options rather than the only one.
  Future<_PickedMedia?> _pickFromGallery() async {
    final file = await FilePicker.pickFile(type: FileType.media);
    if (file == null) return null;

    final extension = (file.extension ?? '').toLowerCase();
    final isImage = _imageExtensions.contains(extension);
    final isVideo = _videoExtensions.contains(extension);
    if (!isImage && !isVideo) {
      setState(() {
        _mediaError =
            'Unsupported file — use a photo (JPG, PNG, GIF, WEBP, HEIC) '
            'or a video (MP4, MOV, WEBM, M4V, AVI, MKV, 3GP).';
      });
      return null;
    }

    return (
      bytes: await file.readAsBytes(),
      extension: extension,
      fileName: file.name,
      isVideo: isVideo,
    );
  }

  Future<void> _recropMedia() async {
    final bytes = _mediaBytes;
    if (bytes == null) return;
    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CropImageScreen(imageBytes: bytes)),
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _mediaBytes = cropped;
      _mediaExtension = 'jpg';
    });
  }

  void _removeMedia() {
    setState(() {
      _mediaBytes = null;
      _mediaExtension = null;
      _mediaType = null;
      _mediaFileName = null;
      _mediaError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _service.getMyProfile().then((profile) {
      if (mounted) setState(() => _myProfile = profile);
    });
  }

  @override
  void dispose() {
    _captionController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  bool _showErrors = false;

  String? get _placeError => _placeController.text.trim().isEmpty
      ? 'Tell us where this was'
      : null;

  String? get _captionError => _captionController.text.trim().isEmpty
      ? 'Add a caption for your post'
      : null;

  bool get _canPost =>
      !_posting && _placeError == null && _captionError == null;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    if (!_canPost) return;
    setState(() => _posting = true);
    try {
      await _service.addPost(
        placeName: _placeController.text.trim(),
        caption: _captionController.text.trim(),
        category: categories[_categoryIndex].label,
        coverGradient: _gradientKeys[_gradientIndex],
        mediaBytes: _mediaBytes,
        mediaExtension: _mediaExtension,
        mediaType: _mediaType,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: context.colors.ink,
            content: Text('Could not post: $e'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myName = _myProfile?['display_name'] as String? ?? 'You';
    final myColor = _myProfile?['avatar_color'] != null
        ? Color(_myProfile!['avatar_color'] as int)
        : AppColors.accent;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'New Post',
              subtitle: 'Share a travel moment',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: myColor,
                        child: Text(
                          myName.isNotEmpty ? myName[0].toUpperCase() : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Posting as $myName',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel('Where was this?'),
                  _InputBox(
                    controller: _placeController,
                    icon: Icons.location_on_rounded,
                    hint: 'e.g. Chew Jetty, George Town',
                    errorText: _showErrors ? _placeError : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  _FieldLabel('Caption'),
                  _InputBox(
                    controller: _captionController,
                    icon: Icons.edit_rounded,
                    hint: 'Share your experience…',
                    maxLines: 5,
                    errorText: _showErrors ? _captionError : null,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel('Photo or video'),
                  _MediaPicker(
                    bytes: _mediaBytes,
                    mediaType: _mediaType,
                    fileName: _mediaFileName,
                    loading: _pickingMedia,
                    errorText: _mediaError,
                    onPick: _pickMedia,
                    onRemove: _removeMedia,
                    onRecrop: _mediaType == 'image' ? _recropMedia : null,
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel('Category'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: List.generate(categories.length, (i) {
                      final c = categories[i];
                      final selected = _categoryIndex == i;
                      return GestureDetector(
                        onTap: () => setState(() => _categoryIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.colors.ink
                                : context.colors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? context.colors.ink
                                  : context.colors.muted.withValues(
                                      alpha: 0.25,
                                    ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                c.icon,
                                size: 14,
                                color: selected
                                    ? Colors.white
                                    : context.colors.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                c.label,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : context.colors.ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),
                  _FieldLabel('Preview'),
                  const SizedBox(height: 8),
                  _PostPreview(
                    authorName: myName,
                    authorColor: myColor,
                    caption: _captionController.text.trim().isEmpty
                        ? 'Your caption will appear here…'
                        : _captionController.text.trim(),
                    place: _placeController.text.trim().isEmpty
                        ? 'Location'
                        : _placeController.text.trim(),
                    mediaBytes: _mediaBytes,
                    mediaType: _mediaType,
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: _posting ? 'Posting…' : 'Post',
                    icon: Icons.send_rounded,
                    onPressed: _posting ? () {} : _submit,
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

class _PostPreview extends StatelessWidget {
  const _PostPreview({
    required this.authorName,
    required this.authorColor,
    required this.caption,
    required this.place,
    this.mediaBytes,
    this.mediaType,
  });

  final String authorName;
  final Color authorColor;
  final String caption;
  final String place;
  final Uint8List? mediaBytes;
  final String? mediaType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: authorColor,
                child: Text(
                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      '$place · Just now',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            caption,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          if (mediaBytes != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              // Video stays a fixed-height icon card (no real frame to
              // size to here); a photo shows at its own aspect ratio
              // scaled to width, matching what was actually cropped
              // instead of being cover-cropped again into a fixed box.
              child: mediaType == 'video'
                  ? Container(
                      height: 100,
                      width: double.infinity,
                      color: Colors.black87,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white70,
                        size: 32,
                      ),
                    )
                  : Image.memory(
                      mediaBytes!,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tap-to-pick box for a post's optional photo/video attachment. Shows a
/// dashed-style placeholder when empty, a preview (image) or filename card
/// (video — no live decode here, just confirmation of what was picked) with
/// a remove button once something's selected.
class _MediaPicker extends StatelessWidget {
  const _MediaPicker({
    required this.bytes,
    required this.mediaType,
    required this.fileName,
    required this.loading,
    required this.errorText,
    required this.onPick,
    required this.onRemove,
    this.onRecrop,
  });

  final Uint8List? bytes;
  final String? mediaType;
  final String? fileName;
  final bool loading;
  final String? errorText;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  final VoidCallback? onRecrop;

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;
    final picker = bytes == null
        ? GestureDetector(
            onTap: loading ? null : onPick,
            child: Container(
              height: 90,
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasError
                      ? const Color(0xFFE0554B)
                      : context.colors.muted.withValues(alpha: 0.25),
                ),
              ),
              alignment: Alignment.center,
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_photo_alternate_outlined,
                          color: context.colors.muted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add a photo or video',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Video stays a fixed-height filename card (no real frame
                // to size to here); a photo shows at its own aspect ratio
                // scaled to width — whatever came out of the crop step,
                // not cover-cropped again into a fixed box.
                mediaType == 'video'
                    ? Container(
                        height: 140,
                        width: double.infinity,
                        color: Colors.black87,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.movie_creation_outlined,
                              color: Colors.white70,
                              size: 28,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              fileName ?? 'Video selected',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      )
                    : Image.memory(
                        bytes!,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                      ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      if (onRecrop != null) ...[
                        GestureDetector(
                          onTap: onRecrop,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.crop_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      GestureDetector(
                        onTap: onRemove,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

    if (!hasError) return picker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        picker,
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            errorText!,
            style: const TextStyle(
              color: Color(0xFFE0554B),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.controller,
    required this.icon,
    required this.hint,
    this.maxLines = 1,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final int maxLines;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    const errorColor = Color(0xFFE0554B);
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        prefixIcon: maxLines == 1
            ? Icon(icon, color: context.colors.muted, size: 20)
            : null,
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.muted),
        errorText: errorText,
        errorStyle: const TextStyle(
          color: errorColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: context.colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: errorText != null
              ? const BorderSide(color: errorColor, width: 1.5)
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: errorText != null ? errorColor : context.colors.ink,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: errorColor, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }
}

/// Bottom sheet offering "Take Photo" / "Record Video" / "Choose from
/// Gallery", shown before [_AddPostScreenState._pickMedia] opens the
/// camera or the file picker.
class _MediaSourceSheet extends StatelessWidget {
  const _MediaSourceSheet();

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
            onTap: () => Navigator.of(context).pop(_MediaSource.camera),
          ),
          ListTile(
            leading: Icon(Icons.videocam_rounded, color: context.colors.ink),
            title: Text(
              'Record Video',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () => Navigator.of(context).pop(_MediaSource.cameraVideo),
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
            onTap: () => Navigator.of(context).pop(_MediaSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
