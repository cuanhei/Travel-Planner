import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/countries.dart';
import '../../models/profile_avatar_state.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/avatar_preview.dart';
import '../../widgets/country_code_picker.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/user_avatar.dart';
import 'avatar_creator_screen.dart';

const _maxAvatarBytes = 5 * 1024 * 1024;
const _allowedAvatarExtensions = {'jpg', 'jpeg', 'png', 'webp'};

/// Profile editor for name, phone, and bio (backed by `public.profiles`),
/// plus a profile-photo uploader (click or drag-and-drop) backed by
/// Supabase Storage. Email is read-only here — it's the login credential,
/// changing it needs its own confirmation flow.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _nameController = TextEditingController(text: _initialProfile?.fullName ?? '');
  late final TextEditingController _phoneController;
  late final _bioController = TextEditingController(text: _initialProfile?.bio ?? '');
  late final String _email = _initialProfile?.email ?? '';
  late Country _selectedCountry;

  UserProfile? get _initialProfile => ProfileService.instance.current.value;

  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _dragHover = false;
  late bool _avatarMode =
      ProfileAvatarState.decode(_initialProfile?.avatarUrl).mode == ProfileAvatarMode.avatarDesign;

  @override
  void initState() {
    super.initState();
    final (country, localNumber) = _splitPhone(_initialProfile?.phone);
    _selectedCountry = country;
    _phoneController = TextEditingController(text: localNumber);
  }

  /// Splits a stored phone like "+60 12-345 6789" into its country (matched
  /// by dial code) and the remaining local number, so the picker and text
  /// field can be repopulated separately. Defaults to Malaysia when there's
  /// no stored phone yet or its dial code isn't recognized.
  (Country, String) _splitPhone(String? stored) {
    final value = stored?.trim() ?? '';
    if (value.isEmpty) return (countries.first, '');
    final byLongestCode = [...countries]
      ..sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    for (final country in byLongestCode) {
      if (value.startsWith(country.dialCode)) {
        return (country, value.substring(country.dialCode.length).trim());
      }
    }
    return (countries.first, value);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = Validators.name(_nameController.text);
    if (nameError != null) {
      _showMessage(nameError);
      return;
    }
    final phoneError = Validators.phone(_phoneController.text);
    if (phoneError != null) {
      _showMessage(phoneError);
      return;
    }

    final localNumber = _phoneController.text.trim();
    final fullPhone = localNumber.isEmpty
        ? null
        : '${_selectedCountry.dialCode} $localNumber';

    setState(() => _saving = true);
    try {
      await ProfileService.instance.updateProfile(
        fullName: _nameController.text.trim(),
        phone: fullPhone,
        bio: _bioController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.ink,
          content: Text(tr('auth_profile_updated')),
        ),
      );
    } catch (e) {
      debugPrint('Profile update failed: $e');
      _showMessage(tr('common_error_generic'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await _uploadFile(file);
  }

  Future<void> _uploadFile(XFile file) async {
    final ext = _extensionOf(file.name);
    if (!_allowedAvatarExtensions.contains(ext)) {
      _showMessage(tr('auth_choose_jpg_png_webp'));
      return;
    }

    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      _showMessage(tr('auth_could_not_read_file'));
      return;
    }
    if (bytes.lengthInBytes > _maxAvatarBytes) {
      _showMessage(tr('auth_image_too_large'));
      return;
    }

    setState(() => _uploadingAvatar = true);
    try {
      await ProfileService.instance.uploadAvatar(
        bytes,
        ext == 'jpeg' ? 'jpg' : ext,
      );
    } catch (e) {
      debugPrint('Avatar upload failed: $e');
      if (mounted) _showMessage(tr('auth_upload_failed'));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  String _extensionOf(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot == -1 ? '' : filename.substring(dot + 1).toLowerCase();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('auth_edit_profile_title'),
              subtitle: tr('auth_edit_profile_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Center(
                    child: Column(
                      children: [
                        _PhotoAvatarToggle(
                          isAvatar: _avatarMode,
                          onChanged: (v) => setState(() => _avatarMode = v),
                        ),
                        const SizedBox(height: 16),
                        if (_avatarMode)
                          _AvatarModePanel(
                            onDesign: () async {
                              final current = ProfileAvatarState.decode(
                                ProfileService.instance.current.value?.avatarUrl,
                              ).design;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AvatarCreatorScreen(initialConfig: current),
                                ),
                              );
                            },
                          )
                        else
                          _AvatarPicker(
                            onTap: _pickImage,
                            onFileDropped: _uploadFile,
                            uploading: _uploadingAvatar,
                            dragHover: _dragHover,
                            onDragHoverChanged: (v) => setState(() => _dragHover = v),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!_avatarMode)
                    Text(
                      tr('auth_change_photo_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.muted, fontSize: 12),
                    ),
                  const SizedBox(height: 28),
                  _FieldLabel(tr('auth_full_name')),
                  _InputBox(
                    controller: _nameController,
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_email')),
                  _InputBox(
                    controller: TextEditingController(text: _email),
                    icon: Icons.email_outlined,
                    readOnly: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      tr('auth_email_locked_note'),
                      style: TextStyle(color: context.colors.muted, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_phone')),
                  _InputBox(
                    controller: _phoneController,
                    prefix: Padding(
                      padding: const EdgeInsets.only(left: 14, right: 8),
                      child: CountryCodePicker(
                        selected: _selectedCountry,
                        onChanged: (c) => setState(() => _selectedCountry = c),
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_bio')),
                  _InputBox(
                    controller: _bioController,
                    icon: Icons.notes_rounded,
                    maxLines: 3,
                    maxLength: 160,
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: tr('auth_save_changes'),
                    icon: Icons.check_rounded,
                    onPressed: _save,
                    loading: _saving,
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

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.onTap,
    required this.onFileDropped,
    required this.uploading,
    required this.dragHover,
    required this.onDragHoverChanged,
  });

  final VoidCallback onTap;
  final ValueChanged<XFile> onFileDropped;
  final bool uploading;
  final bool dragHover;
  final ValueChanged<bool> onDragHoverChanged;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => onDragHoverChanged(true),
      onDragExited: (_) => onDragHoverChanged(false),
      onDragDone: (details) {
        onDragHoverChanged(false);
        if (details.files.isNotEmpty) onFileDropped(details.files.first);
      },
      child: GestureDetector(
        onTap: uploading ? null : onTap,
        child: ValueListenableBuilder<UserProfile?>(
          valueListenable: ProfileService.instance.current,
          builder: (context, profile, _) {
            return Stack(
              children: [
                Container(
                  padding: EdgeInsets.all(dragHover ? 3 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: dragHover
                        ? Border.all(color: AppColors.accent, width: 2)
                        : null,
                  ),
                  child: UserAvatar(
                    name: profile?.fullName ?? '',
                    avatarUrl: ProfileAvatarState.decode(profile?.avatarUrl).photoUrl,
                    size: 84,
                    borderWidth: 3,
                  ),
                ),
                if (uploading)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Material(
                    color: context.colors.ink,
                    shape: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
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
    this.icon,
    this.prefix,
    this.keyboardType,
    this.maxLines = 1,
    this.maxLength,
    this.readOnly = false,
  });

  final TextEditingController controller;
  final IconData? icon;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      readOnly: readOnly,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: readOnly ? context.colors.muted : context.colors.ink,
      ),
      decoration: InputDecoration(
        prefixIcon: prefix ??
            (maxLines == 1 && icon != null
                ? Icon(icon, color: context.colors.muted, size: 20)
                : null),
        suffixIcon: readOnly
            ? Icon(Icons.lock_outline_rounded, color: context.colors.muted, size: 18)
            : null,
        filled: true,
        fillColor: readOnly
            ? context.colors.surface
            : context.colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.colors.ink, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }
}

class _PhotoAvatarToggle extends StatelessWidget {
  const _PhotoAvatarToggle({required this.isAvatar, required this.onChanged});

  final bool isAvatar;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      width: 220,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _seg(
              context,
              tr('auth_change_photo_photo_tab'),
              Icons.photo_camera_outlined,
              !isAvatar,
              () => onChanged(false),
            ),
          ),
          Expanded(
            child: _seg(
              context,
              tr('auth_change_photo_avatar_tab'),
              Icons.face_outlined,
              isAvatar,
              () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seg(BuildContext context, String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: active ? context.colors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: active ? Colors.white : context.colors.muted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: active ? Colors.white : context.colors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarModePanel extends StatelessWidget {
  const _AvatarModePanel({required this.onDesign});

  final VoidCallback onDesign;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UserProfile?>(
      valueListenable: ProfileService.instance.current,
      builder: (context, profile, _) {
        final config = ProfileAvatarState.decode(profile?.avatarUrl).design;
        return Column(
          children: [
            Container(
              width: 140,
              height: 160,
              decoration: BoxDecoration(
                color: context.colors.card,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.ink.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: config != null
                  ? AvatarPreview(config: config, width: 120, height: 150)
                  : Icon(Icons.face_outlined, size: 48, color: context.colors.muted),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onDesign,
              icon: const Icon(Icons.brush_rounded, size: 18),
              label: Text(config != null ? tr('avatar_edit_button') : tr('avatar_design_button')),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }
}
