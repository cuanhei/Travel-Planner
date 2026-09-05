import 'package:flutter/material.dart';

import '../services/locale_service.dart';
import '../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: context.colors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel ?? tr('explore_see_all'),
              style: TextStyle(
                color: AppColors.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}
