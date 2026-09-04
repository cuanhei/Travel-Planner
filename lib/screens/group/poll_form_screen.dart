import 'package:flutter/material.dart';

import '../../models/poll.dart';
import '../../services/locale_service.dart';
import '../../services/poll_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

const _maxOptions = 6;
const _minOptions = 2;

/// Form for creating a new group poll or editing/deleting an existing
/// one — a question plus 2–6 options. Writes straight to Supabase;
/// [VotingScreen] picks up the change via its realtime stream.
class PollFormScreen extends StatefulWidget {
  const PollFormScreen({super.key, required this.tripId, this.initial});

  final String tripId;

  /// Poll being edited, or null when creating a new one.
  final Poll? initial;

  bool get isEditing => initial != null;

  @override
  State<PollFormScreen> createState() => _PollFormScreenState();
}

class _PollFormScreenState extends State<PollFormScreen> {
  final _pollService = PollService();
  bool _isSaving = false;

  late final _questionController = TextEditingController(
    text: widget.initial?.question ?? '',
  );

  late final _optionControllers = widget.initial == null
      ? [TextEditingController(), TextEditingController()]
      : widget.initial!.options
            .map((o) => TextEditingController(text: o.label))
            .toList();

  @override
  void dispose() {
    _questionController.dispose();
    for (final c in _optionControllers) {
      c.dispose();
    }
    super.dispose();
  }

  int get _filledOptionCount =>
      _optionControllers.where((c) => c.text.trim().isNotEmpty).length;

  bool get _canSave =>
      _questionController.text.trim().isNotEmpty && _filledOptionCount >= _minOptions;

  void _addOption() {
    if (_optionControllers.length >= _maxOptions) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= _minOptions) return;
    setState(() => _optionControllers.removeAt(index).dispose());
  }

  Future<void> _save() async {
    if (!_canSave || _isSaving) return;
    final labels = _optionControllers
        .map((c) => c.text.trim())
        .where((label) => label.isNotEmpty)
        .toList();

    setState(() => _isSaving = true);
    try {
      if (widget.initial != null) {
        await _pollService.updatePoll(
          pollId: widget.initial!.id,
          question: _questionController.text.trim(),
          optionLabels: labels,
        );
      } else {
        await _pollService.createPoll(
          tripId: widget.tripId,
          question: _questionController.text.trim(),
          optionLabels: labels,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr('group_delete_poll_title'),
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${widget.initial!.question}" ${tr('group_delete_poll_content_suffix')}',
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
            child: Text(tr('common_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _pollService.deletePoll(widget.initial!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: widget.isEditing ? tr('group_edit_poll_title') : tr('group_new_poll_title'),
              subtitle: widget.isEditing
                  ? tr('group_edit_poll_subtitle')
                  : tr('group_new_poll_subtitle'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _FieldLabel(tr('group_field_question')),
                  TextField(
                    controller: _questionController,
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.colors.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: tr('group_question_hint'),
                      filled: true,
                      fillColor: context.colors.card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: context.colors.ink,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _FieldLabel(tr('group_field_options')),
                      const Spacer(),
                      Text(
                        '${_optionControllers.length}/$_maxOptions',
                        style: TextStyle(
                          color: context.colors.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...List.generate(_optionControllers.length, (i) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _optionControllers[i],
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: context.colors.ink,
                              ),
                              decoration: InputDecoration(
                                hintText: '${tr('group_option_hint_prefix')} ${i + 1}',
                                filled: true,
                                fillColor: context.colors.card,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: context.colors.ink,
                                    width: 1.5,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                  horizontal: 14,
                                ),
                              ),
                            ),
                          ),
                          if (_optionControllers.length > _minOptions) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _removeOption(i),
                              child: Icon(
                                Icons.remove_circle_outline_rounded,
                                color: context.colors.muted,
                                size: 22,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  if (_optionControllers.length < _maxOptions)
                    TextButton.icon(
                      onPressed: _addOption,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(tr('group_add_option')),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.ink,
                      ),
                    ),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: widget.isEditing ? tr('group_save_changes') : tr('group_create_poll'),
                    icon: Icons.how_to_vote_rounded,
                    onPressed: _canSave && !_isSaving ? _save : () {},
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
                          tr('group_delete_poll_button'),
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
