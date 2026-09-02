import 'package:flutter/material.dart';

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
  late bool _packed = widget.initial?.packed ?? false;

  @override
  void dispose() {
    _labelController.dispose();
    _categoryController.dispose();
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
    final item = PackingItem(
      id: widget.initial?.id ?? DateTime.now().microsecondsSinceEpoch,
      label: _labelController.text.trim(),
      category: _categoryController.text.trim(),
      packed: _packed,
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
          'Remove this item?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${widget.initial!.label}" will be removed from your packing list.',
          style: TextStyle(color: dialogContext.colors.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Remove'),
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
              title: widget.isEditing ? 'Edit Item' : 'Add Item',
              subtitle: widget.isEditing
                  ? 'Update this packing list item'
                  : 'Add something to your packing list',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _FieldLabel('Item'),
                  _InputBox(
                    controller: _labelController,
                    icon: Icons.checklist_rounded,
                    hint: 'e.g. Sunglasses',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  _FieldLabel('Category'),
                  _InputBox(
                    controller: _categoryController,
                    icon: Icons.folder_rounded,
                    hint: 'e.g. Clothing',
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
                            category,
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
                            'Already packed',
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
                    label: widget.isEditing ? 'Save Changes' : 'Add Item',
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
                        label: const Text(
                          'Remove Item',
                          style: TextStyle(
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
