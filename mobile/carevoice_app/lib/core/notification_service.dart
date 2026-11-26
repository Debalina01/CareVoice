import 'notification_service_io.dart'
    if (dart.library.html) 'notification_service_web.dart';

/// Central Notification Service for CareVoice
/// Handles in-app, system OS, background, and platform notifications with Taken/Not Taken actions
class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  Future<void> init() => NotificationServiceImpl.instance.init();

  Future<bool> requestPermissions() =>
      NotificationServiceImpl.instance.requestPermissions();

  Future<void> showReminderNotification({
    required int id,
    required String title,
    required String body,
    required String scheduleId,
    String? payload,
    Function()? onTaken,
    Function()? onMissed,
  }) =>
      NotificationServiceImpl.instance.showReminderNotification(
        id: id,
        title: title,
        body: body,
        scheduleId: scheduleId,
        payload: payload,
        onTaken: onTaken,
        onMissed: onMissed,
      );

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
  }) =>
      NotificationServiceImpl.instance.scheduleMedicineAlarm(
        id: id,
        title: title,
        body: body,
        scheduleId: scheduleId,
        hour: hour,
        minute: minute,
        medicineName: medicineName,
        dosage: dosage,
        targetMemberName: targetMemberName,
        preferredLanguage: preferredLanguage,
      );

  Future<void> cancelSchedule(int id) =>
      NotificationServiceImpl.instance.cancelSchedule(id);

  Future<void> cancelAll() =>
      NotificationServiceImpl.instance.cancelAll();

  Future<void> syncAllSchedules() =>
      NotificationServiceImpl.instance.syncAllSchedules();

  void startRealtimeMonitoring() =>
      NotificationServiceImpl.instance.startRealtimeMonitoring();
}
