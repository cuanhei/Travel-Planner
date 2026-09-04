import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';
import 'push_notifications.dart';

/// Wraps Firebase Cloud Messaging: requesting notification permission and
/// registering this device/browser for real push delivery. The resulting
/// token identifies this exact install — Firebase (or any server holding
/// it) can target a push at it specifically via the FCM API, including
/// from the Firebase Console's own "Send test message" screen.
class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();

  bool _foregroundListenerAttached = false;

  /// Requests permission and returns the FCM device token, or null if
  /// permission was denied or Firebase isn't configured yet (see
  /// `firebase_options.dart`).
  Future<String?> enable() async {
    if (!DefaultFirebaseOptions.isConfigured) return null;

    final settings = await FirebaseMessaging.instance.requestPermission();
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) return null;

    _attachForegroundListener();

    final token = await FirebaseMessaging.instance.getToken(vapidKey: DefaultFirebaseOptions.vapidKey);
    debugPrint('FCM permission status: ${settings.authorizationStatus}');
    return token;
  }

  /// FCM only auto-shows a system notification when the app/tab is in the
  /// background (handled by `web/firebase-messaging-sw.js`) — a message
  /// arriving while the tab is focused has to be displayed manually.
  void _attachForegroundListener() {
    if (_foregroundListenerAttached) return;
    _foregroundListenerAttached = true;
    FirebaseMessaging.onMessage.listen(
      (message) {
        debugPrint('FCM onMessage fired: notification=${message.notification?.title}/${message.notification?.body} data=${message.data}');
        final notification = message.notification;
        if (notification == null) return;
        showLocalNotification(notification.title ?? 'TravelPlanner', notification.body ?? '');
      },
      onError: (Object e) => debugPrint('FCM onMessage error: $e'),
    );
  }
}
