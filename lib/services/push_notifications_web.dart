import 'package:web/web.dart' as web;

bool get pushPermissionGranted => web.Notification.permission == 'granted';

bool get pushPermissionDenied => web.Notification.permission == 'denied';

void showLocalNotification(String title, String body) {
  if (!pushPermissionGranted) return;
  web.Notification(title, web.NotificationOptions(body: body));
}
