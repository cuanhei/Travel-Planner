import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

void showComingSoon(BuildContext context, String feature) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: context.colors.ink,
      content: Text('$feature — coming soon'),
    ),
  );
}
