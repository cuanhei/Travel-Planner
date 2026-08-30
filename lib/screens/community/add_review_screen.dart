import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

/// UI-only rating + written review submission form.
class AddReviewScreen extends StatefulWidget {
  const AddReviewScreen({super.key, required this.placeName});

  final String placeName;

  @override
  State<AddReviewScreen> createState() => _AddReviewScreenState();
}

class _AddReviewScreenState extends State<AddReviewScreen> {
  int _rating = 0;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.colors.ink,
        content: Text('Review for ${widget.placeName} posted!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(title: 'Write a Review', subtitle: widget.placeName),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 24),
                children: [
                  Text(
                    'Your rating',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final filled = i < _rating;
                      return IconButton(
                        onPressed: () => setState(() => _rating = i + 1),
                        icon: Icon(
                          filled
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: Color(0xFFFFB347),
                          size: 36,
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Your review',
                    style: TextStyle(
                      color: context.colors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: _controller,
                    maxLines: 6,
                    style: TextStyle(color: context.colors.ink),
                    decoration: InputDecoration(
                      hintText: 'Share details of your experience…',
                      hintStyle: TextStyle(color: context.colors.muted),
                      filled: true,
                      fillColor: context.colors.card,
                      contentPadding: EdgeInsets.all(16),
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
                    ),
                  ),
                  SizedBox(height: 28),
                  GradientButton(
                    label: 'Post Review',
                    onPressed: _rating > 0 ? _submit : () {},
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
