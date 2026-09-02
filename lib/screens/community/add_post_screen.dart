import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';
import '../explore/explore_tab.dart' show categories;
import 'community_tab.dart';

const _coverGradients = [
  AppColors.horizon,
  AppColors.dusk,
  AppColors.sunset,
  AppColors.lagoon,
];

/// UI-only "new post" composer for the Community feed — caption,
/// location, a category (sets the icon), and a cover gradient, with a
/// live preview of the resulting post card.
class AddPostScreen extends StatefulWidget {
  const AddPostScreen({super.key});

  @override
  State<AddPostScreen> createState() => _AddPostScreenState();
}

class _AddPostScreenState extends State<AddPostScreen> {
  final _captionController = TextEditingController();
  final _placeController = TextEditingController();
  int _categoryIndex = 0;
  int _gradientIndex = 0;

  @override
  void dispose() {
    _captionController.dispose();
    _placeController.dispose();
    super.dispose();
  }

  bool get _canPost =>
      _captionController.text.trim().isNotEmpty &&
      _placeController.text.trim().isNotEmpty;

  void _submit() {
    if (!_canPost) return;
    final post = Post(
      author: 'Alex Tan',
      avatarColor: AppColors.accent,
      place: _placeController.text.trim(),
      time: 'Just now',
      caption: _captionController.text.trim(),
      gradient: _coverGradients[_gradientIndex],
      icon: categories[_categoryIndex].icon,
      likes: 0,
      comments: 0,
    );
    Navigator.of(context).pop(post);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const DetailHeader(
              title: 'New Post',
              subtitle: 'Share a travel moment',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 20,
                        backgroundColor: AppColors.accent,
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Posting as Alex Tan',
                        style: TextStyle(
                          color: context.colors.ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel('Where was this?'),
                  _InputBox(
                    controller: _placeController,
                    icon: Icons.location_on_rounded,
                    hint: 'e.g. Chew Jetty, George Town',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 20),
                  _FieldLabel('Caption'),
                  _InputBox(
                    controller: _captionController,
                    icon: Icons.edit_rounded,
                    hint: 'Share your experience…',
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel('Category'),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: List.generate(categories.length, (i) {
                      final c = categories[i];
                      final selected = _categoryIndex == i;
                      return GestureDetector(
                        onTap: () => setState(() => _categoryIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.colors.ink
                                : context.colors.card,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected
                                  ? context.colors.ink
                                  : context.colors.muted.withValues(
                                      alpha: 0.25,
                                    ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                c.icon,
                                size: 14,
                                color: selected
                                    ? Colors.white
                                    : context.colors.muted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                c.label,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : context.colors.ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  _FieldLabel('Cover Style'),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(_coverGradients.length, (i) {
                      final selected = _gradientIndex == i;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () => setState(() => _gradientIndex = i),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _coverGradients[i],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              border: selected
                                  ? Border.all(
                                      color: context.colors.ink,
                                      width: 3,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: selected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 28),
                  _FieldLabel('Preview'),
                  const SizedBox(height: 8),
                  _PostPreview(
                    caption: _captionController.text.trim().isEmpty
                        ? 'Your caption will appear here…'
                        : _captionController.text.trim(),
                    place: _placeController.text.trim().isEmpty
                        ? 'Location'
                        : _placeController.text.trim(),
                    gradient: _coverGradients[_gradientIndex],
                    icon: categories[_categoryIndex].icon,
                  ),
                  const SizedBox(height: 32),
                  GradientButton(
                    label: 'Post',
                    icon: Icons.send_rounded,
                    onPressed: _canPost ? _submit : () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostPreview extends StatelessWidget {
  const _PostPreview({
    required this.caption,
    required this.place,
    required this.gradient,
    required this.icon,
  });

  final String caption;
  final String place;
  final List<Color> gradient;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: context.colors.ink.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.accent,
                child: Text(
                  'A',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Alex Tan',
                      style: TextStyle(
                        color: context.colors.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      '$place · Just now',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            caption,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: Colors.white.withValues(alpha: 0.9),
              size: 32,
            ),
          ),
        ],
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
    this.maxLines = 1,
    this.onChanged,
  });

  final TextEditingController controller;
  final IconData icon;
  final String hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      onChanged: onChanged,
      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
      decoration: InputDecoration(
        prefixIcon: maxLines == 1
            ? Icon(icon, color: context.colors.muted, size: 20)
            : null,
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
