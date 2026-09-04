import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Whether `image_picker`'s `ImageSource.camera` can actually be used on
/// this platform — Android/iOS only; there's no camera implementation for
/// desktop, and web's is unreliable outside mobile browsers. Screens that
/// offer a "Take Photo"/"Record Video" option check this first and fall
/// back to a gallery-only pick when it's `false`.
bool get cameraAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
