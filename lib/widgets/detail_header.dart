import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Standard top bar for interior (pushed) screens: back button, title,
/// optional subtitle, and an optional trailing action.
class DetailHeader extends StatelessWidget {
  const DetailHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: context.colors.ink,
              size: 20,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: context.colors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (subtitle != null) ...[
                  SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: context.colors.muted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
