import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

bool get cameraAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);
