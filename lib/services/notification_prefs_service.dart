import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@immutable
class NotificationPrefs {
  const NotificationPrefs({
    this.pushEnabled = false,
    this.tripRemindersEnabled = false,
    this.emailUpdatesEnabled = false,
    this.fcmToken,
  });

  final bool pushEnabled;
  final bool tripRemindersEnabled;
  final bool emailUpdatesEnabled;

  /// This device/browser's FCM registration token — set once
  /// `FcmService.enable()` succeeds, so a real push can be sent to this
  /// exact install later (e.g. from the Firebase Console's "Send test
  /// message" screen) without the app needing to be open to ask for it
  /// again.
  final String? fcmToken;

  factory NotificationPrefs.fromMetadata(Map<String, dynamic>? meta) => NotificationPrefs(
    pushEnabled: meta?['push_notifications'] as bool? ?? false,
    tripRemindersEnabled: meta?['trip_reminders'] as bool? ?? false,
    emailUpdatesEnabled: meta?['email_updates'] as bool? ?? false,
    fcmToken: meta?['fcm_token'] as String?,
  );
}

/// Persists the three Settings-screen notification toggles — plus this
/// device's FCM token once granted — to the signed-in user's Supabase auth
/// metadata (the same mechanism `ProfileService` already uses for
/// `full_name`), so they survive a reload/sign-out and follow the account
/// rather than resetting every time Settings opens.
class NotificationPrefsService {
  NotificationPrefsService._();

  static final NotificationPrefsService instance = NotificationPrefsService._();

  SupabaseClient get _client => Supabase.instance.client;

  final ValueNotifier<NotificationPrefs> current = ValueNotifier(const NotificationPrefs());

  void load() {
    current.value = NotificationPrefs.fromMetadata(_client.auth.currentUser?.userMetadata);
  }

  Future<void> _persist(NotificationPrefs next) async {
    current.value = next;
    await _client.auth.updateUser(
      UserAttributes(
        data: {
          'push_notifications': next.pushEnabled,
          'trip_reminders': next.tripRemindersEnabled,
          'email_updates': next.emailUpdatesEnabled,
          'fcm_token': next.fcmToken,
        },
      ),
    );
  }

  /// Turning push off also turns off trip reminders (a sub-preference of
  /// push) and drops the token, since it's no longer valid to use.
  Future<void> setPushEnabled(bool value, {String? fcmToken}) {
    final c = current.value;
    return _persist(
      NotificationPrefs(
        pushEnabled: value,
        tripRemindersEnabled: value ? c.tripRemindersEnabled : false,
        emailUpdatesEnabled: c.emailUpdatesEnabled,
        fcmToken: value ? (fcmToken ?? c.fcmToken) : null,
      ),
    );
  }

  Future<void> setTripRemindersEnabled(bool value) {
    final c = current.value;
    return _persist(
      NotificationPrefs(
        pushEnabled: c.pushEnabled,
        tripRemindersEnabled: value,
        emailUpdatesEnabled: c.emailUpdatesEnabled,
        fcmToken: c.fcmToken,
      ),
    );
  }

  Future<void> setEmailUpdatesEnabled(bool value) {
    final c = current.value;
    return _persist(
      NotificationPrefs(
        pushEnabled: c.pushEnabled,
        tripRemindersEnabled: c.tripRemindersEnabled,
        emailUpdatesEnabled: value,
        fcmToken: c.fcmToken,
      ),
    );
  }
}
