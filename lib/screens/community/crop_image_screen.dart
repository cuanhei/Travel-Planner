import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class CropImageScreen extends StatefulWidget {
  const CropImageScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CropImageScreen> createState() => _CropImageScreenState();
}

class _CropImageScreenState extends State<CropImageScreen> {
  final _controller = CropController();
  bool _cropping = false;
  bool _ready = false;

  void _confirm() {
    setState(() => _cropping = true);
    _controller.crop();
  }

  void _onCropped(CropResult result) {
    switch (result) {
      case CropSuccess(:final croppedImage):
        Navigator.of(context).pop(croppedImage);
      case CropFailure(:final cause):
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text('Could not crop image: $cause'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _cropping
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Expanded(
                    child: Text(
                      'Crop photo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: (!_ready || _cropping) ? null : _confirm,
                    child: _cropping
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Crop(
                controller: _controller,
                image: widget.imageBytes,
                baseColor: Colors.black,
                maskColor: Colors.black.withValues(alpha: 0.65),

                formatDetector: (_) => ImageFormat.jpeg,
                onCropped: _onCropped,
                onStatusChanged: (status) {
                  final ready = status == CropStatus.ready;
                  if (ready != _ready) setState(() => _ready = ready);
                },
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}
