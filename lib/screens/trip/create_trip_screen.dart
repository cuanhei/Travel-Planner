import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show Place, categories, places;
import 'location_map_picker.dart';
import 'smart_schedule_screen.dart';

/// UI-only trip creation form: name/description, trip logistics, a
/// stylized map for picking exact locations (no map SDK/API), interest
/// categories, and an optional "auto-recommend more places" toggle that
/// supplements the traveler's picks — all in one page.
class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _nameController = TextEditingController(text: 'Penang Adventure');
  final _descriptionController = TextEditingController();
  final _destinationController = TextEditingController(
    text: 'Penang, Malaysia',
  );
  final _budgetController = TextEditingController(text: 'RM 1,500');
  int _travelers = 2;
  final Set<String> _selectedInterests = {'Shopping', 'Food'};
  final Set<Place> _selectedPlaces = {places[0], places[2]};
  bool _autoRecommend = true;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _destinationController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _addCustomLocation() async {
    final place = await showAddCustomLocationDialog(context);
    if (place == null) return;
    setState(() => _selectedPlaces.add(place));
  }

  void _removePlace(Place place) {
    setState(() => _selectedPlaces.remove(place));
  }

  bool get _canSubmit => _selectedPlaces.isNotEmpty || _autoRecommend;

  void _submit() {
    final recommended = _autoRecommend
        ? places
              .where(
                (p) =>
                    !_selectedPlaces.contains(p) &&
                    _selectedInterests.contains(p.category),
              )
              .take(2)
              .toList()
        : <Place>[];

    final finalPlaces = [..._selectedPlaces, ...recommended];
    if (finalPlaces.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SmartScheduleScreen(
          tripName: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          places: finalPlaces,
          recommendedNames: recommended.map((p) => p.name).toSet(),
        ),
      ),
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
              title: tr('trip_create_trip_title'),
              subtitle: tr('trip_create_trip_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _SectionCard(
                    icon: Icons.edit_note_rounded,
                    title: tr('trip_section_trip_details'),
                    children: [
                      _FieldLabel(tr('trip_field_trip_name')),
                      _InputBox(
                        controller: _nameController,
                        icon: Icons.edit_rounded,
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_description_optional')),
                      _InputBox(
                        controller: _descriptionController,
                        icon: Icons.notes_rounded,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.map_rounded,
                    title: tr('trip_section_travel_information'),
                    children: [
                      _FieldLabel(tr('trip_field_starting_from')),
                      _InputBox(
                        controller: _destinationController,
                        icon: Icons.location_on_rounded,
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_ending_at')),
                      _InputBox(
                        controller: _destinationController,
                        icon: Icons.location_on_rounded,
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_travel_dates')),
                      _DatePickerRow(onTap: () {}),
                      const SizedBox(height: 18),
                      // _FieldLabel('Travelers'),
                      // _TravelersStepper(
                      //   count: _travelers,
                      //   onChanged: (v) => setState(() => _travelers = v),
                      // ),
                      // const SizedBox(height: 18),
                      _FieldLabel(tr('trip_budget_word')),
                      _InputBox(
                        controller: _budgetController,
                        icon: Icons.account_balance_wallet_rounded,
                        keyboardType: TextInputType.text,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.pin_drop_rounded,
                    title: tr('trip_section_locations'),
                    trailing: Text(
                      '${_selectedPlaces.length} ${tr('trip_selected_word')}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      Text(
                        tr('trip_locations_hint'),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      LocationMapPicker(
                        selected: _selectedPlaces,
                        onToggle: (place) => setState(() {
                          _selectedPlaces.contains(place)
                              ? _selectedPlaces.remove(place)
                              : _selectedPlaces.add(place);
                        }),
                        onAddCustom: _addCustomLocation,
                      ),
                      const SizedBox(height: 12),
                      if (_selectedPlaces.isEmpty)
                        Text(
                          tr('trip_no_locations_picked'),
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                          ),
                        )
                      else
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _selectedPlaces.map((place) {
                            return Container(
                              padding: const EdgeInsets.only(
                                left: 12,
                                right: 6,
                                top: 6,
                                bottom: 6,
                              ),
                              decoration: BoxDecoration(
                                color: context.colors.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: context.colors.muted.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    place.icon,
                                    size: 14,
                                    color: context.colors.ink,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    place.name,
                                    style: TextStyle(
                                      color: context.colors.ink,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  GestureDetector(
                                    onTap: () => _removePlace(place),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 16,
                                      color: context.colors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionCard(
                    icon: Icons.tune_rounded,
                    title: tr('trip_section_preferences'),
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.auto_awesome_rounded,
                              color: AppColors.accent,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('trip_auto_recommend_title'),
                                  style: TextStyle(
                                    color: context.colors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tr('trip_auto_recommend_desc'),
                                  style: TextStyle(
                                    color: context.colors.muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _autoRecommend,
                            onChanged: (v) =>
                                setState(() => _autoRecommend = v),
                            activeThumbColor: Colors.white,
                            activeTrackColor: context.colors.ink,
                          ),
                        ],
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOut,
                        alignment: Alignment.topCenter,
                        child: _autoRecommend
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 18),
                                  _FieldLabel(tr('trip_field_interests')),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: categories.map((c) {
                                      final isSelected = _selectedInterests
                                          .contains(c.label);
                                      return GestureDetector(
                                        onTap: () => setState(() {
                                          isSelected
                                              ? _selectedInterests
                                                    .remove(c.label)
                                              : _selectedInterests.add(
                                                  c.label,
                                                );
                                        }),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? context.colors.ink
                                                : context.colors.surface,
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: isSelected
                                                  ? context.colors.ink
                                                  : context.colors.muted
                                                        .withValues(
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
                                                color: isSelected
                                                    ? Colors.white
                                                    : context.colors.muted,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                c.label,
                                                style: TextStyle(
                                                  color: isSelected
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
                                    }).toList(),
                                  ),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: tr('trip_plan_my_trip'),
                    icon: Icons.route_rounded,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: context.colors.ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 16),
          ...children,
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
    this.keyboardType,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        prefixIcon: maxLines == 1
            ? Icon(icon, color: context.colors.muted, size: 20)
            : null,
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
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: context.colors.muted,
              size: 18,
            ),
            const SizedBox(width: 12),
            Text(
              'Aug 14 — Aug 16, 2026',
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(Icons.expand_more_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

class _TravelersStepper extends StatelessWidget {
  const _TravelersStepper({required this.count, required this.onChanged});

  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.people_alt_rounded, color: context.colors.muted, size: 18),
          const SizedBox(width: 12),
          Text(
            '$count ${count == 1 ? tr('trip_traveler_singular') : tr('trip_traveler_plural')}',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _StepperButton(
            icon: Icons.remove_rounded,
            onTap: count > 1 ? () => onChanged(count - 1) : null,
          ),
          const SizedBox(width: 8),
          _StepperButton(
            icon: Icons.add_rounded,
            onTap: () => onChanged(count + 1),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: onTap == null
                ? context.colors.muted.withValues(alpha: 0.4)
                : context.colors.ink,
          ),
        ),
      ),
    );
  }
}
