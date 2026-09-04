import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'explore_tab.dart';
import 'place_details_screen.dart';

/// Browse-by-interest grid; tapping a category filters the place list.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String? _selected;

  static final _colors = [
    Color(0xFFFF7A59),
    Color(0xFF11998E),
    Color(0xFF38EF7D),
    Color(0xFF5C6BC0),
    Color(0xFFFFB347),
    Color(0xFF8E63CE),
  ];

  @override
  Widget build(BuildContext context) {
    final results = _selected == null
        ? <Place>[]
        : places.where((p) => p.category == _selected).toList();

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('explore_categories_title'),
              subtitle: tr('explore_categories_subtitle'),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: GridView.builder(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemBuilder: (context, index) {
                  final c = categories[index];
                  final color = _colors[index % _colors.length];
                  final selected = _selected == c.label;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = c.label),
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: selected ? color : context.colors.card,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.ink.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            c.icon,
                            color: selected ? Colors.white : color,
                            size: 26,
                          ),
                          SizedBox(height: 8),
                          Flexible(
                            child: Text(
                              tr('explore_category_${c.label.toLowerCase()}'),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : context.colors.ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              child: results.isEmpty
                  ? Center(
                      child: Text(
                        tr('explore_pick_category'),
                        style: TextStyle(color: context.colors.muted),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final p = results[index];
                        return Material(
                          color: context.colors.card,
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlaceDetailsScreen(place: p),
                              ),
                            ),
                            child: Container(
                              margin: EdgeInsets.only(bottom: 12),
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.colors.ink.withValues(
                                      alpha: 0.05,
                                    ),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: p.gradient,
                                      ),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      p.icon,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      p.name,
                                      style: TextStyle(
                                        color: context.colors.ink,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: context.colors.muted,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
