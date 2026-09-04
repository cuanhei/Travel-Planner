import 'package:flutter/material.dart';

import '../models/avatar_config.dart';
import 'avatar_preview.dart';

/// Opens [photoUrl] full-screen over a dark scrim, pinch/scroll-zoomable via
/// [InteractiveViewer]. Dismiss with the close button, the system back
/// gesture, or tapping outside the image.
Future<void> showAvatarViewer(BuildContext context, String photoUrl) {
  return _showZoomViewer(
    context,
    child: Image.network(photoUrl, fit: BoxFit.contain),
  );
}

/// Same full-screen, pinch-zoomable presentation as [showAvatarViewer], but
/// for a designed avatar (see [AvatarPreview]) instead of an uploaded photo —
/// used when the profile's active avatar mode is `avatarDesign` rather than
/// `photo` (see `ProfileAvatarState`).
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
