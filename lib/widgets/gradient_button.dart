import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A pill-shaped call-to-action button with a gradient fill and soft glow.
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.colors = AppColors.horizon,
    this.foregroundColor = Colors.white,
    this.shadowColor,
    this.height = 56,
    this.expand = true,
    this.loading = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final List<Color> colors;
  final Color foregroundColor;
  final Color? shadowColor;
  final double height;
  final bool expand;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(height / 2),
        onTap: loading ? null : onPressed,
        child: Ink(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              BoxShadow(
                color: (shadowColor ?? colors.last).withValues(alpha: 0.15),
                blurRadius: 12,
                spreadRadius: -2,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: loading
                ? [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(foregroundColor),
                      ),
                    ),
                  ]
                : [
                    Text(
                      label,
                      style: TextStyle(
                        color: foregroundColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (icon != null) ...[
                      SizedBox(width: 8),
                      Icon(icon, color: foregroundColor, size: 20),
                    ],
                  ],
          ),
        ),
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
