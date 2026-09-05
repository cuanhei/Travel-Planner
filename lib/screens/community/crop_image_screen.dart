import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// One aspect-ratio preset offered below the crop viewport. `null` means
/// free-form (whatever rectangle the user drags).
class _AspectPreset {
  const _AspectPreset(this.label, this.icon, this.ratio);

  final String label;
  final IconData icon;
  final double? ratio;
}

const _presets = [
  _AspectPreset('Free', Icons.crop_free_rounded, null),
  _AspectPreset('1:1', Icons.crop_square_rounded, 1.0),
  _AspectPreset('4:5', Icons.crop_portrait_rounded, 4 / 5),
  _AspectPreset('16:9', Icons.crop_16_9_rounded, 16 / 9),
];

/// Full-screen photo cropper shown right after picking an image for a
/// Community post. Pops with the cropped JPEG bytes, or `null` if the user
/// backed out without confirming a crop.
///
/// Uses `crop_your_image` (pure-Dart/Flutter, no native platform views)
/// rather than the more common `image_cropper`, since this app also builds
/// for Windows/Linux where `image_cropper` has no implementation.
class CropImageScreen extends StatefulWidget {
  const CropImageScreen({super.key, required this.imageBytes});

  final Uint8List imageBytes;

  @override
  State<CropImageScreen> createState() => _CropImageScreenState();
}

class _CropImageScreenState extends State<CropImageScreen> {
  final _controller = CropController();
  int _presetIndex = 0;
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
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                    ),
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
                aspectRatio: _presets[_presetIndex].ratio,
                baseColor: Colors.black,
                maskColor: Colors.black.withValues(alpha: 0.65),
                // Always re-encode to JPEG regardless of the source format,
                // so the caller (AddPostScreen) doesn't need to sniff the
                // output bytes to know what extension/content-type to
                // upload with.
                formatDetector: (_) => ImageFormat.jpeg,
                onCropped: _onCropped,
                onStatusChanged: (status) {
                  final ready = status == CropStatus.ready;
                  if (ready != _ready) setState(() => _ready = ready);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_presets.length, (i) {
                  final preset = _presets[i];
                  final selected = _presetIndex == i;
                  return GestureDetector(
                    onTap: _cropping
                        ? null
                        : () => setState(() => _presetIndex = i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            preset.icon,
                            size: 20,
                            color: selected ? Colors.black : Colors.white70,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          preset.label,
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.white54,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
