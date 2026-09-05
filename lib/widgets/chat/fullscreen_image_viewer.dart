import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({super.key, required this.url});

  final String url;

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Listener(
        onPointerSignal: _handlePointerSignal,
        child: GestureDetector(
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: _minScale,
            maxScale: _maxScale,
            child: Center(
              child: Image.network(widget.url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}
