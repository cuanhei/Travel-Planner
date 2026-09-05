import 'package:flutter/material.dart';

import '../../models/packing_item.dart';
import '../../models/trip.dart';
import '../../services/locale_service.dart';
import '../../services/packing_list_service.dart';
import '../../services/trip_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'packing_item_form_screen.dart';

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

String translatedPackingCategory(String label) {
  final key = _categoryTranslationKeys[label];
  return key == null ? label : tr(key);
}

class PackingListScreen extends StatefulWidget {
  const PackingListScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<PackingListScreen> createState() => _PackingListScreenState();
}

class _PackingListScreenState extends State<PackingListScreen> {
  final _service = PackingListService();
  final _tripService = TripService();

  late Stream<List<PackingItem>> _itemsStream;

  Trip? _trip;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _itemsStream = _service.watchItems(widget.tripId);
    _loadTrip();
  }

  void _retry() {
    setState(() => _itemsStream = _service.watchItems(widget.tripId));
  }

  Future<void> _loadTrip() async {
    try {
      final trip = await _tripService.getTrip(widget.tripId);
      if (mounted) setState(() => _trip = trip);
    } catch (_) {}
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
  }

  Future<void> _autoGenerate(List<PackingItem> currentItems) async {
    final trip = _trip;
    if (trip == null || _generating) return;
    setState(() => _generating = true);
    try {
      final added = await _service.generateSuggestedItems(trip, currentItems);
      _showMessage(
        added == 0
            ? tr('utilities_no_new_suggestions')
            : '$added ${tr('utilities_items_added_suffix')}',
      );
    } catch (e) {
      _showMessage('Could not generate suggestions: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _addItem(List<String> existingCategories) async {
    final result = await Navigator.of(context).push<PackingItemFormResult>(
      MaterialPageRoute(
        builder: (_) =>
            PackingItemFormScreen(existingCategories: existingCategories),
      ),
    );
    if (result == null || result.deleted) return;
    final draft = result.item!;
    try {
      await _service.addItem(
        tripId: widget.tripId,
        label: draft.label,
        category: draft.category,
        quantity: draft.quantity,
        note: draft.note,
        packed: draft.packed,
      );
    } catch (e) {
      _showMessage('Could not add item: $e');
    }
  }

  Future<void> _editItem(
    PackingItem item,
    List<String> existingCategories,
  ) async {
    final result = await Navigator.of(context).push<PackingItemFormResult>(
      MaterialPageRoute(
        builder: (_) => PackingItemFormScreen(
          initial: item,
          existingCategories: existingCategories,
        ),
      ),
    );
    if (result == null) return;
    try {
      if (result.deleted) {
        await _service.deleteItem(item.id);
      } else {
        final updated = result.item!;
        await _service.updateItem(
          item.id,
          label: updated.label,
          category: updated.category,
          quantity: updated.quantity,
          note: updated.note,
          packed: updated.packed,
        );
      }
    } catch (e) {
      _showMessage('Could not update item: $e');
    }
  }

  Future<void> _togglePacked(PackingItem item, bool packed) async {
    try {
      await _service.setPacked(item.id, packed);
    } catch (e) {
      _showMessage('Could not update item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: StreamBuilder<List<PackingItem>>(
          stream: _itemsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Column(
                children: [
                  DetailHeader(title: tr('utilities_packing_list_title')),
                  Expanded(
                    child: _ErrorState(error: snapshot.error!, onRetry: _retry),
                  ),
                ],
              );
            }
            final items = snapshot.data ?? const <PackingItem>[];
            final loading = !snapshot.hasData;
            final packedCount = items.where((i) => i.packed).length;
            final existingCategories = {
              for (final i in items) i.category,
            }.toList();
            final grouped = <String, List<PackingItem>>{};
            for (final item in items) {
              grouped.putIfAbsent(item.category, () => []).add(item);
            }

            return Column(
              children: [
                DetailHeader(
                  title: tr('utilities_packing_list_title'),
                  subtitle:
                      '$packedCount ${tr('utilities_of')} ${items.length} ${tr('utilities_packed')}',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_trip != null)
                        IconButton(
                          onPressed: _generating
                              ? null
                              : () => _autoGenerate(items),
                          tooltip: tr('utilities_auto_generate'),
                          icon: _generating
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.colors.ink,
                                  ),
                                )
                              : Icon(
                                  Icons.auto_awesome_rounded,
                                  color: context.colors.ink,
                                ),
                        ),
                      IconButton(
                        onPressed: () => _addItem(existingCategories),
                        icon: Icon(
                          Icons.add_rounded,
                          color: context.colors.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: items.isEmpty ? 0 : packedCount / items.length,
                      minHeight: 8,
                      backgroundColor: context.colors.card,
                      valueColor: AlwaysStoppedAnimation(Color(0xFF11998E)),
                    ),
                  ),
                ),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? _EmptyState(
                          onAdd: () => _addItem(existingCategories),
                          onAutoGenerate: _trip == null
                              ? null
                              : () => _autoGenerate(items),
                        )
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
                                  (item) => _PackingItemTile(
                                    item: item,
                                    onTogglePacked: (v) =>
                                        _togglePacked(item, v),
                                    onEdit: () =>
                                        _editItem(item, existingCategories),
                                  ),
                                ),
                                SizedBox(height: 12),
                              ],
                            );
                          }).toList(),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PackingItemTile extends StatelessWidget {
  const _PackingItemTile({
    required this.item,
    required this.onTogglePacked,
    required this.onEdit,
  });

  final PackingItem item;
  final ValueChanged<bool> onTogglePacked;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final note = item.note;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: CheckboxListTile(
        value: item.packed,
        onChanged: (v) => onTogglePacked(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: Color(0xFF11998E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Flexible(
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: item.packed
                      ? context.colors.muted
                      : context.colors.ink,
                  decoration: item.packed ? TextDecoration.lineThrough : null,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            if (item.quantity > 1) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '×${item.quantity}',
                  style: TextStyle(
                    color: context.colors.muted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: (note != null && note.isNotEmpty)
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  note,
                  style: TextStyle(color: context.colors.muted, fontSize: 11),
                ),
              )
            : null,
        secondary: GestureDetector(
          onTap: onEdit,
          child: Icon(
            Icons.edit_rounded,
            size: 16,
            color: context.colors.muted,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, this.onAutoGenerate});

  final VoidCallback onAdd;
  final VoidCallback? onAutoGenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.checklist_rounded,
              color: context.colors.muted,
              size: 44,
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.add_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
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
            if (onAutoGenerate != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onAutoGenerate,
                icon: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: context.colors.ink,
                ),
                label: Text(
                  tr('utilities_auto_generate'),
                  style: TextStyle(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: context.colors.muted,
              size: 44,
            ),
            const SizedBox(height: 16),
            Text(
              'Could not load your packing list',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: context.colors.ink,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.muted, fontSize: 12.5),
            ),
            const SizedBox(height: 20),
            Material(
              color: context.colors.ink,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onRetry,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Retry',
                        style: TextStyle(
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
