import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
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

  Future<void> _pickMedia() async {
    setState(() {
      _pickingMedia = true;
      _mediaError = null;
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.media);
      if (file == null) return;

      final extension = (file.extension ?? '').toLowerCase();
      final isImage = _imageExtensions.contains(extension);
      final isVideo = _videoExtensions.contains(extension);
      if (!isImage && !isVideo) {
        setState(() {
          _mediaError =
              'Unsupported file — use a photo (JPG, PNG, GIF, WEBP, HEIC) '
              'or a video (MP4, MOV, WEBM, M4V, AVI, MKV, 3GP).';
        });
        return;
      }

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      if (isImage && _croppableExtensions.contains(extension)) {
        final cropped = await Navigator.of(context).push<Uint8List>(
          MaterialPageRoute(builder: (_) => CropImageScreen(imageBytes: bytes)),
        );
        if (!mounted) return;
        setState(() {
          _mediaBytes = cropped ?? bytes;
          _mediaExtension = cropped != null ? 'jpg' : extension;
          _mediaType = 'image';
          _mediaFileName = file.name;
        });
      } else {
        setState(() {
          _mediaBytes = bytes;
          _mediaExtension = extension;
          _mediaType = isVideo ? 'video' : 'image';
          _mediaFileName = file.name;
        });
      }
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
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
              child: SizedBox(
                height: 100,
                width: double.infinity,
                child: mediaType == 'video'
                    ? Container(
                        color: Colors.black87,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white70,
                          size: 32,
                        ),
                      )
                    : Image.memory(mediaBytes!, fit: BoxFit.cover),
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
                SizedBox(
                  height: 140,
                  width: double.infinity,
                  child: mediaType == 'video'
                      ? Container(
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
                      : Image.memory(bytes!, fit: BoxFit.cover),
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
