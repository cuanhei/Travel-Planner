import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trip_stop_location.dart';
import '../services/photon_service.dart';

const _debounceDuration = Duration(milliseconds: 400);

/// Controlled search-as-you-type field for picking a Malaysia-only place
/// via Photon geocoding — autocomplete dropdown, loading/empty/error
/// states, and a read-only display once a location is selected. The one
/// shared search UI + service for every Photon-backed location picker in
/// the app (Transport's "Depart From"/"Destination", the Trip Map
/// picker's search bar); the parent owns [value] and decides what
/// "selecting" means — e.g. [TripLocationPicker] always passes `value:
/// null` and stages its own pending-stop UI outside this widget entirely,
/// rather than ever marking a result "selected" here.
class LocationSearchField extends StatefulWidget {
  const LocationSearchField({
    super.key,
    required this.value,
    required this.onChanged,
    this.hintText = 'Search a location…',
    this.selectedIcon = Icons.location_on_rounded,
    this.maxDropdownHeight = 220,
    this.helperText,
    this.externalLoading = false,
    this.quickActionLabel,
    this.quickActionIcon = Icons.my_location_rounded,
    this.onQuickAction,
    this.isResultDisabled,
    this.emptyResultsText = 'No results found',
  });

  /// The currently selected location, owned by the parent. When non-null
  /// the field shows it read-only; when null the field is an editable
  /// search box.
  final TripStopLocation? value;

  /// Called with the picked location, or null when the selection is
  /// cleared.
  final ValueChanged<TripStopLocation?> onChanged;
  final String hintText;
  final IconData selectedIcon;
  final double maxDropdownHeight;

  /// Small message shown under the field when there's no selection and
  /// no query typed — e.g. a GPS-lookup failure explaining why the field
  /// is empty and inviting a manual search.
  final String? helperText;

  /// True while the parent is resolving a location on the field's
  /// behalf (e.g. fetching GPS) — shows the same loading affordance as
  /// an in-flight search and disables input meanwhile.
  final bool externalLoading;

  /// Label for an optional quick-select row shown whenever the field is
  /// empty and idle (no selection, no query typed) — e.g. "Use current
  /// location". Null hides the row.
  final String? quickActionLabel;
  final IconData quickActionIcon;
  final VoidCallback? onQuickAction;

  /// Marks a result as already picked elsewhere (e.g. already added to
  /// the trip) — shown with a checkmark instead of being tappable. Null
  /// means no result is ever disabled.
  final bool Function(TripStopLocation)? isResultDisabled;

  final String emptyResultsText;

  @override
  State<LocationSearchField> createState() => _LocationSearchFieldState();
}

class _LocationSearchFieldState extends State<LocationSearchField> {
  final _photon = PhotonService();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<TripStopLocation> _results = const [];
  bool _searching = false;
  String? _error;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value?.name ?? '';
  }

  @override
  void didUpdateWidget(covariant LocationSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _controller.text = widget.value?.name ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
        _error = null;
        _hasSearched = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(_debounceDuration, () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    try {
      final results = await _photon.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        _error = null;
        _hasSearched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _error =
            'Could not search locations. Check your connection and try again.';
        _hasSearched = true;
      });
    }
  }

  void _select(TripStopLocation location) {
    FocusScope.of(context).unfocus();
    setState(() {
      _results = const [];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
    widget.onChanged(location);
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _results = const [];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
    widget.onChanged(null);
  }

  bool get _loading => _searching || widget.externalLoading;

  bool get _showDropdown =>
      widget.value == null &&
      !widget.externalLoading &&
      (_searching || _hasSearched || _error != null);

  @override
  Widget build(BuildContext context) {
    final selected = widget.value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          elevation: 3,
          shadowColor: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? widget.selectedIcon : Icons.search_rounded,
                  color: const Color(0xFF6E7A93),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _onQueryChanged,
                    readOnly: selected || widget.externalLoading,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(
                      color: Color(0xFF0B1D3A),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(
                        color: Color(0xFF6E7A93),
                        fontWeight: FontWeight.w500,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: _clear,
                    child: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF6E7A93),
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_showDropdown) ...[
          const SizedBox(height: 8),
          LocationResultsDropdown(
            loading: _searching,
            error: _error,
            results: _results,
            maxHeight: widget.maxDropdownHeight,
            emptyText: widget.emptyResultsText,
            isResultDisabled: widget.isResultDisabled,
            onPick: _select,
          ),
        ] else if (!selected &&
            !widget.externalLoading &&
            _controller.text.isEmpty) ...[
          if (widget.quickActionLabel != null &&
              widget.onQuickAction != null) ...[
            const SizedBox(height: 8),
            _QuickActionRow(
              label: widget.quickActionLabel!,
              icon: widget.quickActionIcon,
              onTap: widget.onQuickAction!,
            ),
          ],
          if (widget.helperText != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                widget.helperText!,
                style: const TextStyle(color: Color(0xFFB3541E), fontSize: 11.5),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFF11998E)),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF0B1D3A),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared results-list chrome for a [TripStopLocation] search dropdown —
/// used by [LocationSearchField] itself (Photon-backed) and reused as-is
/// by Create Trip's Google-Places-backed stop picker, so both search
/// experiences look identical regardless of which backend found the
/// results.
class LocationResultsDropdown extends StatelessWidget {
  const LocationResultsDropdown({
    super.key,
    required this.loading,
    required this.error,
    required this.results,
    required this.maxHeight,
    required this.emptyText,
    required this.isResultDisabled,
    required this.onPick,
  });

  final bool loading;
  final String? error;
  final List<TripStopLocation> results;
  final double maxHeight;
  final String emptyText;
  final bool Function(TripStopLocation)? isResultDisabled;
  final ValueChanged<TripStopLocation> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFE05A5A),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error!,
                style: const TextStyle(color: Color(0xFF6E7A93), fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          emptyText,
          style: const TextStyle(color: Color(0xFF6E7A93), fontSize: 12.5),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        final disabled = isResultDisabled?.call(r) ?? false;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Icon(r.categoryIcon, size: 18, color: const Color(0xFF11998E)),
          title: Text(
            r.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0B1D3A),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          subtitle: Text(
            r.address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF6E7A93), fontSize: 11),
          ),
          trailing: disabled
              ? const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Color(0xFF11998E),
                )
              : null,
          onTap: disabled ? null : () => onPick(r),
        );
      },
    );
  }
}
