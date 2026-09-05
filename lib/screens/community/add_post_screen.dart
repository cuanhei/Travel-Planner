import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/community_post.dart';
import '../../services/community_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/camera_support.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/user_avatar.dart';
import '../explore/explore_tab.dart' show categories;
import 'crop_image_screen.dart';
import 'post_card.dart' show communityGradients;

const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'heif'};
const _videoExtensions = {'mp4', 'mov', 'webm', 'm4v', 'avi', 'mkv', '3gp'};

const _croppableExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp'};

enum _MediaSource { camera, cameraVideo, gallery }

typedef _PickedMedia = ({
  Uint8List bytes,
  String extension,
  String fileName,
  bool isVideo,
});

class AddPostScreen extends StatefulWidget {
  const AddPostScreen({super.key, this.existingPost});

  final CommunityPost? existingPost;

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  static const _maxMedia = CommunityService.maxPostMedia;

  final _service = CommunityService();
  final _captionController = TextEditingController();
  final _placeController = TextEditingController();
  int _categoryIndex = 0;
  final _gradientIndex = 0;
  bool _posting = false;

  bool get _isEditing => widget.existingPost != null;

  bool get _hasUnsavedChanges {
    final existing = widget.existingPost;
    if (existing == null) {
      return _placeController.text.trim().isNotEmpty ||
          _captionController.text.trim().isNotEmpty ||
          _mediaBytesList.isNotEmpty;
    }
    return _placeController.text.trim() != existing.placeName ||
        _captionController.text.trim() != existing.caption ||
        categories[_categoryIndex].label != existing.category ||
        _mediaBytesList.isNotEmpty ||
        !_sameMedia(_existingMedia, existing.media);
  }

  bool _sameMedia(List<PostMedia> a, List<PostMedia> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].url != b[i].url || a[i].type != b[i].type) return false;
    }
    return true;
  }

  Future<bool> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Discard changes?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          _isEditing
              ? "Your edits to this post haven't been saved."
              : "Your post hasn't been saved.",
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  late final _gradientKeys = communityGradients.keys.toList();

  Map<String, dynamic>? _myProfile;

  final List<Uint8List> _mediaBytesList = [];
  final List<String> _mediaExtensions = [];
  final List<String> _mediaTypes = [];
  final List<String> _mediaFileNames = [];
  bool _pickingMedia = false;
  String? _mediaError;

  late final List<PostMedia> _existingMedia = List.of(
    widget.existingPost?.media ?? const [],
  );

  int get _totalMediaCount => _existingMedia.length + _mediaBytesList.length;

  Future<void> _pickMedia() async {
    if (_totalMediaCount >= _maxMedia) return;

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
          _mediaBytesList.add(cropped ?? picked.bytes);
          _mediaExtensions.add(cropped != null ? 'jpg' : picked.extension);
          _mediaTypes.add('image');
          _mediaFileNames.add(picked.fileName);
        });
      } else {
        setState(() {
          _mediaBytesList.add(picked.bytes);
          _mediaExtensions.add(picked.extension);
          _mediaTypes.add(picked.isVideo ? 'video' : 'image');
          _mediaFileNames.add(picked.fileName);
        });
      }
    } catch (e) {
      if (mounted) setState(() => _mediaError = 'Could not add media: $e');
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

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

  void _removeMedia(int index) {
    setState(() {
      _mediaBytesList.removeAt(index);
      _mediaExtensions.removeAt(index);
      _mediaTypes.removeAt(index);
      _mediaFileNames.removeAt(index);
      _mediaError = null;
    });
  }

  void _removeExistingMedia(int index) {
    setState(() {
      _existingMedia.removeAt(index);
      _mediaError = null;
    });
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existingPost;
    if (existing != null) {
      _placeController.text = existing.placeName;
      _captionController.text = existing.caption;
      _categoryIndex = categories.indexWhere(
        (c) => c.label == existing.category,
      );
      if (_categoryIndex == -1) _categoryIndex = 0;
    }
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

  String? get _placeError =>
      _placeController.text.trim().isEmpty ? 'Tell us where this was' : null;

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
      final newMedia = [
        for (var i = 0; i < _mediaBytesList.length; i++)
          (_mediaBytesList[i], _mediaExtensions[i], _mediaTypes[i]),
      ];
      if (_isEditing) {
        await _service.updatePost(
          postId: widget.existingPost!.id,
          placeName: _placeController.text.trim(),
          caption: _captionController.text.trim(),
          category: categories[_categoryIndex].label,
          keepMedia: _existingMedia,
          newMedia: newMedia,
        );
      } else {
        await _service.addPost(
          placeName: _placeController.text.trim(),
          caption: _captionController.text.trim(),
          category: categories[_categoryIndex].label,
          coverGradient: _gradientKeys[_gradientIndex],
          media: newMedia,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: context.colors.ink,
            content: Text(
              _isEditing ? 'Could not save: $e' : 'Could not post: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myName = _myProfile?['display_name'] as String? ?? 'You';
    final myAvatarUrl = _myProfile?['avatar_url'] as String?;

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: context.colors.surface,
        body: SafeArea(
          child: Column(
            children: [
              DetailHeader(
                title: _isEditing ? 'Edit Post' : 'New Post',
                subtitle: _isEditing
                    ? 'Update your travel moment'
                    : 'Share a travel moment',
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    Row(
                      children: [
                        UserAvatar(
                          name: myName,
                          avatarUrl: myAvatarUrl,
                          size: 40,
                          borderWidth: 0,
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
                    _FieldLabel('Photos or videos (up to $_maxMedia)'),
                    _MediaPicker(
                      existingMedia: _existingMedia,
                      newBytes: _mediaBytesList,
                      newTypes: _mediaTypes,
                      newFileNames: _mediaFileNames,
                      loading: _pickingMedia,
                      canAddMore: _totalMediaCount < _maxMedia,
                      onPick: _pickMedia,
                      onRemoveExisting: _removeExistingMedia,
                      onRemoveNew: _removeMedia,
                    ),
                    if (_mediaError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _mediaError!,
                        style: const TextStyle(
                          color: Color(0xFFE0554B),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                      authorAvatarUrl: myAvatarUrl,
                      caption: _captionController.text.trim().isEmpty
                          ? 'Your caption will appear here…'
                          : _captionController.text.trim(),
                      place: _placeController.text.trim().isEmpty
                          ? 'Location'
                          : _placeController.text.trim(),
                      existingMedia: _existingMedia,
                      newBytes: _mediaBytesList,
                      newTypes: _mediaTypes,
                    ),
                    const SizedBox(height: 32),
                    GradientButton(
                      label: _posting
                          ? (_isEditing ? 'Saving…' : 'Posting…')
                          : (_isEditing ? 'Save Changes' : 'Post'),
                      icon: Icons.send_rounded,
                      onPressed: _posting ? () {} : _submit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  const _PostPreview({
    required this.authorName,
    this.authorAvatarUrl,
    required this.caption,
    required this.place,
    required this.existingMedia,
    required this.newBytes,
    required this.newTypes,
  });

  final String authorName;
  final String? authorAvatarUrl;
  final String caption;
  final String place;
  final List<PostMedia> existingMedia;
  final List<Uint8List> newBytes;
  final List<String> newTypes;

  @override
  Widget build(BuildContext context) {
    final tileCount = existingMedia.length + newBytes.length;
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
              UserAvatar(
                name: authorName,
                avatarUrl: authorAvatarUrl,
                size: 32,
                borderWidth: 0,
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
          if (tileCount > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tileCount,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final isExisting = i < existingMedia.length;
                  final type = isExisting
                      ? existingMedia[i].type
                      : newTypes[i - existingMedia.length];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: type == 'video'
                        ? Container(
                            width: 90,
                            height: 90,
                            color: Colors.black87,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white70,
                              size: 28,
                            ),
                          )
                        : SizedBox(
                            width: 90,
                            height: 90,
                            child: isExisting
                                ? Image.network(
                                    existingMedia[i].url,
                                    fit: BoxFit.cover,
                                  )
                                : Image.memory(
                                    newBytes[i - existingMedia.length],
                                    fit: BoxFit.cover,
                                  ),
                          ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaPicker extends StatelessWidget {
  const _MediaPicker({
    required this.existingMedia,
    required this.newBytes,
    required this.newTypes,
    required this.newFileNames,
    required this.loading,
    required this.canAddMore,
    required this.onPick,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  final List<PostMedia> existingMedia;
  final List<Uint8List> newBytes;
  final List<String> newTypes;
  final List<String> newFileNames;
  final bool loading;
  final bool canAddMore;
  final VoidCallback onPick;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  static const _size = 84.0;

  Widget _thumb({required Widget child, required VoidCallback onRemove}) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            SizedBox(width: _size, height: _size, child: child),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: onRemove,
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
    );
  }

  Widget _videoTile(String? fileName) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.movie_creation_outlined,
            color: Colors.white70,
            size: 22,
          ),
          if (fileName != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                fileName,
                style: const TextStyle(color: Colors.white70, fontSize: 9),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (var i = 0; i < existingMedia.length; i++)
            _thumb(
              onRemove: () => onRemoveExisting(i),
              child: existingMedia[i].type == 'video'
                  ? _videoTile(null)
                  : Image.network(existingMedia[i].url, fit: BoxFit.cover),
            ),
          for (var i = 0; i < newBytes.length; i++)
            _thumb(
              onRemove: () => onRemoveNew(i),
              child: newTypes[i] == 'video'
                  ? _videoTile(newFileNames[i])
                  : Image.memory(newBytes[i], fit: BoxFit.cover),
            ),
          if (canAddMore)
            GestureDetector(
              onTap: loading ? null : onPick,
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
                child: loading
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
            leading: Icon(
              Icons.photo_camera_rounded,
              color: context.colors.ink,
            ),
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
            leading: Icon(
              Icons.photo_library_rounded,
              color: context.colors.ink,
            ),
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
