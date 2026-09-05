import 'package:flutter/material.dart';

import '../../models/packing_item.dart';
import '../../services/locale_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'packing_list_screen.dart';

/// Result of [PackingItemFormScreen]: either a saved (added/edited)
/// item, or a request to delete the item being edited.
class PackingItemFormResult {
  const PackingItemFormResult.save(PackingItem savedItem)
    : item = savedItem,
      deleted = false;
  const PackingItemFormResult.delete() : item = null, deleted = true;

  final PackingItem? item;
  final bool deleted;
}

/// UI-only form for adding a packing list item, or editing/deleting one
/// already on the list.
class PackingItemFormScreen extends StatefulWidget {
  const PackingItemFormScreen({
    super.key,
    this.initial,
    required this.existingCategories,
  });

  /// Item being edited, or null when adding a new one.
  final PackingItem? initial;

  /// Categories already in use elsewhere on the list, offered as quick
  /// picks alongside the built-in suggestions.
  final List<String> existingCategories;

  bool get isEditing => initial != null;

  @override
  State<PackingItemFormScreen> createState() => _PackingItemFormScreenState();
}

class _PackingItemFormScreenState extends State<PackingItemFormScreen> {
  late final _labelController = TextEditingController(
    text: widget.initial?.label ?? '',
  );
  late final _categoryController = TextEditingController(
    text: widget.initial?.category ?? '',
  );
  late final _noteController = TextEditingController(
    text: widget.initial?.note ?? '',
  );
  late bool _packed = widget.initial?.packed ?? false;
  late int _quantity = widget.initial?.quantity ?? 1;

  @override
  void dispose() {
    _labelController.dispose();
    _categoryController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<String> get _categoryOptions => {
    ...packingCategorySuggestions,
    ...widget.existingCategories,
  }.toList();

  bool get _canSave =>
      _labelController.text.trim().isNotEmpty &&
      _categoryController.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    // id/createdBy/createdAt are placeholders here — the screen that
    // pushed this form only reads label/category/quantity/note/packed
    // off the result and does the actual insert/update itself, since
    // those fields are assigned server-side.
    final item = PackingItem(
      id: widget.initial?.id ?? '',
      tripId: widget.initial?.tripId ?? '',
      label: _labelController.text.trim(),
      category: _categoryController.text.trim(),
      quantity: _quantity,
      note: _noteController.text.trim().isEmpty
          ? null
          : _noteController.text.trim(),
      packed: _packed,
      createdBy: widget.initial?.createdBy ?? '',
      createdAt: widget.initial?.createdAt ?? DateTime.now(),
    );
    Navigator.of(context).pop(PackingItemFormResult.save(item));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('utilities_remove_item_confirm_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${widget.initial!.label}" ${tr('utilities_remove_item_confirm_suffix')}',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(tr('common_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: Text(tr('utilities_remove')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const PackingItemFormResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: widget.isEditing
                  ? tr('utilities_edit_item_title')
                  : tr('utilities_add_item'),
              subtitle: widget.isEditing
                  ? tr('utilities_edit_item_subtitle')
                  : tr('utilities_add_item_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _FieldLabel(tr('utilities_field_item')),
                  _InputBox(
                    controller: _labelController,
                    icon: Icons.checklist_rounded,
                    hint: tr('utilities_hint_item'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  _FieldLabel(tr('utilities_field_category')),
                  _InputBox(
                    controller: _categoryController,
                    icon: Icons.folder_rounded,
                    hint: tr('utilities_hint_category'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _categoryOptions.map((category) {
                      final selected = _categoryController.text.trim() == category;
                      return GestureDetector(
                        onTap: () => setState(() => _categoryController.text = category),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.colors.ink
                                : context.colors.card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: selected
                                  ? context.colors.ink
                                  : context.colors.muted.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Text(
                            translatedPackingCategory(category),
                            style: TextStyle(
                              color: selected ? Colors.white : context.colors.ink,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  _FieldLabel(tr('utilities_field_quantity')),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                          icon: Icon(
                            Icons.remove_circle_outline_rounded,
                            color: context.colors.muted,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '$_quantity',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => setState(() => _quantity++),
                          icon: Icon(
                            Icons.add_circle_outline_rounded,
                            color: context.colors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _FieldLabel(tr('utilities_field_note')),
                  _InputBox(
                    controller: _noteController,
                    icon: Icons.sticky_note_2_outlined,
                    hint: tr('utilities_hint_note'),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.colors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          color: context.colors.muted,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            tr('utilities_already_packed'),
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Switch(
                          value: _packed,
                          onChanged: (v) => setState(() => _packed = v),
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color(0xFF11998E),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: widget.isEditing
                        ? tr('utilities_save_changes')
                        : tr('utilities_add_item'),
                    icon: Icons.check_rounded,
                    onPressed: _canSave ? _save : () {},
                  ),
                  if (widget.isEditing) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton.icon(
                        onPressed: _confirmDelete,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        label: Text(
                          tr('utilities_remove_item'),
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
      ),
    );
  }
}

class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.controller,
    required this.icon,
    required this.hint,
    this.onChanged,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: context.colors.muted, size: 20),
        hintText: hint,
        hintStyle: TextStyle(color: context.colors.muted),
        filled: true,
        fillColor: context.colors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: context.colors.ink, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 16,
        ),
      ),
    );
  }
}
