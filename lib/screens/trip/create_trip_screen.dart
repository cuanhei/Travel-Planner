import 'package:flutter/cupertino.dart'
    show CupertinoDatePicker, CupertinoDatePickerMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show FilteringTextInputFormatter, TextInputFormatter;

import '../../models/trip.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show Place, places;
import 'location_map_picker.dart';
import 'optimized_itinerary_screen.dart';

/// A Malaysian city/state pair for the Starting From / Ending At pickers —
/// a small fixed list standing in for what used to be a live postcode
/// lookup; the picker UI itself is unchanged.
class _City {
  const _City(this.city, this.state);
  final String city;
  final String state;
  String get label => '$city, $state';
}

const _dummyCities = [
  _City('George Town', 'Penang'),
  _City('Butterworth', 'Penang'),
  _City('Kuala Lumpur', 'Federal Territory'),
  _City('Petaling Jaya', 'Selangor'),
  _City('Shah Alam', 'Selangor'),
  _City('Johor Bahru', 'Johor'),
  _City('Malacca City', 'Malacca'),
  _City('Ipoh', 'Perak'),
  _City('Kota Kinabalu', 'Sabah'),
  _City('Kuching', 'Sarawak'),
  _City('Alor Setar', 'Kedah'),
  _City('Kota Bharu', 'Kelantan'),
  _City('Kuantan', 'Pahang'),
  _City('Seremban', 'Negeri Sembilan'),
  _City('Kangar', 'Perlis'),
];

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

/// e.g. "Aug 14 – Aug 16, 2026".
String _formatDateRange(DateTimeRange range) {
  final start = range.start;
  final end = range.end;
  return '${_monthNames[start.month - 1]} ${start.day} – '
      '${_monthNames[end.month - 1]} ${end.day}, ${end.year}';
}

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool _dateRangesOverlap(
  DateTime aStart,
  DateTime aEnd,
  DateTime bStart,
  DateTime bEnd,
) => !aEnd.isBefore(bStart) && !aStart.isAfter(bEnd);

/// The first of [blocked] whose range overlaps [start]..[end] (inclusive),
/// or null if none do — used both to grey out individual days already
/// claimed by another of the traveler's trips and to reject a range that
/// would span across one of those windows without directly landing on it.
({DateTimeRange range, String tripName})? _blockingConflict(
  DateTime start,
  DateTime end,
  List<({DateTimeRange range, String tripName})> blocked,
) {
  for (final candidate in blocked) {
    if (_dateRangesOverlap(
      start,
      end,
      candidate.range.start,
      candidate.range.end,
    )) {
      return candidate;
    }
  }
  return null;
}

/// Fixed interest options for "auto-recommend more places" — always the
/// same list, regardless of which stops the traveler has already picked.
/// [category] is the [Place.category] value matched against when
/// generating recommendations; [label] is the more specific,
/// traveler-facing name shown on the chip.
const _interestOptions = [
  (label: 'Hotel', icon: Icons.hotel_rounded, category: 'Hotel'),
  (label: 'Restaurant', icon: Icons.restaurant_rounded, category: 'Food'),
  (label: 'Shopping', icon: Icons.shopping_bag_rounded, category: 'Shopping'),
  (label: 'Museum', icon: Icons.museum_rounded, category: 'Culture'),
  (label: 'Beach', icon: Icons.beach_access_rounded, category: 'Beach'),
  (label: 'Nature', icon: Icons.terrain_rounded, category: 'Nature'),
  (
    label: 'Attraction',
    icon: Icons.attractions_rounded,
    category: 'Attraction',
  ),
];

/// Trip creation form: name/description, trip logistics, a catalog-based
/// location picker for picking stops, interest categories, and an optional
/// "auto-recommend more places" toggle that supplements the traveler's
/// picks from Explore's curated catalog — all in one page.
class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameFieldKey = GlobalKey<FormFieldState<String>>();
  final _startCityFieldKey = GlobalKey<FormFieldState<_City>>();
  final _endCityFieldKey = GlobalKey<FormFieldState<_City>>();
  final _dateRangeFieldKey = GlobalKey<FormFieldState<DateTimeRange>>();
  final _budgetFieldKey = GlobalKey<FormFieldState<String>>();
  final _locationsFieldKey = GlobalKey<FormFieldState<bool>>();
  final _listScrollController = ScrollController();

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _budgetController = TextEditingController(text: '1000');
  final _tripService = TripService();
  late final Future<List<Trip>> _myTripsFuture = _tripService.myTrips();
  _City? _startCity;
  _City? _endCity;
  DateTimeRange? _dateRange;
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 18, minute: 0);
  final Set<String> _selectedInterests = {'Shopping', 'Food'};
  final Set<Place> _selectedPlaces = {};
  bool _autoRecommend = true;
  bool _isSubmitting = false;
  bool _hasTriedSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _budgetController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickStartCity() async {
    final picked = await _pickCity(context);
    if (picked == null) return;
    setState(() => _startCity = picked);
    _startCityFieldKey.currentState?.didChange(picked);
  }

  Future<void> _pickEndCity() async {
    final picked = await _pickCity(context);
    if (picked == null) return;
    setState(() => _endCity = picked);
    _endCityFieldKey.currentState?.didChange(picked);
  }

  Future<_City?> _pickCity(BuildContext context) {
    return showModalBottomSheet<_City>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CityPickerSheet(),
    );
  }

  /// Every date range the traveler is already committed to via another
  /// trip they belong to — the new trip's dates must not clash with any
  /// of these. Trips without both a start and end date set don't block
  /// anything.
  Future<List<({DateTimeRange range, String tripName})>>
  _blockedDateRanges() async {
    List<Trip> trips;
    try {
      trips = await _myTripsFuture;
    } catch (_) {
      return const [];
    }
    return [
      for (final trip in trips)
        if (trip.startDate != null && trip.endDate != null)
          (
            range: DateTimeRange(start: trip.startDate!, end: trip.endDate!),
            tripName: trip.name,
          ),
    ];
  }

  Future<void> _pickDatesAndTimes() async {
    final blockedRanges = await _blockedDateRanges();
    if (!mounted) return;
    final result = await showModalBottomSheet<_TripSchedule>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DatesPickerSheet(
        initialRange: _dateRange,
        initialStartTime: _startTime,
        initialEndTime: _endTime,
        blockedRanges: blockedRanges,
      ),
    );
    if (result == null) return;
    setState(() {
      _dateRange = result.dateRange;
      _startTime = result.startTime;
      _endTime = result.endTime;
    });
    _dateRangeFieldKey.currentState?.didChange(result.dateRange);
  }

  void _togglePlace(Place place) {
    setState(() {
      _selectedPlaces.contains(place)
          ? _selectedPlaces.remove(place)
          : _selectedPlaces.add(place);
    });
    _locationsFieldKey.currentState?.didChange(
      _selectedPlaces.isNotEmpty || _autoRecommend,
    );
  }

  bool get _canSubmit => !_isSubmitting;

  /// Parses the Budget field down to a plain number for
  /// `trips.total_budget` — strips everything but digits and the decimal
  /// point (the field itself is digits-only, but this stays defensive).
  double _parseBudget(String text) =>
      double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  String _formatTimeOfDay(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  void _showRequiredMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  String? _validateName(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Give your trip a name' : null;

  String? _validateBudget(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Enter a budget';
    final parsed = double.tryParse(text);
    if (parsed == null || parsed <= 0) return 'Enter a valid budget';
    return null;
  }

  /// Scrolls the first field with a validation error into view, in the
  /// same top-to-bottom order the fields appear on the page. Returns
  /// whether an errored field was actually found and scrolled to.
  bool _scrollToFirstError() {
    final fields = [
      (
        context: () => _nameFieldKey.currentContext,
        hasError: () => _nameFieldKey.currentState?.hasError ?? false,
      ),
      (
        context: () => _startCityFieldKey.currentContext,
        hasError: () => _startCityFieldKey.currentState?.hasError ?? false,
      ),
      (
        context: () => _endCityFieldKey.currentContext,
        hasError: () => _endCityFieldKey.currentState?.hasError ?? false,
      ),
      (
        context: () => _dateRangeFieldKey.currentContext,
        hasError: () => _dateRangeFieldKey.currentState?.hasError ?? false,
      ),
      (
        context: () => _budgetFieldKey.currentContext,
        hasError: () => _budgetFieldKey.currentState?.hasError ?? false,
      ),
      (
        context: () => _locationsFieldKey.currentContext,
        hasError: () => _locationsFieldKey.currentState?.hasError ?? false,
      ),
    ];

    for (final field in fields) {
      if (!field.hasError()) continue;
      final fieldContext = field.context();
      if (fieldContext != null) {
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
      }
      return true;
    }
    return false;
  }

  Future<void> _submit() async {
    // Rebuild the name field in "always validate" mode from the first
    // submission attempt onward. This makes its red inline error persistent,
    // just like the other required fields, instead of only showing a toast.
    if (!_hasTriedSubmitting) {
      setState(() => _hasTriedSubmitting = true);
    }

    // Non-negotiable guard: no request may reach TripService with a
    // blank/whitespace-only name, even if the Form tree is ever
    // unavailable — checked (and re-validated) explicitly, in addition
    // to being part of the Form below.
    final name = _nameController.text.trim();
    final nameIsBlank = _validateName(name) != null;
    _nameFieldKey.currentState?.validate();

    // Fails CLOSED: if the form's state is ever unavailable for some
    // reason, treat that as invalid rather than silently letting an
    // unvalidated submission through.
    final formIsValid = _formKey.currentState?.validate() ?? false;

    if (nameIsBlank || !formIsValid) {
      // Scrolling/validating right after the setState calls above would
      // read stale (pre-rebuild) layout — this field's new error text
      // hasn't been laid out yet. Defer to the frame after that rebuild
      // lands, so every required field (name included) scrolls into
      // view exactly like the rest.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scrolledToError = _scrollToFirstError();
        if (!scrolledToError && _listScrollController.hasClients) {
          _listScrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
      _showRequiredMessage(
        nameIsBlank
            ? 'Give your trip a name before planning it.'
            : 'Please fill in the required fields.',
      );
      return;
    }

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
    if (finalPlaces.isEmpty) {
      _showRequiredMessage(
        'No matching places found for your interests — try different '
        'interests, or pick locations manually.',
      );
      return;
    }

    final budget = _parseBudget(_budgetController.text);
    setState(() => _isSubmitting = true);
    try {
      // Trip details + travel information only, for now — no stops,
      // interests, or day-by-day schedule yet.
      await _tripService.createTrip(
        name: name,
        description: _descriptionController.text.trim(),
        destination: _endCity?.label ?? _startCity?.label,
        startCity: _startCity?.city,
        startState: _startCity?.state,
        endCity: _endCity?.city,
        endState: _endCity?.state,
        startDate: _dateRange?.start,
        endDate: _dateRange?.end,
        startTime: _formatTimeOfDay(_startTime),
        endTime: _formatTimeOfDay(_endTime),
        totalBudget: budget,
        autoRecommend: _autoRecommend,
      );
    } catch (e) {
      // Full exception (PostgrestException's message/code/details/hint)
      // printed to the console — the SnackBar alone can truncate or get
      // dismissed before it's readable.
      debugPrint('Create trip failed: $e');
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          content: Text('Could not create trip: $e'),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _isSubmitting = false);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OptimizedItineraryScreen(
          tripName: name,
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
              child: Form(
                key: _formKey,
                child: ListView(
                  controller: _listScrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _SectionCard(
                      icon: Icons.edit_note_rounded,
                      title: 'Trip Details',
                      children: [
                        _FieldLabel('Trip Name *'),
                        _InputBox(
                          controller: _nameController,
                          icon: Icons.edit_rounded,
                          hintText: 'e.g. Penang Adventure',
                          validator: _validateName,
                          fieldKey: _nameFieldKey,
                          autovalidateMode: _hasTriedSubmitting
                              ? AutovalidateMode.always
                              : AutovalidateMode.onUserInteraction,
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
                        _FieldLabel('Starting From *'),
                        FormField<_City>(
                          key: _startCityFieldKey,
                          initialValue: _startCity,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) =>
                              value == null ? 'Choose a starting city' : null,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _CityField(
                                city: _startCity,
                                onTap: _pickStartCity,
                              ),
                              _FieldError(field.errorText),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('Ending At *'),
                        FormField<_City>(
                          key: _endCityFieldKey,
                          initialValue: _endCity,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) =>
                              value == null ? 'Choose an ending city' : null,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _CityField(city: _endCity, onTap: _pickEndCity),
                              _FieldError(field.errorText),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('Travel Dates & Time *'),
                        FormField<DateTimeRange>(
                          key: _dateRangeFieldKey,
                          initialValue: _dateRange,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (value) => value == null
                              ? 'Pick your travel dates and time'
                              : null,
                          builder: (field) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ScheduleField(
                                dateRange: _dateRange,
                                startTime: _startTime,
                                endTime: _endTime,
                                onTap: _pickDatesAndTimes,
                              ),
                              _FieldError(field.errorText),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        _FieldLabel('Budget *'),
                        _InputBox(
                          controller: _budgetController,
                          icon: Icons.account_balance_wallet_rounded,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          prefixText: 'RM ',
                          validator: _validateBudget,
                          fieldKey: _budgetFieldKey,
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
                          'Search or tap a pin to pick your stops.',
                          style: TextStyle(
                            color: context.colors.muted,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        LocationMapPicker(
                          selected: _selectedPlaces,
                          onToggle: _togglePlace,
                          onAddCustom: () {},
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
                                    const SizedBox(width: 4),
                                    GestureDetector(
                                      onTap: () => _togglePlace(place),
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
                        FormField<bool>(
                          key: _locationsFieldKey,
                          initialValue:
                              _selectedPlaces.isNotEmpty || _autoRecommend,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          validator: (ok) => ok == true
                              ? null
                              : 'No locations selected — enable '
                                    '"Auto-recommend more places", or pick at '
                                    'least one location.',
                          builder: (field) => _FieldError(field.errorText),
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
                              onChanged: (v) {
                                setState(() => _autoRecommend = v);
                                _locationsFieldKey.currentState?.didChange(
                                  _selectedPlaces.isNotEmpty || v,
                                );
                              },
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
                                      children: _interestOptions.map((opt) {
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
                      label: 'Plan My Trip',
                      icon: Icons.route_rounded,
                      loading: _isSubmitting,
                      onPressed: _canSubmit ? _submit : () {},
                    ),
                  ],
                ),
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

/// Inline validation-error text for a [FormField] — matches
/// [TextFormField]'s own error styling, for the custom picker fields
/// (Starting From, Ending At, Travel Dates & Time, Locations) that can't
/// use [TextFormField] directly. Renders nothing while [message] is null.
class _FieldError extends StatelessWidget {
  const _FieldError(this.message);

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.redAccent,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
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
    this.hintText,
    this.prefixText,
    this.inputFormatters,
    this.validator,
    this.fieldKey,
    this.autovalidateMode = AutovalidateMode.onUserInteraction,
  });

  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? hintText;

  /// Static, non-editable text shown inline before the value (e.g. "RM ")
  /// — part of the field's chrome, not something the traveler types.
  final String? prefixText;
  final List<TextInputFormatter>? inputFormatters;

  /// When set, wires this field into the ambient [Form] — validated on
  /// submit and live once the traveler has interacted with it.
  final String? Function(String?)? validator;

  /// Key on the underlying [TextFormField] itself (not this wrapper) — lets
  /// a caller reach its [FormFieldState] directly, e.g. to check
  /// [FormFieldState.hasError] or scroll it into view.
  final Key? fieldKey;
  final AutovalidateMode autovalidateMode;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      validator: validator,
      autovalidateMode: autovalidateMode,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(
          color: context.colors.muted,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: maxLines == 1
            ? Icon(icon, color: context.colors.muted, size: 20)
            : null,
        prefixText: prefixText,
        prefixStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: context.colors.ink,
        ),
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
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

  final _City? city;
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

/// Searchable bottom sheet listing Malaysian cities from [_dummyCities],
/// filtered as the user types. Returns the tapped [_City] via
/// `Navigator.pop`.
class _CityPickerSheet extends StatefulWidget {
  const _CityPickerSheet();

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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                child: Builder(
                  builder: (context) {
                    final q = _query.trim().toLowerCase();
                    final filtered = q.isEmpty
                        ? _dummyCities
                        : _dummyCities
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
                        ? 'Select travel dates'
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
    required this.blockedRanges,
  });

  final DateTimeRange? initialRange;
  final TimeOfDay initialStartTime;
  final TimeOfDay initialEndTime;

  /// Date ranges already claimed by another trip the traveler belongs to
  /// — the picked range must not overlap any of these.
  final List<({DateTimeRange range, String tripName})> blockedRanges;

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
    final initialRange = widget.initialRange;
    if (initialRange != null) {
      _start = initialRange.start;
      _end = initialRange.end;
    } else {
      // Default to a 3-day trip starting today, nudged forward day by day
      // until it lands somewhere that doesn't clash with another trip.
      var start = _today;
      var end = _today.add(const Duration(days: 2));
      var guard = 0;
      while (_blockingConflict(start, end, widget.blockedRanges) != null &&
          guard < 365) {
        start = start.add(const Duration(days: 1));
        end = end.add(const Duration(days: 1));
        guard++;
      }
      _start = start;
      _end = end;
    }
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
                        'Travel Dates & Time',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _confirm,
                      child: const Text(
                        'Done',
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
                    _SheetSectionLabel('Travel Dates'),
                    _RangeCalendar(
                      start: _start,
                      end: _end,
                      firstDate: _today,
                      lastDate: lastDate,
                      blockedRanges: widget.blockedRanges,
                      onChanged: (start, end) => setState(() {
                        _start = start;
                        _end = end;
                        _clampEndTime();
                      }),
                    ),
                    if (widget.blockedRanges.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Builder(
                              builder: (context) => Text(
                                'Dates already taken by another of your trips',
                                style: TextStyle(
                                  color: context.colors.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SheetSectionLabel('Start Time'),
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
                              _SheetSectionLabel('End Time'),
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
    required this.blockedRanges,
    required this.onChanged,
  });

  final DateTime start;
  final DateTime end;
  final DateTime firstDate;
  final DateTime lastDate;
  final List<({DateTimeRange range, String tripName})> blockedRanges;
  final void Function(DateTime start, DateTime end) onChanged;

  @override
  State<_RangeCalendar> createState() => _RangeCalendarState();
}

class _RangeCalendarState extends State<_RangeCalendar> {
  late DateTime _displayedMonth = DateTime(
    widget.start.year,
    widget.start.month,
  );

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
    final DateTime newStart;
    final DateTime newEnd;
    if (hasCompleteRange || day.isBefore(widget.start)) {
      newStart = day;
      newEnd = day;
    } else {
      newStart = widget.start;
      newEnd = day;
    }

    final conflict = _blockingConflict(newStart, newEnd, widget.blockedRanges);
    if (conflict != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            'These dates clash with "${conflict.tripName}" '
            '(${_formatDateRange(conflict.range)}).',
          ),
        ),
      );
      return;
    }
    widget.onChanged(newStart, newEnd);
  }

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(
      _displayedMonth.year,
      _displayedMonth.month,
      1,
    );
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
                    // Still tappable (unlike `disabled`), so tapping one
                    // surfaces the "clashes with another trip" message from
                    // `_onDayTap` instead of doing nothing.
                    final blocked =
                        !disabled &&
                        _blockingConflict(day, day, widget.blockedRanges) !=
                            null;
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
                          decoration: blocked
                              ? BoxDecoration(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                )
                              : inRange && !disabled
                              ? BoxDecoration(
                                  color: AppColors.accent.withValues(
                                    alpha: 0.18,
                                  ),
                                )
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
                                        : blocked
                                        ? Colors.redAccent.withValues(
                                            alpha: 0.85,
                                          )
                                        : context.colors.ink,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                    decoration: blocked
                                        ? TextDecoration.lineThrough
                                        : null,
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
