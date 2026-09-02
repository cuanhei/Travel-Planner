import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/expense.dart';
import '../../services/budget_service.dart';
import '../../services/group_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'budget_planner_screen.dart'
    show BudgetCategory, budgetCategories, categoryVisuals, formatAmount;
import 'spending_insights_screen.dart';

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatShortDate(DateTime d) => '${_monthNames[d.month - 1]} ${d.day}';

/// File extension for an [XFile] picked via image_picker, used to name
/// the storage object and pick its content-type — falls back to "jpg"
/// when the picked file has no extension (some web/camera captures).
String _photoFileExt(XFile file) {
  final name = file.name;
  final dot = name.lastIndexOf('.');
  if (dot == -1 || dot == name.length - 1) return 'jpg';
  return name.substring(dot + 1);
}

/// Cap on how many photos one expense can carry — keeps the picker strip
/// and upload time bounded rather than a hard product requirement.
const _maxPhotosPerExpense = 6;

/// A freshly picked-and-cropped photo waiting to be uploaded on save —
/// distinct from an already-saved [Expense.photoUrls] entry, which is
/// just a URL with no local bytes to re-upload.
class _PendingPhoto {
  const _PendingPhoto({required this.bytes, required this.ext});
  final Uint8List bytes;
  final String ext;
}

/// Full-screen crop step shown right after picking a photo — drag the
/// handles to choose which part of the image to keep (freeform, no
/// fixed aspect ratio) instead of silently center-cropping it later to
/// fit a thumbnail box. Pops with the cropped bytes, or null if the
/// user backs out.
class _CropPhotoScreen extends StatefulWidget {
  const _CropPhotoScreen({required this.bytes});

  final Uint8List bytes;

  @override
  State<_CropPhotoScreen> createState() => _CropPhotoScreenState();
}

class _CropPhotoScreenState extends State<_CropPhotoScreen> {
  final _controller = CropController();
  var _isCropping = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Crop Photo'),
        actions: [
          TextButton(
            onPressed: _isCropping
                ? null
                : () {
                    setState(() => _isCropping = true);
                    _controller.crop();
                  },
            child: const Text(
              'Done',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: Crop(
        image: widget.bytes,
        controller: _controller,
        baseColor: Colors.black,
        maskColor: Colors.black.withValues(alpha: 0.65),
        progressIndicator: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
        onCropped: (result) {
          switch (result) {
            case CropSuccess(:final croppedImage):
              Navigator.of(context).pop(croppedImage);
            case CropFailure():
              setState(() => _isCropping = false);
              Navigator.of(context).pop();
          }
        },
      ),
    );
  }
}

const _calcOperators = {'+', '−', '×', '÷'};

/// Evaluates a calculator-style expression typed via the amount field's
/// on-screen keypad, e.g. "13+12" -> 25 or "100×2−5" -> 195 (standard
/// ×/÷-before-+/− precedence, left to right within each). Returns null
/// if it can't be parsed (empty, a leading/trailing/doubled operator,
/// or division by zero).
double? _evaluateExpression(String input) {
  final expr = input.trim();
  if (expr.isEmpty) return null;

  final tokens = <String>[];
  final buffer = StringBuffer();
  for (final ch in expr.split('')) {
    if (_calcOperators.contains(ch)) {
      if (buffer.isEmpty) return null;
      tokens.add(buffer.toString());
      tokens.add(ch);
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  if (buffer.isEmpty) return null;
  tokens.add(buffer.toString());

  final first = double.tryParse(tokens[0]);
  if (first == null) return null;

  // First pass: × and ÷, left to right.
  final reduced = <Object>[first];
  var i = 1;
  while (i < tokens.length - 1) {
    final op = tokens[i];
    final operand = double.tryParse(tokens[i + 1]);
    if (operand == null) return null;
    if (op == '×' || op == '÷') {
      if (op == '÷' && operand == 0) return null;
      final last = reduced.removeLast() as double;
      reduced.add(op == '×' ? last * operand : last / operand);
    } else {
      reduced.add(op);
      reduced.add(operand);
    }
    i += 2;
  }

  // Second pass: + and −, left to right.
  var result = reduced[0] as double;
  var j = 1;
  while (j < reduced.length - 1) {
    final op = reduced[j] as String;
    final operand = reduced[j + 1] as double;
    result = op == '+' ? result + operand : result - operand;
    j += 2;
  }
  return result;
}

/// Applies one calculator keypad tap to [controller]'s text: digits and
/// `.` append (guarding against a second `.` within the current
/// number), an operator appends (or replaces a trailing operator rather
/// than stacking two), `⌫` deletes the last character, `C` clears, and
/// `=` evaluates the expression in place.
void _applyCalculatorKey(TextEditingController controller, String key) {
  final text = controller.text;

  if (key == 'C') {
    controller.clear();
    return;
  }
  if (key == '⌫') {
    if (text.isNotEmpty) {
      controller.text = text.substring(0, text.length - 1);
    }
    return;
  }
  if (key == '=') {
    final result = _evaluateExpression(text);
    if (result != null) controller.text = formatAmount(result);
    return;
  }
  if (_calcOperators.contains(key)) {
    if (text.isEmpty) return;
    final lastChar = text[text.length - 1];
    controller.text = _calcOperators.contains(lastChar)
        ? text.substring(0, text.length - 1) + key
        : text + key;
    return;
  }
  if (key == '.') {
    final lastOpIndex = text.split('').lastIndexWhere(_calcOperators.contains);
    if (text.substring(lastOpIndex + 1).contains('.')) return;
  }
  controller.text = text + key;
}

/// Handles a physical-keyboard edit to the amount field: normalizes the
/// ASCII operators a keyboard actually types (`* / -`) to the keypad's
/// symbols (`× ÷ −`) so both entry paths produce the exact same
/// expression text, and evaluates immediately if the just-typed
/// character was `=` (e.g. typing "13+12=").
void _handleAmountTyped(TextEditingController controller, String value) {
  final normalized = value
      .replaceAll('*', '×')
      .replaceAll('/', '÷')
      .replaceAll('-', '−');

  if (normalized.endsWith('=')) {
    final expr = normalized.substring(0, normalized.length - 1);
    final result = _evaluateExpression(expr);
    controller.text = result != null ? formatAmount(result) : expr;
    return;
  }

  if (normalized != value) {
    final selection = controller.selection;
    controller.value = controller.value.copyWith(
      text: normalized,
      selection: selection,
    );
  }
}

/// Live running log of trip expenses, backed by Supabase: each entry
/// can be tagged with a category and the stop it was spent at, added
/// fresh or edited later. The per-stop / per-category breakdown is
/// surfaced as "insights" — framed as the data a future AI budget
/// recommendation would draw on.
class ExpenseTrackerScreen extends StatefulWidget {
  const ExpenseTrackerScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<ExpenseTrackerScreen> createState() => _ExpenseTrackerScreenState();
}

class _ExpenseTrackerScreenState extends State<ExpenseTrackerScreen> {
  final _budgetService = BudgetService();
  final _groupService = GroupService();
  late final Future<bool> _isOrganizerFuture = _groupService.isOrganizer(
    widget.tripId,
  );

  Future<void> _saveExpense({
    Expense? existing,
    required String title,
    required String category,
    required double amount,
    required String? stopPlace,
    required List<String> photoUrls,
  }) async {
    if (existing != null) {
      await _budgetService.updateExpense(
        existing.id,
        title: title,
        category: category,
        amount: amount,
        stopPlace: stopPlace,
        photoUrls: photoUrls,
      );
    } else {
      await _budgetService.addExpense(
        tripId: widget.tripId,
        title: title,
        category: category,
        amount: amount,
        spentAt: DateTime.now(),
        stopPlace: stopPlace,
        photoUrls: photoUrls,
      );
    }
  }

  Future<void> _confirmDeleteExpense(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete this expense?',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          '"${expense.title}" (RM ${expense.amount.toStringAsFixed(2)}) will be removed.',
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
    if (confirmed != true || !mounted) return;
    try {
      await _budgetService.deleteExpense(expense.id, tripId: widget.tripId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text('$e')),
      );
    }
  }

  /// Read-only counterpart to [_showExpenseSheet] for an expense the
  /// viewer can't edit (logged by someone else, and they're not the
  /// organizer) — every member can still see what it was for, so the
  /// list doesn't hide details behind a permission wall it doesn't need.
  void _showExpenseDetailsSheet(Expense expense) {
    final visuals = categoryVisuals(expense.category);
    showModalBottomSheet(
      context: context,
      // Without this, the sheet caps itself at a fixed fraction of
      // screen height and its content doesn't scroll — a multi-photo
      // strip plus the detail rows can then overflow past that cap and
      // get laid out (and hit-tested) somewhere other than where
      // they're visibly drawn, making the photo look unclickable.
      isScrollControlled: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              24 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: visuals.color.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          visuals.icon,
                          color: visuals.color,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense.title,
                              style: TextStyle(
                                color: sheetContext.colors.ink,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              expense.category,
                              style: TextStyle(
                                color: sheetContext.colors.muted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'RM ${expense.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: sheetContext.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  if (expense.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _PhotoStrip(urls: expense.photoUrls),
                  ],
                  const SizedBox(height: 20),
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Date',
                    value: _formatShortDate(expense.spentAt),
                  ),
                  if (expense.stopPlace != null) ...[
                    const SizedBox(height: 12),
                    _DetailRow(
                      icon: Icons.place_rounded,
                      label: 'Where',
                      value: expense.stopPlace!,
                    ),
                  ],
                  const SizedBox(height: 12),
                  FutureBuilder<String?>(
                    future: _groupService.getDisplayName(expense.userId),
                    builder: (context, snap) {
                      return _DetailRow(
                        icon: Icons.person_rounded,
                        label: 'Logged by',
                        value: snap.data ?? '…',
                      );
                    },
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(color: sheetContext.colors.muted),
                      ),
                      child: Text(
                        'Close',
                        style: TextStyle(color: sheetContext.colors.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showExpenseSheet({
    Expense? existing,
    required List<String> stopSuggestions,
    required List<BudgetCategory> categorySuggestions,
  }) {
    final titleController = TextEditingController(text: existing?.title);
    final amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(2) : '',
    );
    final stopController = TextEditingController(text: existing?.stopPlace);
    final stopFocusNode = FocusNode();
    var selectedCategory = existing != null
        ? categoryVisuals(existing.category)
        : budgetCategories.first;
    String? formError;
    final keptExistingUrls = <String>[...?existing?.photoUrls];
    final pendingPhotos = <_PendingPhoto>[];
    var isUploadingPhoto = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void openPhotoViewer(int index) {
              final images = <ImageProvider>[
                for (final url in keptExistingUrls) NetworkImage(url),
                for (final photo in pendingPhotos) MemoryImage(photo.bytes),
              ];
              Navigator.of(sheetContext).push(
                MaterialPageRoute(
                  builder: (_) =>
                      _PhotoViewerScreen(images: images, initialIndex: index),
                  fullscreenDialog: true,
                ),
              );
            }

            Future<void> pickPhoto() async {
              if (keptExistingUrls.length + pendingPhotos.length >=
                  _maxPhotosPerExpense) {
                return;
              }
              final source = await showModalBottomSheet<ImageSource>(
                context: sheetContext,
                backgroundColor: sheetContext.colors.card,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (photoSheetContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_camera_rounded),
                        title: const Text('Take Photo'),
                        onTap: () => Navigator.of(
                          photoSheetContext,
                        ).pop(ImageSource.camera),
                      ),
                      ListTile(
                        leading: const Icon(Icons.photo_library_rounded),
                        title: const Text('Choose from Gallery'),
                        onTap: () => Navigator.of(
                          photoSheetContext,
                        ).pop(ImageSource.gallery),
                      ),
                    ],
                  ),
                ),
              );
              if (source == null) return;
              final file = await ImagePicker().pickImage(
                source: source,
                maxWidth: 2000,
                imageQuality: 90,
              );
              if (file == null) return;
              final bytes = await file.readAsBytes();
              if (!mounted) return;
              // Crop before adding — otherwise a portrait photo just
              // gets silently center-cropped later to fit the square
              // thumbnail box, hiding whatever wasn't in the middle.
              final cropped = await Navigator.of(context).push<Uint8List>(
                MaterialPageRoute(
                  builder: (_) => _CropPhotoScreen(bytes: bytes),
                  fullscreenDialog: true,
                ),
              );
              if (cropped == null) return;
              setSheetState(() {
                pendingPhotos.add(
                  _PendingPhoto(bytes: cropped, ext: _photoFileExt(file)),
                );
              });
            }

            Future<void> save() async {
              final title = titleController.text.trim();
              final rawAmount = amountController.text.trim();
              // Save works whether or not "=" was tapped first — typing
              // "13+12" and hitting Add directly computes and saves 25.
              final amount =
                  double.tryParse(rawAmount) ?? _evaluateExpression(rawAmount);
              if (title.isEmpty) {
                setSheetState(() => formError = 'Enter what you spent on');
                return;
              }
              if (amount == null || amount <= 0) {
                setSheetState(() => formError = 'Enter a valid amount');
                return;
              }
              final stopPlace = stopController.text.trim();

              final photoUrls = [...keptExistingUrls];
              if (pendingPhotos.isNotEmpty) {
                setSheetState(() => isUploadingPhoto = true);
                try {
                  for (final photo in pendingPhotos) {
                    final url = await _budgetService.uploadExpensePhoto(
                      tripId: widget.tripId,
                      bytes: photo.bytes,
                      fileExt: photo.ext,
                    );
                    photoUrls.add(url);
                  }
                } catch (e) {
                  setSheetState(() {
                    isUploadingPhoto = false;
                    formError = 'Could not upload photo: $e';
                  });
                  return;
                }
              }

              if (!sheetContext.mounted) return;
              Navigator.of(sheetContext).pop();
              await _saveExpense(
                existing: existing,
                title: title,
                category: selectedCategory.label,
                amount: amount,
                stopPlace: stopPlace.isEmpty ? null : stopPlace,
                photoUrls: photoUrls,
              );
            }

            Future<void> delete() async {
              Navigator.of(sheetContext).pop();
              await _confirmDeleteExpense(existing!);
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            existing != null ? 'Edit Expense' : 'Add Expense',
                            style: TextStyle(
                              color: sheetContext.colors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        if (existing != null)
                          IconButton(
                            onPressed: delete,
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.redAccent,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleController,
                      onChanged: (_) {
                        if (formError != null) {
                          setSheetState(() => formError = null);
                        }
                      },
                      style: TextStyle(color: sheetContext.colors.ink),
                      decoration: InputDecoration(
                        hintText: 'What did you spend on?',
                        filled: true,
                        fillColor: sheetContext.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.text,
                      onChanged: (value) {
                        setSheetState(() {
                          formError = null;
                          _handleAmountTyped(amountController, value);
                        });
                      },
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Amount (RM) — type or use the keypad',
                        filled: true,
                        fillColor: sheetContext.colors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final text = amountController.text;
                        final hasOperator = text.contains(RegExp(r'[+−×÷]'));
                        final preview = hasOperator
                            ? _evaluateExpression(text)
                            : null;
                        if (preview == null) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6, left: 4),
                          child: Text(
                            '= RM ${formatAmount(preview)}',
                            style: TextStyle(
                              color: sheetContext.colors.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _CalculatorKeypad(
                      onKeyTap: (key) {
                        setSheetState(() {
                          formError = null;
                          _applyCalculatorKey(amountController, key);
                        });
                      },
                    ),
                    if (formError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        formError!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'Category',
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ...budgetCategories.map(
                          (c) => _CategoryChip(
                            category: c,
                            isSelected: c.label == selectedCategory.label,
                            onTap: () =>
                                setSheetState(() => selectedCategory = c),
                          ),
                        ),
                        // Custom categories typed in via "Other" on a
                        // past expense (e.g. "Visa") — offered directly
                        // as a chip from here on, instead of having to
                        // retype it through "Other" every time. Skips
                        // whichever one is currently selected-but-custom
                        // — the "Other" chip below already represents
                        // that case, so this avoids showing it twice.
                        ...categorySuggestions
                            .where(
                              (c) =>
                                  c.label != selectedCategory.label ||
                                  budgetCategories.any(
                                    (b) => b.label == selectedCategory.label,
                                  ),
                            )
                            .map(
                              (c) => _CategoryChip(
                                category: c,
                                isSelected: false,
                                onTap: () =>
                                    setSheetState(() => selectedCategory = c),
                              ),
                            ),
                        _OtherCategoryChip(
                          selectedCategory: selectedCategory,
                          onPicked: (custom) =>
                              setSheetState(() => selectedCategory = custom),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Where were you?',
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick a previous stop or type a new one — so we can learn your spending patterns',
                      style: TextStyle(
                        color: sheetContext.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Autocomplete<String>(
                      textEditingController: stopController,
                      focusNode: stopFocusNode,
                      optionsBuilder: (value) {
                        if (value.text.trim().isEmpty) {
                          return stopSuggestions;
                        }
                        final q = value.text.trim().toLowerCase();
                        return stopSuggestions.where(
                          (s) => s.toLowerCase().contains(q),
                        );
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              style: TextStyle(color: sheetContext.colors.ink),
                              decoration: InputDecoration(
                                hintText: 'Where were you? (optional)',
                                prefixIcon: Icon(
                                  Icons.place_rounded,
                                  size: 18,
                                  color: sheetContext.colors.muted,
                                ),
                                filled: true,
                                fillColor: sheetContext.colors.surface,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            );
                          },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            color: sheetContext.colors.card,
                            elevation: 4,
                            borderRadius: BorderRadius.circular(14),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 220,
                                minWidth: 280,
                              ),
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return InkWell(
                                    onTap: () => onSelected(option),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.place_rounded,
                                            size: 14,
                                            color: sheetContext.colors.muted,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              option,
                                              style: TextStyle(
                                                color: sheetContext.colors.ink,
                                                fontSize: 13,
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
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Photos (optional)',
                      style: TextStyle(
                        color: sheetContext.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Attach up to $_maxPhotosPerExpense receipt or reference photos',
                      style: TextStyle(
                        color: sheetContext.colors.muted,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 88,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < keptExistingUrls.length; i++)
                            _PhotoThumb(
                              key: ValueKey('existing-${keptExistingUrls[i]}'),
                              image: NetworkImage(keptExistingUrls[i]),
                              onTap: () => openPhotoViewer(i),
                              onRemove: () => setSheetState(
                                () => keptExistingUrls.removeAt(i),
                              ),
                            ),
                          for (var i = 0; i < pendingPhotos.length; i++)
                            _PhotoThumb(
                              key: ValueKey('pending-$i'),
                              image: MemoryImage(pendingPhotos[i].bytes),
                              onTap: () =>
                                  openPhotoViewer(keptExistingUrls.length + i),
                              onRemove: () => setSheetState(
                                () => pendingPhotos.removeAt(i),
                              ),
                            ),
                          if (keptExistingUrls.length + pendingPhotos.length <
                              _maxPhotosPerExpense)
                            _AddPhotoTile(onTap: pickPhoto),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: isUploadingPhoto ? null : save,
                        style: FilledButton.styleFrom(
                          backgroundColor: sheetContext.colors.ink,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: isUploadingPhoto
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(existing != null ? 'Save Changes' : 'Add'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myUid = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: FutureBuilder<bool>(
          future: _isOrganizerFuture,
          builder: (context, organizerSnap) {
            final isOrganizer = organizerSnap.data ?? false;
            return StreamBuilder<List<String>>(
              stream: _budgetService.watchStopNames(widget.tripId),
              builder: (context, stopSnap) {
                final stopNames = stopSnap.data ?? const <String>[];
                return StreamBuilder<List<Expense>>(
                  stream: _budgetService.watchExpenses(widget.tripId),
                  builder: (context, snapshot) {
                    final expenses = snapshot.data ?? const <Expense>[];
                    final total = expenses.fold<double>(
                      0,
                      (sum, e) => sum + e.amount,
                    );

                    final byStop = <String, List<Expense>>{};
                    for (final e in expenses) {
                      if (e.stopPlace == null) continue;
                      byStop.putIfAbsent(e.stopPlace!, () => []).add(e);
                    }
                    final avgPerStop = byStop.isEmpty
                        ? 0.0
                        : byStop.values
                                  .map(
                                    (list) => list.fold<double>(
                                      0,
                                      (s, e) => s + e.amount,
                                    ),
                                  )
                                  .fold<double>(0, (a, b) => a + b) /
                              byStop.length;

                    final byCategory = <String, double>{};
                    for (final e in expenses) {
                      byCategory.update(
                        e.category,
                        (v) => v + e.amount,
                        ifAbsent: () => e.amount,
                      );
                    }
                    final topCategory = byCategory.entries.isEmpty
                        ? null
                        : byCategory.entries.reduce(
                            (a, b) => a.value > b.value ? a : b,
                          );

                    // Suggestions for "Where were you?": planned trip
                    // stops plus any custom stop name already typed on an
                    // expense — a trip with no planned stops (e.g. the
                    // auto-created demo trip) would otherwise offer no
                    // suggestions at all and, since the field used to be
                    // chip-only, no way to tag a stop whatsoever.
                    final stopSuggestions = <String>{
                      ...stopNames,
                      for (final e in expenses)
                        if (e.stopPlace != null) e.stopPlace!,
                    }.toList()..sort();

                    // Custom categories already typed in via "Other" on
                    // a past expense (e.g. "Visa") — offered directly as
                    // a chip from here on instead of only through the
                    // fixed budgetCategories set.
                    final categorySuggestions = <String>{
                      for (final e in expenses)
                        if (!budgetCategories.any((c) => c.label == e.category))
                          e.category,
                    }.toList()..sort();
                    final categoryVisualSuggestions = categorySuggestions
                        .map(categoryVisuals)
                        .toList();

                    return Column(
                      children: [
                        DetailHeader(
                          title: 'Expense Tracker',
                          subtitle: 'RM ${total.toStringAsFixed(2)} logged',
                          trailing: IconButton(
                            onPressed: () => _showExpenseSheet(
                              stopSuggestions: stopSuggestions,
                              categorySuggestions: categoryVisualSuggestions,
                            ),
                            icon: Icon(
                              Icons.add_circle_rounded,
                              color: context.colors.ink,
                              size: 26,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            children: [
                              Material(
                                color: context.colors.card,
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => SpendingInsightsScreen(
                                        tripId: widget.tripId,
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: context.colors.ink.withValues(
                                            alpha: 0.05,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.insights_rounded,
                                              color: AppColors.accent,
                                              size: 18,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Spending Insights',
                                                style: TextStyle(
                                                  color: context.colors.ink,
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 13.5,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              size: 18,
                                              color: context.colors.muted,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: _InsightStat(
                                                label: 'Avg per stop',
                                                value: byStop.isEmpty
                                                    ? '—'
                                                    : 'RM ${formatAmount(avgPerStop)}',
                                              ),
                                            ),
                                            Expanded(
                                              child: _InsightStat(
                                                label: 'Top category',
                                                value: topCategory?.key ?? '—',
                                              ),
                                            ),
                                            Expanded(
                                              child: _InsightStat(
                                                label: 'Stops tagged',
                                                value: '${byStop.length}',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Tag expenses with a stop and category — we\'ll use this history to recommend smarter budgets on future trips.',
                                          style: TextStyle(
                                            color: context.colors.muted,
                                            fontSize: 11,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              if (expenses.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'No expenses logged yet.',
                                      style: TextStyle(
                                        color: context.colors.muted,
                                      ),
                                    ),
                                  ),
                                ),
                              ...expenses.map((e) {
                                final visuals = categoryVisuals(e.category);
                                final canEdit =
                                    e.userId == myUid || isOrganizer;
                                return Material(
                                  color: context.colors.card,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: canEdit
                                        ? () => _showExpenseSheet(
                                            existing: e,
                                            stopSuggestions: stopSuggestions,
                                            categorySuggestions:
                                                categoryVisualSuggestions,
                                          )
                                        : () => _showExpenseDetailsSheet(e),
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(13),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: context.colors.ink
                                                .withValues(alpha: 0.05),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: visuals.color.withValues(
                                                alpha: 0.12,
                                              ),
                                              shape: BoxShape.circle,
                                            ),
                                            alignment: Alignment.center,
                                            child: Icon(
                                              visuals.icon,
                                              color: visuals.color,
                                              size: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        e.title,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: context
                                                              .colors
                                                              .ink,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    if (e
                                                        .photoUrls
                                                        .isNotEmpty) ...[
                                                      const SizedBox(width: 5),
                                                      Icon(
                                                        Icons
                                                            .photo_camera_rounded,
                                                        size: 12,
                                                        color: context
                                                            .colors
                                                            .muted,
                                                      ),
                                                      if (e.photoUrls.length >
                                                          1) ...[
                                                        const SizedBox(
                                                          width: 2,
                                                        ),
                                                        Text(
                                                          '${e.photoUrls.length}',
                                                          style: TextStyle(
                                                            color: context
                                                                .colors
                                                                .muted,
                                                            fontSize: 10.5,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ],
                                                ),
                                                Text(
                                                  e.stopPlace == null
                                                      ? '${e.category} · ${_formatShortDate(e.spentAt)}'
                                                      : '${e.category} · ${e.stopPlace} · ${_formatShortDate(e.spentAt)}',
                                                  style: TextStyle(
                                                    color: context.colors.muted,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            'RM ${e.amount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: context.colors.ink,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: context.colors.muted,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// On-screen calculator keypad for the amount field — digits plus
/// `+ − × ÷` and `=`, so "13+12" can be typed and evaluated to 25
/// directly, like a receipt/accounting app's amount entry. Replaces the
/// OS keyboard (the amount field is read-only) since a plain numeric
/// keypad has no operator keys.
class _CalculatorKeypad extends StatelessWidget {
  const _CalculatorKeypad({required this.onKeyTap});

  final ValueChanged<String> onKeyTap;

  static const _rows = [
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    ['C', '0', '.', '+'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (final key in row) ...[
                  Expanded(
                    child: _KeypadButton(
                      label: key,
                      isOperator: _calcOperators.contains(key),
                      onTap: () => onKeyTap(key),
                    ),
                  ),
                  if (key != row.last) const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: _KeypadButton(label: '⌫', onTap: () => onKeyTap('⌫')),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _KeypadButton(
                label: '=',
                isAccent: true,
                onTap: () => onKeyTap('='),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({
    required this.label,
    required this.onTap,
    this.isOperator = false,
    this.isAccent = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isOperator;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final background = isAccent ? context.colors.ink : context.colors.surface;
    final foreground = isAccent
        ? Colors.white
        : isOperator
        ? AppColors.accent
        : context.colors.ink;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A single selectable category chip — shared by the fixed
/// [budgetCategories] and by previously-used custom categories.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.isSelected,
    required this.onTap,
  });

  final BudgetCategory category;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? category.color.withValues(alpha: 0.16)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? category.color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon, size: 14, color: category.color),
            const SizedBox(width: 6),
            Text(
              category.label,
              style: TextStyle(
                color: isSelected ? category.color : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chip for a category outside the fixed [budgetCategories] set —
/// prompts for a custom name (e.g. "Souvenirs", "Visa Fees") so
/// spending that doesn't fit the presets still gets tagged and shows
/// up in the Budget Planner's "By Category" breakdown.
class _OtherCategoryChip extends StatelessWidget {
  const _OtherCategoryChip({
    required this.selectedCategory,
    required this.onPicked,
  });

  final BudgetCategory selectedCategory;
  final ValueChanged<BudgetCategory> onPicked;

  bool get _isSelected =>
      !budgetCategories.any((c) => c.label == selectedCategory.label);

  Future<void> _pick(BuildContext context) async {
    final controller = TextEditingController(
      text: _isSelected ? selectedCategory.label : '',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.colors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Custom category',
          style: TextStyle(
            color: dialogContext.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15.5,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: dialogContext.colors.ink),
          decoration: InputDecoration(
            hintText: 'e.g. Souvenirs, Visa Fees',
            filled: true,
            fillColor: dialogContext.colors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              backgroundColor: dialogContext.colors.ink,
            ),
            child: const Text('Use this'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      onPicked(categoryVisuals(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _isSelected ? selectedCategory : categoryVisuals('Other');
    return GestureDetector(
      onTap: () => _pick(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _isSelected
              ? c.color.withValues(alpha: 0.16)
              : context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isSelected ? c.color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(c.icon, size: 14, color: c.color),
            const SizedBox(width: 6),
            Text(
              _isSelected ? selectedCategory.label : 'Other',
              style: TextStyle(
                color: _isSelected ? c.color : context.colors.ink,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightStat extends StatelessWidget {
  const _InsightStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: context.colors.muted, fontSize: 10.5),
        ),
      ],
    );
  }
}

/// One photo in the Add/Edit Expense sheet's picker strip — either an
/// already-saved URL or freshly picked (and cropped) local bytes, with
/// a small remove button. Square thumbnail: fine to center-crop here
/// since the user already chose the crop themselves upstream. Tapping
/// the image (not the remove button) opens the same full-screen
/// zoomable viewer the read-only details sheet uses, so a photo isn't
/// stuck at this fixed 80x80 preview size while editing either.
class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    super.key,
    required this.image,
    required this.onTap,
    required this.onRemove,
  });

  final ImageProvider image;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          children: [
            GestureDetector(
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: image,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onRemove,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
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

/// Trailing tile in the photo picker strip — tap to add another photo
/// (opens source picker, then the crop screen).
class _AddPhotoTile extends StatelessWidget {
  const _AddPhotoTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: context.colors.muted.withValues(alpha: 0.3),
            width: 1.2,
          ),
        ),
        child: Icon(
          Icons.add_a_photo_rounded,
          color: context.colors.muted,
          size: 22,
        ),
      ),
    );
  }
}

/// Read-only display of an expense's photos — a single one shown large
/// and full-width, several shown as a scrollable strip of square
/// thumbnails. Tapping any of them opens the full-screen zoomable
/// viewer instead of just a bigger fixed-size crop.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.urls});

  final List<String> urls;

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewerScreen(
          images: [for (final url in urls) NetworkImage(url)],
          initialIndex: index,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return GestureDetector(
        onTap: () => _openViewer(context, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            urls.first,
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () => _openViewer(context, i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              urls[i],
              width: 110,
              height: 110,
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-to-zoom viewer for an expense's
/// photos — the whole image via [BoxFit.contain], not a center-cropped
/// preview box, so nothing is ever hidden off-frame. Takes
/// [ImageProvider]s rather than URLs so it can show a freshly-picked,
/// not-yet-uploaded photo (in-memory bytes) just as well as a saved one.
class _PhotoViewerScreen extends StatelessWidget {
  const _PhotoViewerScreen({
    required this.images,
    required this.initialIndex,
  });

  final List<ImageProvider> images;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: images.length,
        itemBuilder: (context, i) => _ZoomablePhoto(image: images[i]),
      ),
    );
  }
}

/// One photo's zoom/pan surface — pinch (touch), double-tap (toggles
/// between fit and zoomed-in, centered on the tap), and mouse-wheel
/// scroll (desktop/web, centered on the cursor) all zoom in and out,
/// matching how a phone's photo viewer behaves regardless of input.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.image});

  final ImageProvider image;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  static const _doubleTapZoom = 3.0;
  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    if (_controller.value != Matrix4.identity()) {
      _controller.value = Matrix4.identity();
      return;
    }
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (_doubleTapZoom - 1),
        -position.dy * (_doubleTapZoom - 1),
        0.0,
        1.0,
      )
      ..scaleByDouble(_doubleTapZoom, _doubleTapZoom, _doubleTapZoom, 1.0);
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final currentScale = _controller.value.getMaxScaleOnAxis();
    final targetScale = (currentScale - event.scrollDelta.dy * 0.0025).clamp(
      _minScale,
      _maxScale,
    );
    if (targetScale <= _minScale) {
      _controller.value = Matrix4.identity();
      return;
    }
    final position = event.localPosition;
    _controller.value = Matrix4.identity()
      ..translateByDouble(
        -position.dx * (targetScale - 1),
        -position.dy * (targetScale - 1),
        0.0,
        1.0,
      )
      ..scaleByDouble(targetScale, targetScale, targetScale, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: GestureDetector(
        onDoubleTapDown: (details) => _doubleTapDetails = details,
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: _minScale,
          maxScale: _maxScale,
          child: Center(child: Image(image: widget.image, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

/// One labeled row in the read-only expense detail sheet — icon, label,
/// value, all on a line.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.colors.muted),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(color: context.colors.muted, fontSize: 12.5),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: context.colors.ink,
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}
