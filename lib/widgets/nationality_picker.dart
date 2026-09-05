import 'package:flutter/material.dart';

import '../data/countries.dart';
import '../services/locale_service.dart';
import '../theme/app_theme.dart';

class NationalityPicker extends StatelessWidget {
  const NationalityPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<Country> onChanged;

  Country? get _selectedCountry {
    if (selected == null || selected!.isEmpty) return null;
    for (final c in countries) {
      if (c.name == selected) return c;
    }
    return null;
  }

  Future<void> _openPicker(BuildContext context) async {
    final result = await showModalBottomSheet<Country>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NationalityPickerSheet(),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final country = _selectedCountry;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openPicker(context),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.flag_outlined, color: context.colors.muted, size: 20),
            SizedBox(width: 12),
            if (country != null) ...[
              Text(country.flag, style: const TextStyle(fontSize: 18)),
              SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                country?.name ?? tr('auth_nationality'),
                style: TextStyle(
                  color: country != null
                      ? context.colors.ink
                      : context.colors.muted.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 20,
              color: context.colors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _NationalityPickerSheet extends StatefulWidget {
  const _NationalityPickerSheet();

  @override
  State<_NationalityPickerSheet> createState() =>
      _NationalityPickerSheetState();
}

class _NationalityPickerSheetState extends State<_NationalityPickerSheet> {
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
          : countries.where((c) => c.name.toLowerCase().contains(q)).toList();
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
                    hintText: tr('common_search_country'),
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
