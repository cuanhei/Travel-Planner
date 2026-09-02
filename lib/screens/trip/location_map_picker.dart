import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/map_grid_painter.dart';
import '../../widgets/map_label_pill.dart';
import '../explore/explore_tab.dart' show Place, places;

/// UI-only "map" for picking trip locations: no map SDK or geocoding
/// API — known places are shown as pins at fixed positions over a
/// stylized grid. An optional built-in search bar lets the traveler
/// look up a known place (jumps straight to a pin) or type any other
/// name to drop a custom pin at a deterministic spot on the map.
class LocationMapPicker extends StatefulWidget {
  const LocationMapPicker({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.onAddCustom,
    this.visiblePlaces,
    this.showSearch = true,
  });

  final Set<Place> selected;
  final ValueChanged<Place> onToggle;
  final VoidCallback onAddCustom;

  /// Places shown as pins, e.g. filtered by a search query. Defaults to
  /// every known place.
  final List<Place>? visiblePlaces;

  /// Whether to render the built-in search bar. Screens that already
  /// drive [visiblePlaces] with their own external search field (e.g.
  /// the stop editor) should set this to false to avoid a duplicate.
  final bool showSearch;

  static const _coords = <String, (double top, double left)>{
    'Penang Hill': (0.60, 0.20),
    'Batu Ferringhi': (0.10, 0.60),
    'Chew Jetty': (0.30, 0.86),
    'The Top Komtar': (0.46, 0.66),
    'Gurney Drive Hawker Centre': (0.18, 0.80),
    'Upside Down Museum': (0.58, 0.82),
  };

  /// Resolves a pin position: known places use a hand-placed spot,
  /// anything else (custom / searched-in stops) gets a deterministic
  /// spread based on its name so it still lands somewhere sensible and
  /// stable across rebuilds.
  static (double top, double left) coordFor(Place place) {
    final fixed = _coords[place.name];
    if (fixed != null) return fixed;
    final hash = place.name.toLowerCase().hashCode.abs();
    final top = 0.16 + (hash % 71) / 100;
    final left = 0.12 + ((hash ~/ 71) % 77) / 100;
    return (top, left);
  }

  @override
  State<LocationMapPicker> createState() => _LocationMapPickerState();
}

class _LocationMapPickerState extends State<LocationMapPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Place> get _catalog => widget.visiblePlaces ?? places;

  List<Place> get _matches {
    if (_query.isEmpty) return const [];
    final q = _query.toLowerCase();
    return _catalog.where((p) => p.name.toLowerCase().contains(q)).take(4).toList();
  }

  bool get _hasExactMatch =>
      _catalog.any((p) => p.name.toLowerCase() == _query.trim().toLowerCase());

  void _pickPlace(Place place) {
    if (!widget.selected.contains(place)) widget.onToggle(place);
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() => _query = '');
  }

  void _addSearchedPlace() {
    final name = _query.trim();
    if (name.isEmpty) return;
    _pickPlace(buildCustomPlace(name));
  }

  @override
  Widget build(BuildContext context) {
    final shownPlaces = <Place>{..._catalog, ...widget.selected}.toList();
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 236,
        color: const Color(0xFFE4E9F2),
        child: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: MapGridPainter()),
            ),
            ...shownPlaces.map((place) {
              final coord = LocationMapPicker.coordFor(place);
              final isSelected = widget.selected.contains(place);
              return Align(
                alignment: Alignment(coord.$2 * 2 - 1, coord.$1 * 2 - 1),
                child: GestureDetector(
                  onTap: () => widget.onToggle(place),
                  child: _MapPinButton(place: place, selected: isSelected),
                ),
              );
            }),
            if (!widget.showSearch)
              Positioned(
                left: 10,
                top: 10,
                child: MapLabelPill(
                  text: shownPlaces.isEmpty
                      ? tr('trip_map_no_matches')
                      : tr('trip_map_tap_pins'),
                ),
              ),
            if (widget.showSearch)
              Positioned(
                left: 10,
                right: 10,
                top: 10,
                child: _SearchField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) {
                    if (_matches.isNotEmpty) {
                      _pickPlace(_matches.first);
                    } else {
                      _addSearchedPlace();
                    }
                  },
                ),
              ),
            if (widget.showSearch && _query.isNotEmpty)
              Positioned(
                left: 10,
                right: 10,
                top: 58,
                child: _SearchResults(
                  matches: _matches,
                  query: _query,
                  hasExactMatch: _hasExactMatch,
                  onPick: _pickPlace,
                  onAddCustom: _addSearchedPlace,
                ),
              ),
            if (!widget.showSearch)
              Positioned(
                right: 10,
                bottom: 10,
                child: Material(
                  color: context.colors.ink,
                  shape: const CircleBorder(),
                  elevation: 3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: widget.onAddCustom,
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon(
                        Icons.add_location_alt_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: Color(0xFF6E7A93),
              size: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                textInputAction: TextInputAction.search,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  hintText: tr('trip_map_search_hint'),
                  hintStyle: const TextStyle(
                    color: Color(0xFF6E7A93),
                    fontWeight: FontWeight.w500,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                child: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFF6E7A93),
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.matches,
    required this.query,
    required this.hasExactMatch,
    required this.onPick,
    required this.onAddCustom,
  });

  final List<Place> matches;
  final String query;
  final bool hasExactMatch;
  final ValueChanged<Place> onPick;
  final VoidCallback onAddCustom;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 190),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          children: [
            for (final place in matches)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: Icon(
                  place.icon,
                  size: 18,
                  color: const Color(0xFF11998E),
                ),
                title: Text(
                  place.name,
                  style: const TextStyle(
                    color: Color(0xFF0B1D3A),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  place.area,
                  style: const TextStyle(
                    color: Color(0xFF6E7A93),
                    fontSize: 11,
                  ),
                ),
                trailing: const Icon(
                  Icons.add_location_alt_outlined,
                  size: 16,
                  color: Color(0xFF6E7A93),
                ),
                onTap: () => onPick(place),
              ),
            if (!hasExactMatch)
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(
                  Icons.add_location_alt_rounded,
                  size: 18,
                  color: Color(0xFFFF7A59),
                ),
                title: Text(
                  '${tr('trip_map_drop_pin_for')} "${query.trim()}"',
                  style: const TextStyle(
                    color: Color(0xFF0B1D3A),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  tr('trip_map_add_custom_stop'),
                  style: const TextStyle(color: Color(0xFF6E7A93), fontSize: 11),
                ),
                onTap: onAddCustom,
              ),
          ],
        ),
      ),
    );
  }
}

class _MapPinButton extends StatelessWidget {
  const _MapPinButton({required this.place, required this.selected});

  final Place place;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            selected ? Icons.check_circle_rounded : Icons.location_on_rounded,
            color: selected ? const Color(0xFF11998E) : const Color(0xFF0B1D3A),
            size: selected ? 26 : 30,
          ),
        ),
      ],
    );
  }
}

/// Builds a synthetic [Place] for a custom, non-catalog stop.
Place buildCustomPlace(String name) {
  return Place(
    name: name,
    area: tr('trip_custom_location_area'),
    category: 'Custom',
    rating: 0,
    reviews: 0,
    gradient: AppColors.dusk,
    icon: Icons.location_pin,
    description: 'A custom stop you added yourself.',
    avgBudget: 'Varies',
    distanceKm: 5,
  );
}

/// Prompts for a custom location name and returns a synthetic [Place].
Future<Place?> showAddCustomLocationDialog(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<Place>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('trip_add_location_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: dialogContext.colors.ink),
          decoration: InputDecoration(
            hintText: tr('trip_add_location_hint'),
            hintStyle: TextStyle(color: dialogContext.colors.muted),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr('trip_cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.of(dialogContext).pop(buildCustomPlace(name));
            },
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.colors.ink,
            ),
            child: Text(tr('trip_add_button')),
          ),
        ],
      );
    },
  );
}
