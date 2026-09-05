import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class JumpToLatestButton extends StatelessWidget {
  const JumpToLatestButton({super.key, required this.show, this.onTap});

  final bool show;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: context.colors.card,
            shape: const CircleBorder(),
            elevation: 3,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: context.colors.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
