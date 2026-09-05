import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/countries.dart';
import '../../models/profile_avatar_state.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/gender_options.dart';
import '../../utils/validators.dart';
import '../../widgets/avatar_preview.dart';
import '../../widgets/country_code_picker.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/nationality_picker.dart';
import '../../widgets/user_avatar.dart';
import 'avatar_creator_screen.dart';

const _maxAvatarBytes = 5 * 1024 * 1024;
const _allowedAvatarExtensions = {'jpg', 'jpeg', 'png', 'webp'};

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime d) =>
    '${d.day} ${_monthNames[d.month - 1]} ${d.year}';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final _nameController = TextEditingController(
    text: _initialProfile?.fullName ?? '',
  );
  late final TextEditingController _phoneController;
  late final _bioController = TextEditingController(
    text: _initialProfile?.bio ?? '',
  );
  late final _addressController = TextEditingController(
    text: _initialProfile?.address ?? '',
  );
  late final String _email = _initialProfile?.email ?? '';
  late Country _selectedCountry;
  late DateTime? _dateOfBirth = _initialProfile?.dateOfBirth;
  late String? _gender = _initialProfile?.gender;
  late String? _nationality = _initialProfile?.nationality;

  UserProfile? get _initialProfile => ProfileService.instance.current.value;

  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _dragHover = false;
  bool _justAutosaved = false;
  late bool _avatarMode =
      ProfileAvatarState.decode(_initialProfile?.avatarUrl).mode ==
      ProfileAvatarMode.avatarDesign;

  Timer? _autosaveDebounce;
  Timer? _savedBadgeTimer;

  @override
  void initState() {
    super.initState();
    final (country, localNumber) = _splitPhone(_initialProfile?.phone);
    _selectedCountry = country;
    _phoneController = TextEditingController(text: localNumber);
    _nameController.addListener(_scheduleAutosave);
    _phoneController.addListener(_scheduleAutosave);
    _bioController.addListener(_scheduleAutosave);
    _addressController.addListener(_scheduleAutosave);
  }

  void _scheduleAutosave() {
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 900), _autosave);
  }

  Future<void> _autosave() async {
    if (Validators.name(_nameController.text) != null) return;
    if (Validators.phone(_phoneController.text, _selectedCountry) != null)
      return;

    final localNumber = _phoneController.text.trim();
    final fullPhone = localNumber.isEmpty
        ? null
        : '${_selectedCountry.dialCode} $localNumber';
    try {
      await ProfileService.instance.updateProfile(
        fullName: _nameController.text.trim(),
        phone: fullPhone,
        bio: _bioController.text,
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        nationality: _nationality,
        address: _addressController.text,
      );
      if (mounted) _flashSavedBadge();
    } catch (e) {
      debugPrint('Autosave failed: $e');
    }
  }

  void _flashSavedBadge() {
    _savedBadgeTimer?.cancel();
    setState(() => _justAutosaved = true);
    _savedBadgeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _justAutosaved = false);
    });
  }

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
    if (_autosaveDebounce?.isActive ?? false) _autosave();
    _autosaveDebounce?.cancel();
    _savedBadgeTimer?.cancel();
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    _autosaveDebounce?.cancel();
    final nameError = Validators.name(_nameController.text);
    if (nameError != null) {
      _showMessage(nameError);
      return;
    }
    final phoneError = Validators.phone(
      _phoneController.text,
      _selectedCountry,
    );
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
        dateOfBirth: _dateOfBirth,
        gender: _gender,
        nationality: _nationality,
        address: _addressController.text,
      );

      final targetMode = _avatarMode
          ? ProfileAvatarMode.avatarDesign
          : ProfileAvatarMode.photo;
      final savedState = ProfileAvatarState.decode(
        ProfileService.instance.current.value?.avatarUrl,
      );
      final targetHasContent = targetMode == ProfileAvatarMode.avatarDesign
          ? savedState.design != null
          : (savedState.photoUrl?.isNotEmpty ?? false);
      if (targetHasContent) {
        await ProfileService.instance.setActiveAvatarMode(targetMode);
      }

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

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
      _scheduleAutosave();
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
              trailing: AnimatedOpacity(
                opacity: _justAutosaved ? 1 : 0,
                duration: const Duration(milliseconds: 250),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF11998E),
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      tr('auth_saved'),
                      style: TextStyle(
                        color: Color(0xFF11998E),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
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
                                ProfileService
                                    .instance
                                    .current
                                    .value
                                    ?.avatarUrl,
                              ).design;
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AvatarCreatorScreen(
                                    initialConfig: current,
                                  ),
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
                            onDragHoverChanged: (v) =>
                                setState(() => _dragHover = v),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!_avatarMode)
                    Text(
                      tr('auth_change_photo_hint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
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
                    locked: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      tr('auth_email_locked_note'),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
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
                        onChanged: (c) {
                          setState(() => _selectedCountry = c);
                          _scheduleAutosave();
                        },
                      ),
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(
                        _selectedCountry.maxPhoneDigits,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    tr('auth_personal_info_section'),
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FieldLabel(tr('auth_date_of_birth')),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickDateOfBirth,
                    child: AbsorbPointer(
                      child: _InputBox(
                        controller: TextEditingController(
                          text: _dateOfBirth == null
                              ? ''
                              : _formatDate(_dateOfBirth!),
                        ),
                        icon: Icons.cake_outlined,
                        readOnly: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_gender')),
                  _GenderPicker(
                    selected: _gender,
                    onChanged: (g) {
                      setState(() => _gender = g);
                      _scheduleAutosave();
                    },
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_nationality')),
                  NationalityPicker(
                    selected: _nationality,
                    onChanged: (c) {
                      setState(() => _nationality = c.name);
                      _scheduleAutosave();
                    },
                  ),
                  const SizedBox(height: 18),
                  _FieldLabel(tr('auth_address')),
                  _InputBox(
                    controller: _addressController,
                    icon: Icons.home_outlined,
                    maxLines: 2,
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
      child: ValueListenableBuilder<UserProfile?>(
        valueListenable: ProfileService.instance.current,
        builder: (context, profile, _) {
          final photoUrl = ProfileAvatarState.decode(
            profile?.avatarUrl,
          ).photoUrl;
          return Stack(
            children: [
              MouseRegion(
                cursor: uploading
                    ? MouseCursor.defer
                    : SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: uploading ? null : onTap,
                  child: Container(
                    padding: EdgeInsets.all(dragHover ? 3 : 0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: dragHover
                          ? Border.all(color: AppColors.accent, width: 2)
                          : null,
                    ),
                    child: UserAvatar(
                      name: profile?.fullName ?? '',
                      avatarUrl: photoUrl,
                      size: 84,
                      borderWidth: 3,
                    ),
                  ),
                ),
              ),
              if (uploading)
                Positioned.fill(
                  child: IgnorePointer(
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
                ),
            ],
          );
        },
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
    this.locked = false,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final IconData? icon;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final int maxLines;
  final int? maxLength;
  final bool readOnly;
  final List<TextInputFormatter>? inputFormatters;

  final bool locked;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      readOnly: locked || readOnly,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: locked ? context.colors.muted : context.colors.ink,
      ),
      decoration: InputDecoration(
        prefixIcon:
            prefix ??
            (maxLines == 1 && icon != null
                ? Icon(icon, color: context.colors.muted, size: 20)
                : null),
        suffixIcon: Icon(
          locked ? Icons.lock_outline_rounded : Icons.edit_outlined,
          color: context.colors.muted,
          size: locked ? 18 : 16,
        ),
        filled: true,
        fillColor: locked ? context.colors.surface : context.colors.card,
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

class _GenderPicker extends StatelessWidget {
  const _GenderPicker({required this.selected, required this.onChanged});

  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in genderOptions)
          GestureDetector(
            onTap: () => onChanged(option),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected == option
                    ? context.colors.ink
                    : context.colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                genderLabel(option),
                style: TextStyle(
                  color: selected == option ? Colors.white : context.colors.ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
      ],
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

  Widget _seg(
    BuildContext context,
    String label,
    IconData icon,
    bool active,
    VoidCallback onTap,
  ) {
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
            Icon(
              icon,
              size: 15,
              color: active ? Colors.white : context.colors.muted,
            ),
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
                  : Icon(
                      Icons.face_outlined,
                      size: 48,
                      color: context.colors.muted,
                    ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: onDesign,
              icon: const Icon(Icons.brush_rounded, size: 18),
              label: Text(
                config != null
                    ? tr('avatar_edit_button')
                    : tr('avatar_design_button'),
              ),
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
