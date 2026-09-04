import 'package:flutter/material.dart';

import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'packing_item_form_screen.dart';

/// A single packing checklist entry. Mutable `packed` flag so tapping
/// the checkbox can toggle it in place — UI-only, no persistence.
class PackingItem {
  PackingItem({
    required this.id,
    required this.label,
    required this.category,
    this.packed = false,
  });

  final int id;
  final String label;
  final String category;
  bool packed;
}

/// Common category suggestions offered when adding an item, alongside
/// whatever custom categories the traveler has already typed in.
const packingCategorySuggestions = [
  'Clothing',
  'Toiletries',
  'Electronics',
  'Documents',
];

const _categoryTranslationKeys = {
  'Clothing': 'utilities_category_clothing',
  'Toiletries': 'utilities_category_toiletries',
  'Electronics': 'utilities_category_electronics',
  'Documents': 'utilities_category_documents',
};

/// Translates a fixed packing category label; a custom category a
/// traveler typed in has no fixed-language key, so it's shown exactly
/// as entered.
String translatedPackingCategory(String label) {
  final key = _categoryTranslationKeys[label];
  return key == null ? label : tr(key);
}

/// Packing checklist grouped by category — add, edit, or remove items,
/// and check them off as they're packed.
class PackingListScreen extends StatefulWidget {
  const PackingListScreen({super.key});

  @override
  State<PackingListScreen> createState() => _PackingListScreenState();
}

class _PackingListScreenState extends State<PackingListScreen> {
  final _items = [
    PackingItem(id: 1, label: tr('utilities_item_light_shirts_shorts'), category: 'Clothing', packed: true),
    PackingItem(id: 2, label: tr('utilities_item_swimwear'), category: 'Clothing', packed: true),
    PackingItem(id: 3, label: tr('utilities_item_walking_shoes'), category: 'Clothing'),
    PackingItem(id: 4, label: tr('utilities_item_rain_jacket'), category: 'Clothing'),
    PackingItem(id: 5, label: tr('utilities_item_sunscreen'), category: 'Toiletries', packed: true),
    PackingItem(id: 6, label: tr('utilities_item_toothbrush'), category: 'Toiletries'),
    PackingItem(id: 7, label: tr('utilities_item_insect_repellent'), category: 'Toiletries'),
    PackingItem(id: 8, label: tr('utilities_item_phone_charger'), category: 'Electronics', packed: true),
    PackingItem(id: 9, label: tr('utilities_item_power_bank'), category: 'Electronics'),
    PackingItem(id: 10, label: tr('utilities_item_universal_adapter'), category: 'Electronics'),
    PackingItem(id: 11, label: tr('utilities_item_camera'), category: 'Electronics'),
    PackingItem(id: 12, label: tr('utilities_item_passport_ic'), category: 'Documents', packed: true),
    PackingItem(id: 13, label: tr('utilities_item_hotel_booking'), category: 'Documents'),
    PackingItem(id: 14, label: tr('utilities_item_travel_insurance'), category: 'Documents'),
  ];

  List<String> get _existingCategories =>
      {for (final i in _items) i.category}.toList();

  Future<void> _addItem() async {
    final result = await Navigator.of(context).push<PackingItemFormResult>(
      MaterialPageRoute(
        builder: (_) =>
            PackingItemFormScreen(existingCategories: _existingCategories),
      ),
    );
    if (result == null || result.deleted) return;
    setState(() => _items.add(result.item!));
  }

  Future<void> _editItem(PackingItem item) async {
    final result = await Navigator.of(context).push<PackingItemFormResult>(
      MaterialPageRoute(
        builder: (_) => PackingItemFormScreen(
          initial: item,
          existingCategories: _existingCategories,
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.deleted) {
        _items.removeWhere((i) => i.id == item.id);
      } else {
        final index = _items.indexWhere((i) => i.id == item.id);
        _items[index] = result.item!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final packedCount = _items.where((i) => i.packed).length;
    final grouped = <String, List<PackingItem>>{};
    for (final item in _items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('utilities_packing_list_title'),
              subtitle: '$packedCount ${tr('utilities_of')} ${_items.length} ${tr('utilities_packed')}',
              trailing: IconButton(
                onPressed: _addItem,
                icon: Icon(Icons.add_rounded, color: context.colors.ink),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _items.isEmpty ? 0 : packedCount / _items.length,
                  minHeight: 8,
                  backgroundColor: context.colors.card,
                  valueColor: AlwaysStoppedAnimation(Color(0xFF11998E)),
                ),
              ),
            ),
            Expanded(
              child: _items.isEmpty
                  ? _EmptyState(onAdd: _addItem)
                  : ListView(
                      padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
                      children: grouped.entries.map((entry) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              translatedPackingCategory(entry.key),
                              style: TextStyle(
                                color: context.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                            SizedBox(height: 10),
                            ...entry.value.map(
                              (item) => Container(
                                margin: EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: context.colors.card,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: CheckboxListTile(
                                  value: item.packed,
                                  onChanged: (v) =>
                                      setState(() => item.packed = v ?? false),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  activeColor: Color(0xFF11998E),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  title: Text(
                                    item.label,
                                    style: TextStyle(
                                      color: item.packed
                                          ? context.colors.muted
                                          : context.colors.ink,
                                      decoration: item.packed
                                          ? TextDecoration.lineThrough
                                          : null,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                  secondary: GestureDetector(
                                    onTap: () => _editItem(item),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      size: 16,
                                      color: context.colors.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(height: 12),
                          ],
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.checklist_rounded, color: context.colors.muted, size: 44),
            const SizedBox(height: 16),
            Text(
              tr('utilities_empty_packing_title'),
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr('utilities_empty_packing_subtitle'),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            Material(
              color: context.colors.ink,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onAdd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        tr('utilities_add_item'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
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
