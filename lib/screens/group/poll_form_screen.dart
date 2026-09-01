import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import 'voting_screen.dart';

/// Result of [PollFormScreen]: either a saved (created/edited) poll, or
/// a request to delete the poll being edited.
class PollFormResult {
  const PollFormResult.save(Poll savedPoll) : poll = savedPoll, deleted = false;
  const PollFormResult.delete() : poll = null, deleted = true;

  final Poll? poll;
  final bool deleted;
}

const _maxOptions = 6;
const _minOptions = 2;

/// UI-only form for creating a new group poll or editing/deleting an
/// existing one — a question plus 2–6 options.
class PollFormScreen extends StatefulWidget {
  const PollFormScreen({super.key, this.initial});

  /// Poll being edited, or null when creating a new one.
  final Poll? initial;

  bool get isEditing => initial != null;

  @override
  State<PollFormScreen> createState() => _PollFormScreenState();
}

class _PollFormScreenState extends State<PollFormScreen> {
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

  void _save() {
    if (!_canSave) return;
    final options = <PollOption>[];
    for (var i = 0; i < _optionControllers.length; i++) {
      final label = _optionControllers[i].text.trim();
      if (label.isEmpty) continue;
      final priorVotes = (widget.initial != null && i < widget.initial!.options.length)
          ? widget.initial!.options[i].votes
          : 0;
      options.add(PollOption(label, priorVotes));
    }
    final poll = Poll(_questionController.text.trim(), options);
    final priorVotedIndex = widget.initial?.votedIndex;
    poll.votedIndex = (priorVotedIndex != null && priorVotedIndex < options.length)
        ? priorVotedIndex
        : null;
    Navigator.of(context).pop(PollFormResult.save(poll));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete this poll?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${widget.initial!.question}" will be removed for the group.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const PollFormResult.delete());
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
              title: widget.isEditing ? 'Edit Poll' : 'New Poll',
              subtitle: widget.isEditing
                  ? 'Update the question or options'
                  : 'Ask the group to decide something',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  _FieldLabel('Question'),
                  TextField(
                    controller: _questionController,
                    maxLines: 2,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.colors.ink,
                    ),
                    decoration: InputDecoration(
                      hintText: 'e.g. Where should we have dinner?',
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
                      _FieldLabel('Options'),
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
                                hintText: 'Option ${i + 1}',
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
                      label: const Text('Add option'),
                      style: TextButton.styleFrom(
                        foregroundColor: context.colors.ink,
                      ),
                    ),
                  const SizedBox(height: 24),
                  GradientButton(
                    label: widget.isEditing ? 'Save Changes' : 'Create Poll',
                    icon: Icons.how_to_vote_rounded,
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
                          'Delete Poll',
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
