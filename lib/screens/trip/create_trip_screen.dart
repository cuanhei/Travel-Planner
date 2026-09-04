import 'package:flutter/cupertino.dart' show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/malaysia_city.dart';
import '../../models/trip_stop_location.dart';
import '../../services/locale_service.dart';
import '../../services/malaysia_location_service.dart';
import '../../services/photon_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show Place, places;
import 'location_map_picker.dart' show buildCustomPlace;
import 'optimized_itinerary_screen.dart';
import 'stop_map_picker.dart';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// e.g. "Aug 14 – Aug 16, 2026".
String _formatDateRange(DateTimeRange range) {
  final start = range.start;
  final end = range.end;
  return '${_monthNames[start.month - 1]} ${start.day} – '
      '${_monthNames[end.month - 1]} ${end.day}, ${end.year}';
}

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Fixed interest options for "auto-recommend more places" — always the
/// same list, regardless of which stops the traveler has already picked.
/// [category] is the [Place.category] / [TripStopLocation.category] value
/// matched against when generating recommendations; [label] is the more
/// specific, traveler-facing name shown on the chip.
// A function, not `const` — `tr()` isn't a compile-time constant, and
// (as elsewhere in this app) a `const`/`final` list would only ever be
// evaluated once, freezing these labels at whichever language was active
// at that moment instead of retranslating on a language change.
List<({String label, IconData icon, String category})> _interestOptions() => [
  (label: tr('trip_interest_hotel'), icon: Icons.hotel_rounded, category: 'Hotel'),
  (label: tr('trip_interest_restaurant'), icon: Icons.restaurant_rounded, category: 'Food'),
  (label: tr('trip_interest_shopping'), icon: Icons.shopping_bag_rounded, category: 'Shopping'),
  (label: tr('trip_interest_museum'), icon: Icons.museum_rounded, category: 'Culture'),
  (label: tr('trip_interest_beach'), icon: Icons.beach_access_rounded, category: 'Beach'),
  (label: tr('trip_interest_nature'), icon: Icons.terrain_rounded, category: 'Nature'),
  (
    label: tr('trip_interest_attraction'),
    icon: Icons.attractions_rounded,
    category: 'Attraction',
  ),
];

/// Trip creation form: name/description, trip logistics, a real
/// OpenStreetMap-backed location search embedded directly on the page for
/// picking exact stops (see [StopMapPicker]), interest categories, and an
/// optional "auto-recommend more places" toggle that supplements the
/// traveler's picks from Explore's curated catalog — all in one page.
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
  final _photonService = PhotonService();
  MalaysiaCity? _startCity;
  MalaysiaCity? _endCity;
  DateTimeRange? _dateRange;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  int _travelers = 2;
  final Set<String> _selectedInterests = {'Shopping', 'Food'};
  final Map<Place, TripStopLocation> _mapPickedStops = {};
  bool _autoRecommend = true;
  bool _saving = false;

  /// Stops picked via the real map/search, wrapped as synthetic [Place]s
  /// so they can flow into the existing itinerary-generation screens.
  Set<Place> get _selectedPlaces => _mapPickedStops.keys.toSet();

  /// Trip length in days (inclusive of both ends), for day-by-day route
  /// planning — defaults to 1 when no date range has been picked.
  int get _dayCount {
    final range = _dateRange;
    if (range == null) return 1;
    return range.end.difference(range.start).inDays + 1;
  }

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

  Future<void> _pickDatesAndTimes() async {
    final result = await showModalBottomSheet<_TripSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DatesPickerSheet(
        initialRange: _dateRange,
        initialStartTime: _startTime,
        initialEndTime: _endTime,
      ),
    );
    if (result == null) return;
    setState(() {
      _dateRange = result.dateRange;
      _startTime = result.startTime;
      _endTime = result.endTime;
    });
  }

  void _addStop(TripStopLocation stop) {
    setState(() => _mapPickedStops[buildCustomPlace(stop.name)] = stop);
  }

  void _removeStop(Place place) {
    setState(() => _mapPickedStops.remove(place));
  }

  bool get _canSubmit => (_selectedPlaces.isNotEmpty || _autoRecommend) && !_saving;

  double _parseBudget(String text) {
    final match = RegExp(
      r'\d+(\.\d+)?',
    ).firstMatch(text.replaceAll(',', ''));
    return match == null ? 0 : double.tryParse(match.group(0)!) ?? 0;
  }

  Future<void> _submit() async {
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

    setState(() => _saving = true);

    final stops = _mapPickedStops.values.toList();
    LatLng? startPoint;
    LatLng? endPoint;

    // Real, geocoded stops + a start city let the itinerary screen plot an
    // actual hotel-anchored day plan; without both of those there's
    // nothing to anchor it to, so it falls back to its simulated
    // weather/day-split view instead.
    if (stops.isNotEmpty && _startCity != null) {
      try {
        startPoint = await _photonService.geocodeQuery(
          '${_startCity!.city}, ${_startCity!.state}, Malaysia',
        );
        if (_endCity != null) {
          endPoint = await _photonService.geocodeQuery(
            '${_endCity!.city}, ${_endCity!.state}, Malaysia',
          );
        }
      } catch (_) {
        startPoint = null;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OptimizedItineraryScreen(
          tripName: _nameController.text.trim(),
          description: _descriptionController.text.trim(),
          places: finalPlaces,
          recommendedNames: recommended.map((p) => p.name).toSet(),
          realStops: stops,
          startLabel: _startCity?.label,
          startPoint: startPoint,
          endLabel: _endCity?.label,
          endPoint: endPoint,
          dayCount: _dayCount,
          startDate: _dateRange?.start,
          dayStartTime: _startTime,
          // Nothing has been saved yet — the itinerary preview screen
          // saves it all (trip, stops, schedule) once the traveler
          // confirms with its own "Save Trip" button.
          startCity: _startCity,
          endCity: _endCity,
          dateRange: _dateRange,
          endTime: _endTime,
          totalBudget: _parseBudget(_budgetController.text),
          autoRecommend: _autoRecommend,
          interests: _selectedInterests,
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
                      _CityField(city: _startCity, onTap: _pickStartCity),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_ending_at')),
                      _CityField(city: _endCity, onTap: _pickEndCity),
                      const SizedBox(height: 18),
                      _FieldLabel(tr('trip_field_travel_dates_time')),
                      _ScheduleField(
                        dateRange: _dateRange,
                        startTime: _startTime,
                        endTime: _endTime,
                        onTap: _pickDatesAndTimes,
                      ),
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
                      '${_mapPickedStops.length} ${tr('trip_selected_word')}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    children: [
                      Text(
                        tr('trip_locations_hint_map'),
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 320,
                        child: StopMapPicker(
                          markedStops: _mapPickedStops.values.toList(),
                          onAdd: _addStop,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_mapPickedStops.isEmpty)
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
                          children: _mapPickedStops.entries.map((entry) {
                            final place = entry.key;
                            final stop = entry.value;
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
                                    stop.categoryIcon,
                                    size: 14,
                                    color: context.colors.ink,
                                  ),
                                  const SizedBox(width: 6),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        stop.name,
                                        style: TextStyle(
                                          color: context.colors.ink,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12.5,
                                        ),
                                      ),
                                      Text(
                                        '${stop.category} · ${stop.address}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.colors.muted,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _removeStop(place),
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
                                    children: _interestOptions().map((opt) {
                                      final isSelected = _selectedInterests
                                          .contains(opt.category);
                                      return GestureDetector(
                                        onTap: () => setState(() {
                                          isSelected
                                              ? _selectedInterests.remove(
                                                  opt.category,
                                                )
                                              : _selectedInterests.add(
                                                  opt.category,
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
                                                opt.icon,
                                                size: 14,
                                                color: isSelected
                                                    ? Colors.white
                                                    : context.colors.muted,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                opt.label,
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
                    loading: _saving,
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
                city?.label ?? tr('trip_select_a_city'),
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
        return Material(
          color: context.colors.card,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
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
                    hintText: tr('trip_search_city_state_hint'),
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
                            '${tr('trip_could_not_load_cities_prefix')}: '
                            '${snapshot.error}',
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
                          tr('trip_no_matching_city'),
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

/// Tappable field showing the trip's date range + start/end time on two
/// lines, or a placeholder until picked. Opens [_DatesPickerSheet].
class _ScheduleField extends StatelessWidget {
  const _ScheduleField({
    required this.dateRange,
    required this.startTime,
    required this.endTime,
    required this.onTap,
  });

  final DateTimeRange? dateRange;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final range = dateRange;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    range == null
                        ? tr('trip_select_travel_dates')
                        : _formatDateRange(range),
                    style: TextStyle(
                      color: range == null
                          ? context.colors.muted
                          : context.colors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (range != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${startTime.format(context)} — ${endTime.format(context)}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.expand_more_rounded, color: context.colors.muted),
          ],
        ),
      ),
    );
  }
}

/// Result of [_DatesPickerSheet]: the picked date range plus start/end time.
class _TripSchedule {
  const _TripSchedule({
    required this.dateRange,
    required this.startTime,
    required this.endTime,
  });

  final DateTimeRange dateRange;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
}

/// Bottom-sheet date + time picker, in the same visual style as
/// [_CityPickerSheet] — everything happens in one popup on the same page,
/// no separate dialog/screen. Two calendars (start/end date) plus two
/// scrollable time wheels (start/end time), with a "Done" button to confirm.
class _DatesPickerSheet extends StatefulWidget {
  const _DatesPickerSheet({
    required this.initialRange,
    required this.initialStartTime,
    required this.initialEndTime,
  });

  final DateTimeRange? initialRange;
  final TimeOfDay initialStartTime;
  final TimeOfDay initialEndTime;

  @override
  State<_DatesPickerSheet> createState() => _DatesPickerSheetState();
}

class _DatesPickerSheetState extends State<_DatesPickerSheet> {
  late final DateTime _today = _dateOnly(DateTime.now());
  late DateTime _start;
  late DateTime _end;
  late TimeOfDay _startTime = widget.initialStartTime;
  late TimeOfDay _endTime = widget.initialEndTime;

  /// Bumped only when [_clampEndTime] actually corrects [_endTime], so the
  /// End Time wheel resets to reflect it. Kept separate from a plain
  /// `ValueKey(_endTime)` so normal scrolling through that same wheel
  /// doesn't rebuild (and visually stutter) on every tick.
  int _endTimeResetTick = 0;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _start = widget.initialRange?.start ?? _today;
    _end = widget.initialRange?.end ?? _today.add(const Duration(days: 2));
    _clampEndTime();
  }

  /// On a same-day trip, the end time can't be at or before the start time
  /// — bumps it forward when that happens (from a start-time change, an
  /// end-time change, or the dates collapsing onto the same day).
  void _clampEndTime() {
    if (!_isSameDate(_start, _end)) return;
    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (endMinutes <= startMinutes) {
      final adjusted = (startMinutes + 30).clamp(0, 23 * 60 + 59);
      _endTime = TimeOfDay(hour: adjusted ~/ 60, minute: adjusted % 60);
      _endTimeResetTick++;
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      _TripSchedule(
        dateRange: DateTimeRange(start: _start, end: _end),
        startTime: _startTime,
        endTime: _endTime,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lastDate = DateTime(_today.year + 3);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Material(
          color: context.colors.card,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('trip_field_travel_dates_time'),
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _confirm,
                      child: Text(
                        tr('common_done'),
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    _SheetSectionLabel(tr('trip_field_travel_dates')),
                    _RangeCalendar(
                      start: _start,
                      end: _end,
                      firstDate: _today,
                      lastDate: lastDate,
                      onChanged: (start, end) => setState(() {
                        _start = start;
                        _end = end;
                        _clampEndTime();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SheetSectionLabel(tr('trip_start_time')),
                              SizedBox(
                                height: 130,
                                child: CupertinoDatePicker(
                                  mode: CupertinoDatePickerMode.time,
                                  initialDateTime: DateTime(
                                    2000,
                                    1,
                                    1,
                                    _startTime.hour,
                                    _startTime.minute,
                                  ),
                                  onDateTimeChanged: (dt) => setState(() {
                                    _startTime = TimeOfDay(
                                      hour: dt.hour,
                                      minute: dt.minute,
                                    );
                                    _clampEndTime();
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SheetSectionLabel(tr('trip_end_time')),
                              SizedBox(
                                height: 130,
                                child: CupertinoDatePicker(
                                  key: ValueKey(_endTimeResetTick),
                                  mode: CupertinoDatePickerMode.time,
                                  initialDateTime: DateTime(
                                    2000,
                                    1,
                                    1,
                                    _endTime.hour,
                                    _endTime.minute,
                                  ),
                                  onDateTimeChanged: (dt) => setState(() {
                                    _endTime = TimeOfDay(
                                      hour: dt.hour,
                                      minute: dt.minute,
                                    );
                                    _clampEndTime();
                                  }),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SheetSectionLabel extends StatelessWidget {
  const _SheetSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}

const _weekdayLabels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

/// Single-month calendar with Material-range-picker-style selection: start
/// and end days get a filled circle, and every day between them gets a
/// tinted highlight band — all in one calendar (no separate start/end
/// views), with month navigation arrows.
class _RangeCalendar extends StatefulWidget {
  const _RangeCalendar({
    required this.start,
    required this.end,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
  });

  final DateTime start;
  final DateTime end;
  final DateTime firstDate;
  final DateTime lastDate;
  final void Function(DateTime start, DateTime end) onChanged;

  @override
  State<_RangeCalendar> createState() => _RangeCalendarState();
}

class _RangeCalendarState extends State<_RangeCalendar> {
  late DateTime _displayedMonth = DateTime(widget.start.year, widget.start.month);

  void _changeMonth(int delta) {
    setState(() {
      _displayedMonth = DateTime(
        _displayedMonth.year,
        _displayedMonth.month + delta,
      );
    });
  }

  void _onDayTap(DateTime day) {
    final hasCompleteRange = !_isSameDate(widget.start, widget.end);
    if (hasCompleteRange || day.isBefore(widget.start)) {
      widget.onChanged(day, day);
    } else {
      widget.onChanged(widget.start, day);
    }
  }

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + 1,
      0,
    ).day;
    final leading = firstOfMonth.weekday % 7; // 0 = Sunday
    final totalCells = leading + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final canGoBack = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
    ).isAfter(DateTime(widget.firstDate.year, widget.firstDate.month));

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              onPressed: canGoBack ? () => _changeMonth(-1) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${_monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        Row(
          children: [
            for (final w in _weekdayLabels)
              Expanded(
                child: Center(
                  child: Text(
                    w,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Builder(
                  builder: (context) {
                    final dayNum = r * 7 + c - leading + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return const Expanded(child: SizedBox(height: 40));
                    }
                    final day = DateTime(
                      _displayedMonth.year,
                      _displayedMonth.month,
                      dayNum,
                    );
                    final disabled =
                        day.isBefore(widget.firstDate) ||
                        day.isAfter(widget.lastDate);
                    final isStart = _isSameDate(day, widget.start);
                    final isEnd = _isSameDate(day, widget.end);
                    final isEndpoint = isStart || isEnd;
                    // Inclusive of both endpoints, so a same-day trip (start
                    // == end) still shows the highlight band, not just a
                    // bare circle, and the band visually flows through the
                    // start/end days rather than stopping just short of them.
                    final inRange =
                        !day.isBefore(widget.start) && !day.isAfter(widget.end);

                    return Expanded(
                      child: GestureDetector(
                        onTap: disabled ? null : () => _onDayTap(day),
                        child: Container(
                          height: 40,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          color: inRange && !disabled
                              ? AppColors.accent.withValues(alpha: 0.18)
                              : null,
                          alignment: Alignment.center,
                          child: isEndpoint
                              ? Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: context.colors.ink,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '$dayNum',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                )
                              : Text(
                                  '$dayNum',
                                  style: TextStyle(
                                    color: disabled
                                        ? context.colors.muted.withValues(
                                            alpha: 0.35,
                                          )
                                        : context.colors.ink,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
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
