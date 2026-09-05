import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/nearby_place.dart';
import '../services/google_places_service.dart';
import '../services/locale_service.dart';
import '../services/search_history_service.dart';
import '../theme/app_theme.dart';
import 'explore/explore_place_details_screen.dart';

const _debounceDuration = Duration(milliseconds: 400);

class SearchDestinationScreen extends StatefulWidget {
  const SearchDestinationScreen({super.key});

  @override
  State<SearchDestinationScreen> createState() =>
      _SearchDestinationScreenState();
}

class _SearchDestinationScreenState extends State<SearchDestinationScreen> {
  final _controller = TextEditingController();
  final _placesService = GooglePlacesService();
  final _historyService = SearchHistoryService();
  Timer? _debounce;

  String _query = '';
  List<NearbyPlace> _results = const [];
  bool _searching = false;
  String? _error;
  bool _hasSearched = false;

  List<String> _recentSearches = const [];

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final uid = _uid;
    if (uid == null) return;
    final recent = await _historyService.recentSearches(uid);
    if (!mounted) return;
    setState(() => _recentSearches = recent);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    setState(() => _query = value);
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
      final results = await _placesService.textSearch(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
        _error = null;
        _hasSearched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _error =
            'Could not search destinations. Check your connection and try again.';
        _hasSearched = true;
      });
    }
  }

  void _selectRecent(String query) {
    _controller.text = query;
    _onQueryChanged(query);
  }

  Future<void> _selectPlace(NearbyPlace place) async {
    final uid = _uid;
    if (uid != null) {
      await _historyService.recordSearch(uid, place.name);
      if (mounted) await _loadRecentSearches();
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ExplorePlaceDetailsScreen(place: place),
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
            Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 20, 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: context.colors.ink,
                      size: 20,
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: context.colors.card,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            color: context.colors.muted,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              autofocus: true,
                              onChanged: _onQueryChanged,
                              style: TextStyle(
                                color: context.colors.ink,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                hintText: tr('home_search_destinations_hint'),
                                hintStyle: TextStyle(
                                  color: context.colors.muted,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            ),
                          ),
                          if (_searching)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _debounce?.cancel();
                                _controller.clear();
                                setState(() {
                                  _query = '';
                                  _results = const [];
                                  _error = null;
                                  _hasSearched = false;
                                });
                              },
                              child: Icon(
                                Icons.close_rounded,
                                color: context.colors.muted,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_query.isEmpty) {
      return ListView(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Text(
            'Recent Searches',
            style: TextStyle(
              color: context.colors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          SizedBox(height: 12),
          if (_recentSearches.isEmpty)
            Text(
              'No recent searches yet.',
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            )
          else
            ..._recentSearches.map(
              (r) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.history_rounded,
                  color: context.colors.muted,
                ),
                title: Text(
                  r,
                  style: TextStyle(color: context.colors.ink, fontSize: 13.5),
                ),
                trailing: Icon(
                  Icons.north_west_rounded,
                  color: context.colors.muted,
                  size: 16,
                ),
                onTap: () => _selectRecent(r),
              ),
            ),
        ],
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: context.colors.muted,
                size: 28,
              ),
              SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.muted, fontSize: 12.5),
              ),
              SizedBox(height: 8),
              TextButton(
                onPressed: () => _search(_query.trim()),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasSearched && _results.isEmpty) {
      return Center(
        child: Text(
          'No destinations found',
          style: TextStyle(color: context.colors.muted),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: _results
          .map((p) => _ResultTile(place: p, onTap: () => _selectPlace(p)))
          .toList(),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.place, required this.onTap});

  final NearbyPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(bottom: 10),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: AppColors.horizon),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(place.icon, color: Colors.white, size: 20),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      place.address,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.north_west_rounded,
                color: context.colors.muted,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
