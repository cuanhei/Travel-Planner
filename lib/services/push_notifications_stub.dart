// Non-web platforms (desktop/mobile) have no browser Notification API to
// call — the app still runs, permission is simply never granted here.
bool get pushPermissionGranted => false;

bool get pushPermissionDenied => false;

void showLocalNotification(String title, String body) {}
