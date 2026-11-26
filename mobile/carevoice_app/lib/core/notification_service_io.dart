import 'dart:async';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import '../data/local_db.dart';
import '../domain/models.dart';
import 'firebase_service.dart';
import 'tts_service.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  NotificationServiceImpl.handleNotificationResponse(notificationResponse);
}

@pragma('vm:entry-point')
void medicineAlarmBackgroundCallback(int id) async {
  NotificationServiceImpl.handleBackgroundAlarmTrigger(id);
}

class NotificationServiceImpl {
  static final NotificationServiceImpl instance = NotificationServiceImpl._();
  NotificationServiceImpl._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  Timer? _realtimeTimer;

  Future<void> init() async {
    if (_isInitialized) return;
    try {
      tz_data.initializeTimeZones();
    } catch (_) {}

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await AndroidAlarmManager.initialize();
      } catch (_) {}
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (response) {
        handleNotificationResponse(response);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    _isInitialized = true;
    startRealtimeMonitoring();
  }

  /// Active in-app periodic watcher (ticks every 10 seconds)
  void startRealtimeMonitoring() {
    _realtimeTimer?.cancel();
    _realtimeTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      final now = DateTime.now();
      final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      try {
        final schedules = await LocalDatabase.getCachedSchedules();
        final medicines = await LocalDatabase.getCachedMedicines();
        final members = await LocalDatabase.getCachedMembers();
        final pendingLogs = await LocalDatabase.getPendingLogs();
        final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final todayDateOnly = DateTime(now.year, now.month, now.day);
        final dayMask = 1 << (now.weekday - 1);

        for (final s in schedules) {
          final parts = s.timeOfDay.split(':');
          if (parts.isEmpty) continue;
          final sHour = int.tryParse(parts[0]) ?? -1;
          final sMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? -1) : 0;
          if (sHour != now.hour || sMinute != now.minute) continue;

          if (s.daysOfWeekMask > 0 && (s.daysOfWeekMask & dayMask) == 0) {
            continue;
          }

          final med = medicines.firstWhere(
            (m) => m.id == s.medicineId || m.name.toLowerCase() == s.medicineName.toLowerCase(),
            orElse: () => MedicineModel(id: s.medicineId, name: s.medicineName, dosage: s.dosage, foodRelation: 'NoRelation'),
          );

          if (med.startDate != null) {
            final startDay = DateTime(med.startDate!.year, med.startDate!.month, med.startDate!.day);
            if (todayDateOnly.isBefore(startDay)) continue;
          }
          if (med.endDate != null) {
            final endDay = DateTime(med.endDate!.year, med.endDate!.month, med.endDate!.day);
            if (todayDateOnly.isAfter(endDay)) continue;
          }

          final alreadyTaken = pendingLogs.any((l) =>
              l['scheduleId'] == s.id &&
              (l['status'] == 'Taken' || l['status'] == 'taken') &&
              ((l['scheduledTime']?.toString().startsWith(todayStr) ?? false) ||
               (l['actionTime']?.toString().startsWith(todayStr) ?? false)));
          if (alreadyTaken) continue;

          final announcementKey = '${s.id}_${now.year}_${now.month}_${now.day}_$nowTime';
          final shouldAnnounce = await LocalDatabase.shouldAnnounceReminder(announcementKey);
          if (shouldAnnounce) {
            final member = members.firstWhere(
              (m) => m.id == s.targetMemberId,
              orElse: () => FamilyMemberModel(id: s.targetMemberId, fullName: 'Patient', relation: 'Self', preferredLanguage: 'bn', voicePreference: 'Female'),
            );


            if (TtsService.isVoiceReminderEnabled) {
              await TtsService.speakReminder(
                recipientName: member.fullName,
                medicineName: med.name,
                dosage: med.dosage,
                instructions: med.foodRelation != 'NoRelation' ? med.foodRelation : null,
                language: member.preferredLanguage,
              );
            }

            final isBn = member.preferredLanguage.startsWith('bn');
            await showReminderNotification(
              id: s.id.hashCode.abs() % 1000000,
              title: isBn ? '💊 ওষুধ স্মরণসূচী: ${med.name} (${med.dosage})' : '💊 Medicine Reminder: ${med.name} (${med.dosage})',
              body: isBn ? '${member.fullName}-এর জন্য ${med.name} খাওয়ার সময় হয়েছে।' : 'Time for ${member.fullName} to take ${med.name}.',
              scheduleId: s.id,
              payload: '${s.id}|${med.name}|${med.dosage}|${member.fullName}|${member.preferredLanguage}',
            );
          }
        }
      } catch (_) {}
    });
  }

  /// Headless Native Alarm callback executed by Android AlarmManager
  static Future<void> handleBackgroundAlarmTrigger(int id) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final schedules = await LocalDatabase.getCachedSchedules();
      final match = schedules.where((s) => (s.id.hashCode.abs() % 1000000) == id);
      if (match.isEmpty) return;
      final s = match.first;

      final now = DateTime.now();
      final dayMask = 1 << (now.weekday - 1);
      if (s.daysOfWeekMask > 0 && (s.daysOfWeekMask & dayMask) == 0) return;

      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final announcementKey = '${s.id}_${now.year}_${now.month}_${now.day}_$timeStr';

      final shouldAnnounce = await LocalDatabase.shouldAnnounceReminder(announcementKey);
      if (!shouldAnnounce) {
        return;
      }

      final medicines = await LocalDatabase.getCachedMedicines();
      final members = await LocalDatabase.getCachedMembers();

      final med = medicines.firstWhere(
        (m) => m.id == s.medicineId || m.name.toLowerCase() == s.medicineName.toLowerCase(),
        orElse: () => MedicineModel(id: s.medicineId, name: s.medicineName, dosage: s.dosage, foodRelation: 'NoRelation'),
      );

      final todayDateOnly = DateTime(now.year, now.month, now.day);
      if (med.startDate != null) {
        final startDay = DateTime(med.startDate!.year, med.startDate!.month, med.startDate!.day);
        if (todayDateOnly.isBefore(startDay)) return;
      }
      if (med.endDate != null) {
        final endDay = DateTime(med.endDate!.year, med.endDate!.month, med.endDate!.day);
        if (todayDateOnly.isAfter(endDay)) return;
      }

      final member = members.firstWhere(
        (m) => m.id == s.targetMemberId,
        orElse: () => FamilyMemberModel(id: s.targetMemberId, fullName: 'Patient', relation: 'Self', preferredLanguage: 'bn', voicePreference: 'Female'),
      );

      await TtsService.init();
      if (TtsService.isVoiceReminderEnabled) {
        await TtsService.speakReminder(
          recipientName: member.fullName,
          medicineName: med.name,
          dosage: med.dosage,
          instructions: med.foodRelation != 'NoRelation' ? med.foodRelation : null,
          language: member.preferredLanguage,
        );
      }

      await NotificationServiceImpl.instance.init();
      final isBn = member.preferredLanguage.startsWith('bn');
      await NotificationServiceImpl.instance.showReminderNotification(
        id: id,
        title: isBn ? '💊 ওষুধ স্মরণসূচী: ${med.name} (${med.dosage})' : '💊 Medicine Reminder: ${med.name} (${med.dosage})',
        body: isBn ? '${member.fullName}-এর জন্য ${med.name} খাওয়ার সময় হয়েছে।' : 'Time for ${member.fullName} to take ${med.name}.',
        scheduleId: s.id,
        payload: '${s.id}|${med.name}|${med.dosage}|${member.fullName}|${member.preferredLanguage}',
      );
    } catch (_) {}
  }

  static void handleNotificationResponse(NotificationResponse response) async {
    final payload = response.payload ?? '';
    final actionId = response.actionId ?? '';

    final parts = payload.split('|');
    final scheduleId = parts.isNotEmpty ? parts[0] : '';
    final medicineName = parts.length > 1 ? parts[1] : 'Medicine';
    final dosage = parts.length > 2 ? parts[2] : '';
    final targetMemberName = parts.length > 3 ? parts[3] : 'Patient';
    final preferredLanguage = parts.length > 4 ? parts[4] : 'en';

    if (actionId == 'action_taken' || actionId == 'action_missed') {
      final status = actionId == 'action_taken' ? 'Taken' : 'Not Taken';
      final clientLogId = 'log_${DateTime.now().millisecondsSinceEpoch}';

      await LocalDatabase.savePendingLog(
        clientLogId: clientLogId,
        scheduleId: scheduleId,
        targetMemberId: '',
        scheduledTime: DateTime.now().toUtc().toIso8601String(),
        actionTime: DateTime.now().toUtc().toIso8601String(),
        status: status,
      );

      FirebaseService.instance.syncDoseLogToFirestore(
        familyId: 'family_default',
        clientLogId: clientLogId,
        scheduleId: scheduleId,
        medicineName: medicineName,
        dosage: dosage,
        targetMemberName: targetMemberName,
        status: status,
        scheduledTime: DateTime.now().toUtc().toIso8601String(),
        actorName: 'User Notification Action',
      );

      FirebaseService.instance.updateScheduleStatus(
        familyId: 'family_default',
        scheduleId: scheduleId,
        status: status,
        lastTakenTime: DateTime.now().toUtc().toIso8601String(),
      );

      final isBn = preferredLanguage.startsWith('bn');
      if (status == 'Taken') {
        final text = isBn
            ? '$medicineName ওষুধ সফলভাবে নেওয়া হয়েছে।'
            : 'Great job! $medicineName marked as taken.';
        TtsService.speak(text, language: preferredLanguage);
      } else {
        final text = isBn
            ? '$medicineName ওষুধ নেওয়া হয়নি হিসেবে চিহ্নিত।'
            : '$medicineName marked as not taken.';
        TtsService.speak(text, language: preferredLanguage);
      }
    } else {
    }
  }

  Future<bool> requestPermissions() async {
    final android = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestExactAlarmsPermission();
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
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
    await init();

    const androidDetails = AndroidNotificationDetails(
      'medicine_reminders_channel',
      'Medicine Reminders',
      channelDescription: 'High priority alerts for scheduled medicine reminders',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      category: AndroidNotificationCategory.reminder,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_taken',
          'Taken',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'action_missed',
          'Not Taken',
          showsUserInterface: true,
        ),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload ?? scheduleId,
    );
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
    await init();

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'medicine_reminders_channel',
      'Medicine Reminders',
      channelDescription: 'High priority alerts for scheduled medicine reminders',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      category: AndroidNotificationCategory.reminder,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_taken',
          'Taken',
          showsUserInterface: true,
        ),
        AndroidNotificationAction(
          'action_missed',
          'Not Taken',
          showsUserInterface: true,
        ),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final payload = '$scheduleId|$medicineName|$dosage|$targetMemberName|${preferredLanguage ?? 'en'}';

    await _localNotifications.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload,
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final nativeDate = DateTime(
          scheduledDate.year,
          scheduledDate.month,
          scheduledDate.day,
          scheduledDate.hour,
          scheduledDate.minute,
        );
        await AndroidAlarmManager.oneShotAt(
          nativeDate,
          id,
          medicineAlarmBackgroundCallback,
          exact: true,
          wakeup: true,
          rescheduleOnReboot: true,
        );
      } catch (_) {}
    }

  }

  Future<void> cancelSchedule(int id) async {
    await _localNotifications.cancel(id: id);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await AndroidAlarmManager.cancel(id);
      } catch (_) {}
    }
  }

  Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }

  Future<void> syncAllSchedules() async {
    await init();
    final schedules = await LocalDatabase.getCachedSchedules();
    final medicines = await LocalDatabase.getCachedMedicines();
    final members = await LocalDatabase.getCachedMembers();

    for (var s in schedules) {
      final parts = s.timeOfDay.split(':');
      final hour = int.tryParse(parts[0]) ?? 8;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

      final med = medicines.firstWhere(
        (m) => m.id == s.medicineId || m.name.toLowerCase() == s.medicineName.toLowerCase(),
        orElse: () => MedicineModel(
          id: s.medicineId,
          name: s.medicineName,
          dosage: s.dosage,
          foodRelation: 'NoRelation',
        ),
      );

      final member = members.firstWhere(
        (m) => m.id == s.targetMemberId,
        orElse: () => FamilyMemberModel(
          id: s.targetMemberId,
          fullName: 'Family Member',
          relation: 'Member',
          preferredLanguage: 'en',
          voicePreference: 'en-US-Standard-A',
        ),
      );

      final isBn = member.preferredLanguage.startsWith('bn');
      final title = isBn
          ? '💊 ওষুধ স্মরণসূচী: ${med.name} (${med.dosage})'
          : '💊 Medicine Reminder: ${med.name} (${med.dosage})';
      final body = isBn
          ? '${member.fullName}-এর জন্য ${med.name} খাওয়ার সময় হয়েছে। গ্রহণের পর Taken এ চাপুন।'
          : 'Time for ${member.fullName} to take ${med.name}. Tap Taken or Not Taken.';

      final intId = s.id.hashCode.abs() % 1000000;

      await scheduleMedicineAlarm(
        id: intId,
        title: title,
        body: body,
        scheduleId: s.id,
        hour: hour,
        minute: minute,
        medicineName: med.name,
        dosage: med.dosage,
        targetMemberName: member.fullName,
        preferredLanguage: member.preferredLanguage,
      );
    }
  }
}
