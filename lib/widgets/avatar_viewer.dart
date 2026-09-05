import 'package:flutter/material.dart';

import '../models/avatar_config.dart';
import 'avatar_preview.dart';

Future<void> showAvatarViewer(BuildContext context, String photoUrl) {
  return _showZoomViewer(
    context,
    child: Image.network(photoUrl, fit: BoxFit.contain),
  );
}

Future<void> showAvatarDesignViewer(BuildContext context, AvatarConfig design) {
  return _showZoomViewer(
    context,
    child: AvatarPreview(config: design, width: 240, height: 300),
  );
}

Future<void> _showZoomViewer(BuildContext context, {required Widget child}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (context, _, _) => _ZoomViewer(child: child),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _ZoomViewer extends StatelessWidget {
  const _ZoomViewer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              behavior: HitTestBehavior.opaque,
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(child: child),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
