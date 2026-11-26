// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

class NotificationServiceImpl {
  static final NotificationServiceImpl instance = NotificationServiceImpl._();
  NotificationServiceImpl._();

  Future<void> init() async {
    await requestPermissions();
  }

  Future<bool> requestPermissions() async {
    if (!html.Notification.supported) return false;
    final perm = await html.Notification.requestPermission();
    return perm == 'granted';
  }

  Future<void> showReminderNotification({
    required int id,
    required String title,
    required String body,
    required String scheduleId,
    String? payload,
    Function()? onTaken,
    Function()? onMissed,
  }) async {
    if (!html.Notification.supported) return;
    if (html.Notification.permission == 'granted') {
      final notif = html.Notification(
        title,
        body: body,
        icon: 'favicon.png',
        tag: scheduleId,
      );
      notif.onClick.listen((_) {
        notif.close();
      });
    } else if (html.Notification.permission != 'denied') {
      final perm = await html.Notification.requestPermission();
      if (perm == 'granted') {
        showReminderNotification(
          id: id,
          title: title,
          body: body,
          scheduleId: scheduleId,
          payload: payload,
          onTaken: onTaken,
          onMissed: onMissed,
        );
      }
    }
  }

  Future<void> scheduleMedicineAlarm({
    required int id,
    required String title,
    required String body,
    required String scheduleId,
    required int hour,
    required int minute,
    required String medicineName,
    required String dosage,
    required String targetMemberName,
    String? preferredLanguage,
  }) async {
  }

  Future<void> cancelSchedule(int id) async {}

  Future<void> cancelAll() async {}

  Future<void> syncAllSchedules() async {}

  void startRealtimeMonitoring() {}
}
