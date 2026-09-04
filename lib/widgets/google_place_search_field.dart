import 'dart:async';

import 'package:flutter/material.dart';

import '../models/trip_stop_location.dart';
import '../services/google_places_service.dart';
import 'location_search_field.dart';

const _searchDebounce = Duration(milliseconds: 400);

/// Search-as-you-type field for picking a place via Google Places Text
/// Search — same 46px white pill chrome and [LocationResultsDropdown] as
/// the shared Photon-backed [LocationSearchField], but never shows a
/// "selected" read-only state: picking a result immediately calls
/// [onChanged] with the converted [TripStopLocation] (see
/// [TripStopLocation.fromNearbyPlace]) and clears back to an empty
/// search box, leaving it to the caller to decide what "selecting" means
/// (Create Trip's stop picker stages it as a pending map pin; the
/// accommodation picker treats it as the chosen hotel directly).
class GooglePlaceSearchField extends StatefulWidget {
  const GooglePlaceSearchField({
    super.key,
    required this.onChanged,
    this.isResultDisabled,
    this.hintText = 'Search for a place…',
    this.includedType,
    this.strictTypeFiltering = false,
  });

  final ValueChanged<TripStopLocation> onChanged;
  final bool Function(TripStopLocation)? isResultDisabled;
  final String hintText;

  /// Restricts results to one Places "Table A" type (e.g. `'lodging'`)
  /// — see [GooglePlacesService.textSearch]. Null means unrestricted.
  final String? includedType;
  final bool strictTypeFiltering;

  @override
  State<GooglePlaceSearchField> createState() =>
      _GooglePlaceSearchFieldState();
}

class _GooglePlaceSearchFieldState extends State<GooglePlaceSearchField> {
  final _placesService = GooglePlacesService();
  final _controller = TextEditingController();
  Timer? _debounce;

  List<TripStopLocation> _results = const [];
  bool _searching = false;
  String? _error;
  bool _hasSearched = false;

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
    _debounce = Timer(_searchDebounce, () => _search(trimmed));
  }

  Future<void> _search(String query) async {
    try {
      final places = await _placesService.textSearch(
        query,
        includedType: widget.includedType,
        strictTypeFiltering: widget.strictTypeFiltering,
      );
      if (!mounted) return;
      setState(() {
        _results = [
          for (final p in places) TripStopLocation.fromNearbyPlace(p),
        ];
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
            'Could not search places. Check your connection and try again.';
        _hasSearched = true;
      });
    }
  }

  void _select(TripStopLocation stop) {
    FocusScope.of(context).unfocus();
    _debounce?.cancel();
    _controller.clear();
    setState(() {
      _results = const [];
      _error = null;
      _hasSearched = false;
      _searching = false;
    });
    widget.onChanged(stop);
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
  }

  bool get _showDropdown => _searching || _hasSearched || _error != null;

  @override
  Widget build(BuildContext context) {
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
                const Icon(
                  Icons.search_rounded,
                  color: Color(0xFF6E7A93),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onChanged: _onQueryChanged,
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
                if (_searching)
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
            maxHeight: 220,
            emptyText: 'No places found',
            isResultDisabled: widget.isResultDisabled,
            onPick: _select,
          ),
        ],
      ],
    );
  }
}
