import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';
import 'explore/explore_tab.dart';
import 'explore/place_details_screen.dart';

/// UI-only destination search with recent searches and live filtering
/// over the dummy places list.
class SearchDestinationScreen extends StatefulWidget {
  const SearchDestinationScreen({super.key});

  @override
  State<SearchDestinationScreen> createState() =>
      _SearchDestinationScreenState();
}

class _SearchDestinationScreenState extends State<SearchDestinationScreen> {
  final _controller = TextEditingController();
  late final _recent = [
    tr('home_recent_gurney_drive'),
    tr('home_destination_penang_hill'),
    tr('home_recent_komtar'),
  ];
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.isEmpty
        ? <Place>[]
        : places
              .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();

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
                              onChanged: (v) => setState(() => _query = v),
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
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() {
                                _controller.clear();
                                _query = '';
                              }),
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
            Expanded(
              child: _query.isEmpty
                  ? ListView(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      children: [
                        Text(
                          tr('home_recent_searches'),
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 12),
                        ..._recent.map(
                          (r) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              Icons.history_rounded,
                              color: context.colors.muted,
                            ),
                            title: Text(
                              r,
                              style: TextStyle(
                                color: context.colors.ink,
                                fontSize: 13.5,
                              ),
                            ),
                            trailing: Icon(
                              Icons.north_west_rounded,
                              color: context.colors.muted,
                              size: 16,
                            ),
                            onTap: () => setState(() {
                              _controller.text = r;
                              _query = r;
                            }),
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          tr('home_popular_right_now'),
                          style: TextStyle(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 12),
                        ...places.take(3).map((p) => _ResultTile(place: p)),
                      ],
                    )
                  : results.isEmpty
                  ? Center(
                      child: Text(
                        tr('home_no_destinations_found'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      children: results
                          .map((p) => _ResultTile(place: p))
                          .toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PlaceDetailsScreen(place: place)),
        ),
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
                  gradient: LinearGradient(colors: place.gradient),
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
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    Text(
                      place.area,
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
