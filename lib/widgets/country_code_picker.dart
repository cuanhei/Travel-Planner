import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

class CountryCodePicker extends StatelessWidget {
  const CountryCodePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Country selected;
  final ValueChanged<Country> onChanged;

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CountryPickerSheet(),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _openPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(selected.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              selected.dialCode,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
                fontSize: 14,
              ),
            ),
            SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: context.colors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet();

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchController = TextEditingController();
  List<Country> _filtered = countries;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? countries
          : countries
                .where(
                  (c) =>
                      c.name.toLowerCase().contains(q) ||
                      c.dialCode.contains(q) ||
                      c.isoCode.toLowerCase().contains(q),
                )
                .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.colors.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
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
                  onChanged: _onSearchChanged,
                  style: TextStyle(color: context.colors.ink),
                  decoration: InputDecoration(
                    hintText: tr('common_search_country_or_code'),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: context.colors.muted,
                    ),
                    filled: true,
                    fillColor: context.colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Text(
                          tr('common_no_countries_found'),
                          style: TextStyle(color: context.colors.muted),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final country = _filtered[index];
                          return ListTile(
                            leading: Text(
                              country.flag,
                              style: const TextStyle(fontSize: 22),
                            ),
                            title: Text(
                              country.name,
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: Text(
                              country.dialCode,
                              style: TextStyle(
                                color: context.colors.muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(country),
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
