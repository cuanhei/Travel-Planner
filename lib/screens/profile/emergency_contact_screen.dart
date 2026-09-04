import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';

import '../../data/countries.dart';
import '../../models/emergency_contact.dart';
import '../../services/emergency_contact_service.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/validators.dart';
import '../../widgets/country_code_picker.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/user_avatar.dart';
import 'view_profile_screen.dart';

/// Turns a raw Supabase error into a message worth showing the user.
/// `PGRST205` specifically means the `emergency_contacts` table hasn't
/// been created yet on this project (see
/// `supabase/migrations/0009_create_emergency_contacts.sql`) — everything
/// else falls back to a generic retry message.
String _friendlyError(Object e) {
  if (e is PostgrestException && e.code == 'PGRST205') {
    return tr('auth_emergency_contact_not_setup');
  }
  return tr('common_error_generic');
}

/// The signed-in user's own emergency contacts (family/friends they add
/// themselves) — full CRUD, backed by Supabase. Distinct from the
/// Utilities module's static list of official numbers (police, ambulance,
/// etc.), which stays as-is and isn't editable.
class EmergencyContactScreen extends StatefulWidget {
  const EmergencyContactScreen({super.key});

  @override
  State<EmergencyContactScreen> createState() =>
      _EmergencyContactScreenState();
}

class _EmergencyContactScreenState extends State<EmergencyContactScreen> {
  List<EmergencyContact>? _contacts;
  Map<String, UserProfile> _matchedProfiles = {};
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Re-fetches contacts and, for each one, re-checks whether its phone
  /// number now belongs to a signed-up TravelPlanner account — so a
  /// contact who wasn't a member when added automatically picks up their
  /// live profile photo/name/link the next time this screen loads, with
  /// no need to re-add them.
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final contacts = await EmergencyContactService.instance.list();
      Map<String, UserProfile> matches = {};
      try {
        matches = await ProfileService.instance.findByPhones(
          contacts.map((c) => c.phone).toList(),
        );
      } catch (e) {
        // Fails open: if the matching RPC errors (e.g. its migration
        // hasn't been applied yet), the contact list still shows — just
        // without the "signed-up user" linking for this load.
        debugPrint('findByPhones failed, skipping profile linking: $e');
      }
      if (mounted) {
        setState(() {
          _contacts = contacts;
          _matchedProfiles = matches;
        });
      }
    } catch (e) {
      debugPrint('Failed to load emergency contacts: $e');
      if (mounted) setState(() => _loadError = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({EmergencyContact? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContactFormSheet(existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(EmergencyContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('auth_remove_contact_title')),
        content: Text(
          '${contact.name} ${tr('auth_remove_contact_body_suffix')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('common_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              tr('auth_remove'),
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await EmergencyContactService.instance.delete(contact.id);
      _load();
    } catch (e) {
      debugPrint('Failed to delete emergency contact: $e');
      _showMessage(_friendlyError(e));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
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
              title: tr('auth_emergency_contact'),
              subtitle: tr('auth_emergency_contact_screen_subtitle'),
              trailing: IconButton(
                onPressed: () => _openForm(),
                icon: Icon(Icons.person_add_alt_1_rounded, color: context.colors.ink),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return _ErrorState(message: _loadError!, onRetry: _load);
    }
    final contacts = _contacts ?? [];
    if (contacts.isEmpty) {
      return _EmptyState(onAdd: () => _openForm());
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final contact = contacts[index];
        final matchedProfile = _matchedProfiles[contact.phone];
        return _ContactCard(
          contact: contact,
          matchedProfile: matchedProfile,
          onTap: matchedProfile == null
              ? () => _openForm(existing: contact)
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          ViewProfileScreen(userId: matchedProfile.id),
                    ),
                  ),
          onEdit: matchedProfile == null ? null : () => _openForm(existing: contact),
          onDelete: () => _delete(contact),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: Colors.redAccent,
            ),
            SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.ink, fontSize: 13.5),
            ),
            SizedBox(height: 20),
            TextButton.icon(
              onPressed: onRetry,
              icon: Icon(Icons.refresh_rounded, size: 18),
              label: Text(tr('auth_try_again')),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.contact_phone_outlined,
              size: 56,
              color: context.colors.muted,
            ),
            SizedBox(height: 16),
            Text(
              tr('auth_no_emergency_contacts_yet'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 6),
            Text(
              tr('auth_add_family_friends_hint'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 13),
            ),
            SizedBox(height: 24),
            GradientButton(
              label: tr('auth_add_contact'),
              icon: Icons.person_add_alt_1_rounded,
              onPressed: onAdd,
              expand: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.onTap,
    required this.onDelete,
    this.matchedProfile,
    this.onEdit,
  });

  final EmergencyContact contact;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Set when [contact]'s phone number matches a signed-up TravelPlanner
  /// account — re-checked on every load (see
  /// `_EmergencyContactScreenState._load`), so this appears automatically
  /// once that person signs up, with no need to re-add them. When set,
  /// [onTap] opens their profile ([ViewProfileScreen]) instead of the
  /// edit-contact sheet, so [onEdit] is offered separately.
  final UserProfile? matchedProfile;
  final VoidCallback? onEdit;

  Future<void> _call(BuildContext context) async {
    final launched = await launchUrl(Uri(scheme: 'tel', path: contact.phone));
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            '${tr('auth_could_not_start_call_prefix')} ${contact.phone}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              if (matchedProfile != null)
                UserAvatar(
                  name: matchedProfile!.fullName,
                  avatarUrl: matchedProfile!.avatarUrl,
                  size: 46,
                )
              else
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.person_rounded,
                    color: AppColors.accent,
                    size: 22,
                  ),
                ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            matchedProfile != null &&
                                    matchedProfile!.fullName.isNotEmpty
                                ? matchedProfile!.fullName
                                : contact.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (matchedProfile != null) ...[
                          SizedBox(width: 4),
                          Icon(
                            Icons.verified_rounded,
                            color: AppColors.accent,
                            size: 15,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 3),
                    Text(
                      [
                        if (contact.relationship?.isNotEmpty ?? false)
                          contact.relationship!,
                        contact.phone,
                      ].join(' · '),
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (onEdit != null) ...[
                Material(
                  color: context.colors.ink.withValues(alpha: 0.08),
                  shape: CircleBorder(),
                  child: InkWell(
                    customBorder: CircleBorder(),
                    onTap: onEdit,
                    child: Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.edit_outlined,
                        color: context.colors.ink,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8),
              ],
              Material(
                color: Color(0xFF11998E).withValues(alpha: 0.12),
                shape: CircleBorder(),
                child: InkWell(
                  customBorder: CircleBorder(),
                  onTap: () => _call(context),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.call_rounded,
                      color: Color(0xFF11998E),
                      size: 18,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Material(
                color: Colors.redAccent.withValues(alpha: 0.1),
                shape: CircleBorder(),
                child: InkWell(
                  customBorder: CircleBorder(),
                  onTap: onDelete,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactFormSheet extends StatefulWidget {
  const _ContactFormSheet({this.existing});

  final EmergencyContact? existing;

  @override
  State<_ContactFormSheet> createState() => _ContactFormSheetState();
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

class _ContactFormSheetState extends State<_ContactFormSheet> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _relationshipController = TextEditingController(
    text: widget.existing?.relationship ?? '',
  );
  late final TextEditingController _phoneController;
  late Country _selectedCountry;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final (country, localNumber) = _splitPhone(widget.existing?.phone);
    _selectedCountry = country;
    _phoneController = TextEditingController(text: localNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _relationshipController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final nameError = Validators.name(_nameController.text);
    if (nameError != null) {
      _showMessage(nameError);
      return;
    }
    final localNumber = _phoneController.text.trim();
    if (localNumber.isEmpty) {
      _showMessage(tr('auth_enter_phone_number'));
      return;
    }
    final phoneError = Validators.phone(localNumber, _selectedCountry);
    if (phoneError != null) {
      _showMessage(phoneError);
      return;
    }
    final phone = '${_selectedCountry.dialCode} $localNumber';

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await EmergencyContactService.instance.update(
          id: widget.existing!.id,
          name: _nameController.text.trim(),
          phone: phone,
          relationship: _relationshipController.text,
        );
      } else {
        await EmergencyContactService.instance.add(
          name: _nameController.text.trim(),
          phone: phone,
          relationship: _relationshipController.text,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('Failed to save emergency contact: $e');
      _showMessage(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
        decoration: BoxDecoration(
          color: context.colors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: context.colors.muted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEditing ? tr('auth_edit_contact') : tr('auth_add_contact'),
                style: TextStyle(
                  color: context.colors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 18),
              _Field(
                controller: _nameController,
                label: tr('auth_name_field'),
                icon: Icons.person_outline_rounded,
              ),
              SizedBox(height: 14),
              _Field(
                controller: _relationshipController,
                label: tr('auth_relationship_optional'),
                icon: Icons.diversity_1_rounded,
              ),
              SizedBox(height: 14),
              _Field(
                controller: _phoneController,
                label: tr('auth_phone'),
                prefix: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: CountryCodePicker(
                    selected: _selectedCountry,
                    onChanged: (c) => setState(() => _selectedCountry = c),
                  ),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_selectedCountry.maxPhoneDigits),
                ],
              ),
              SizedBox(height: 24),
              GradientButton(
                label: _isEditing ? tr('auth_save_changes') : tr('auth_add_contact'),
                icon: Icons.check_rounded,
                onPressed: _save,
                loading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.icon,
    this.prefix,
    this.keyboardType,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final Widget? prefix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefix ??
            (icon != null
                ? Icon(icon, color: context.colors.muted, size: 20)
                : null),
        filled: true,
        fillColor: context.colors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.colors.ink, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      ),
    );
  }
}
