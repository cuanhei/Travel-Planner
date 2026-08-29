import 'package:flutter/material.dart';

import '../../models/malaysia_city.dart';
import '../../services/malaysia_location_service.dart';
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
  final _budgetController = TextEditingController(text: 'RM 1,500');
  final _locationService = MalaysiaLocationService();
  late final _citiesFuture = _locationService.getCities();
  MalaysiaCity? _startCity;
  MalaysiaCity? _endCity;
  int _travelers = 2;
  final Set<String> _selectedInterests = {'Shopping', 'Food'};
  final Set<Place> _selectedPlaces = {places[0], places[2]};
  bool _autoRecommend = true;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _pickStartCity() async {
    final picked = await _pickCity(context);
    if (picked != null) setState(() => _startCity = picked);
  }

  Future<void> _pickEndCity() async {
    final picked = await _pickCity(context);
    if (picked != null) setState(() => _endCity = picked);
  }

  Future<MalaysiaCity?> _pickCity(BuildContext context) {
    return showModalBottomSheet<MalaysiaCity>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CityPickerSheet(citiesFuture: _citiesFuture),
    );
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
            const DetailHeader(
              title: 'Create Trip',
              subtitle: 'Name it, pick your spots, we\'ll plan the rest',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  _SectionCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Trip Details',
                    children: [
                      _FieldLabel('Trip Name'),
                      _InputBox(
                        controller: _nameController,
                        icon: Icons.edit_rounded,
                      ),
                      const SizedBox(height: 18),
                      _FieldLabel('Description (optional)'),
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
                    title: 'Travel Information',
                    children: [
                      _FieldLabel('Starting From'),
                      _CityField(city: _startCity, onTap: _pickStartCity),
                      const SizedBox(height: 18),
                      _FieldLabel('Ending At'),
                      _CityField(city: _endCity, onTap: _pickEndCity),
                      const SizedBox(height: 18),
                      _FieldLabel('Travel Dates'),
                      _DatePickerRow(onTap: () {}),
                      const SizedBox(height: 18),
                      // _FieldLabel('Travelers'),
                      // _TravelersStepper(
                      //   count: _travelers,
                      //   onChanged: (v) => setState(() => _travelers = v),
                      // ),
                      // const SizedBox(height: 18),
                      _FieldLabel('Budget'),
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
                    title: 'Locations',
                    trailing: Text(
                      '${_selectedPlaces.length} selected',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      Text(
                        'Search for a place you want to visit, or tap directly on the map to add it to your trip.',
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
                          'No locations picked yet.',
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
                    title: 'Preferences',
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
                                  'Auto-recommend more places',
                                  style: TextStyle(
                                    color: context.colors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Add AI-suggested spots that match your interests',
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
                                  _FieldLabel('Interests'),
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
                    label: 'Plan My Trip',
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

/// Tappable field showing the selected Malaysian city, or a placeholder
/// until one is picked. Opens [_CityPickerSheet] on tap.
class _CityField extends StatelessWidget {
  const _CityField({required this.city, required this.onTap});

  final MalaysiaCity? city;
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
              Icons.location_on_rounded,
              color: context.colors.muted,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                city?.label ?? 'Select a city',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: city == null
                      ? context.colors.muted
                      : context.colors.ink,
                  fontWeight: FontWeight.w600,
                ),
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

/// Searchable bottom sheet listing every Malaysian city from
/// [MalaysiaLocationService], filtered as the user types. Returns the
/// tapped [MalaysiaCity] via `Navigator.pop`.
class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet({required this.citiesFuture});

  final Future<List<MalaysiaCity>> citiesFuture;

  @override
  State<_CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<_CityPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: context.colors.ink),
                  decoration: InputDecoration(
                    hintText: 'Search city or state…',
                    hintStyle: TextStyle(color: context.colors.muted),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: context.colors.muted,
                    ),
                    filled: true,
                    fillColor: context.colors.surface,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<MalaysiaCity>>(
                  future: widget.citiesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load cities: ${snapshot.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.colors.muted),
                          ),
                        ),
                      );
                    }

                    final cities = snapshot.data ?? const <MalaysiaCity>[];
                    final q = _query.trim().toLowerCase();
                    final filtered = q.isEmpty
                        ? cities
                        : cities
                              .where(
                                (c) =>
                                    c.city.toLowerCase().contains(q) ||
                                    c.state.toLowerCase().contains(q),
                              )
                              .toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          'No matching city',
                          style: TextStyle(color: context.colors.muted),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) {
                        final c = filtered[i];
                        return ListTile(
                          title: Text(
                            c.city,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            c.state,
                            style: TextStyle(
                              color: context.colors.muted,
                              fontSize: 12,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(c),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
            '$count ${count == 1 ? 'traveler' : 'travelers'}',
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
