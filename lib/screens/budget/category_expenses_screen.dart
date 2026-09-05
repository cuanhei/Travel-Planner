import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/expense.dart';
import '../../services/budget_service.dart';
import '../../services/group_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import 'budget_planner_screen.dart'
    show BudgetCategory, categoryVisuals, formatAmount;

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

/// "What's in this category" view, reached by tapping a category card
/// in the Budget Planner's By Category list — every expense logged
/// under [label], with a planned/spent/remaining summary up top.
/// Read-only: editing an expense stays in the Expense Tracker, editing
/// the category's planned amount (or deleting it) stays on the Budget
/// Planner row itself.
class CategoryExpensesScreen extends StatelessWidget {
  const CategoryExpensesScreen({
    super.key,
    required this.tripId,
    required this.label,
    required this.planned,
  });

  final String tripId;
  final String label;
  final double planned;

  @override
  Widget build(BuildContext context) {
    final budgetService = BudgetService();
    final groupService = GroupService();
    final visuals = categoryVisuals(label);

    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: StreamBuilder<List<Expense>>(
          stream: budgetService.watchExpenses(tripId),
          builder: (context, snapshot) {
            final expenses = (snapshot.data ?? const <Expense>[])
                .where((e) => e.category == label)
                .toList();
            final spent = expenses.fold<double>(0, (s, e) => s + e.amount);
            final remaining = planned - spent;
            final isOverBudget = planned > 0 && spent > planned;

            return Column(
              children: [
                DetailHeader(
                  title: label,
                  subtitle:
                      '${expenses.length} expense${expenses.length == 1 ? '' : 's'}',
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: context.colors.card,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: context.colors.ink.withValues(alpha: 0.05),
                              blurRadius: 12,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
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
                                if (planned > 0)
                                  Expanded(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (isOverBudget) ...[
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.redAccent,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Over budget',
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (isOverBudget
                                                        ? Colors.redAccent
                                                        : visuals.color)
                                                    .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '${(spent / planned * 100).round()}%',
                                            style: TextStyle(
                                              color: isOverBudget
                                                  ? Colors.redAccent
                                                  : visuals.color,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _CategoryStat(
                                    label: 'Planned',
                                    value: planned,
                                  ),
                                ),
                                Expanded(
                                  child: _CategoryStat(
                                    label: 'Spent',
                                    value: spent,
                                    valueColor: isOverBudget
                                        ? Colors.redAccent
                                        : null,
                                  ),
                                ),
                                Expanded(
                                  child: _CategoryStat(
                                    label: 'Remaining',
                                    value: remaining,
                                    valueColor: remaining < 0
                                        ? Colors.redAccent
                                        : const Color(0xFF11998E),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Expenses',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (expenses.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'No expenses logged in this category yet.',
                              style: TextStyle(color: context.colors.muted),
                            ),
                          ),
                        )
                      else
                        ...expenses.map(
                          (e) => _ExpenseTile(
                            expense: e,
                            visuals: visuals,
                            groupService: groupService,
                          ),
                        ),
                    ],
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

class _CategoryStat extends StatelessWidget {
  const _CategoryStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final double value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.colors.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          'RM ${formatAmount(value)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ?? context.colors.ink,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}

/// One expense row, tappable to a read-only detail view (including its
/// photo, if any) — this screen never edits, matching its "what's in
/// this category" purpose.
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({
    required this.expense,
    required this.visuals,
    required this.groupService,
  });

  final Expense expense;
  final BudgetCategory visuals;
  final GroupService groupService;

  void _showDetails(BuildContext context) {
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
                    future: groupService.getDisplayName(expense.userId),
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

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetails(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: context.colors.ink.withValues(alpha: 0.05),
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
                  color: visuals.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(visuals.icon, color: visuals.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            expense.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.colors.ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        if (expense.photoUrls.isNotEmpty) ...[
                          const SizedBox(width: 5),
                          Icon(
                            Icons.photo_camera_rounded,
                            size: 12,
                            color: context.colors.muted,
                          ),
                          if (expense.photoUrls.length > 1) ...[
                            const SizedBox(width: 2),
                            Text(
                              '${expense.photoUrls.length}',
                              style: TextStyle(
                                color: context.colors.muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    Text(
                      expense.stopPlace == null
                          ? _formatShortDate(expense.spentAt)
                          : '${expense.stopPlace} · ${_formatShortDate(expense.spentAt)}',
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'RM ${expense.amount.toStringAsFixed(2)}',
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
        builder: (_) => _PhotoViewerScreen(urls: urls, initialIndex: index),
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
/// preview box, so nothing is ever hidden off-frame.
class _PhotoViewerScreen extends StatelessWidget {
  const _PhotoViewerScreen({required this.urls, required this.initialIndex});

  final List<String> urls;
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
        itemCount: urls.length,
        itemBuilder: (context, i) => _ZoomablePhoto(url: urls[i]),
      ),
    );
  }
}

/// One photo's zoom/pan surface — pinch (touch), double-tap (toggles
/// between fit and zoomed-in, centered on the tap), and mouse-wheel
/// scroll (desktop/web, centered on the cursor) all zoom in and out,
/// matching how a phone's photo viewer behaves regardless of input.
class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.url});

  final String url;

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
          child: Center(child: Image.network(widget.url, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

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
