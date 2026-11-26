import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import '../../core/firebase_service.dart';
import '../../core/localization.dart';
import '../../core/notification_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/tts_service.dart';
import '../../data/auth_repository.dart';
import '../../data/family_repository.dart';
import '../../data/medicine_repository.dart';
import '../../domain/models.dart';
import '../ai/serbom_ai_screen.dart';
import '../auth/login_screen.dart';
import '../documents/medical_documents_screen.dart';
import '../family/family_group_screen.dart';
import '../family/family_screen.dart';
import '../medicines/medicines_screen.dart';
import '../shell/app_shell.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/continuous_rtl_scroll_view.dart';
import '../widgets/date_range_picker_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/icon_tile_button.dart';
import '../widgets/pill_button.dart';
import '../widgets/section_header.dart';
import '../widgets/soft_card.dart';
import '../widgets/soft_text_field.dart';
import '../widgets/stat_card.dart';
import '../widgets/status_pill.dart';
import '../widgets/voice_settings_dialog.dart';

class DashboardScreen extends StatefulWidget {
  final UserModel user;

  const DashboardScreen({super.key, required this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final _familyRepo = FamilyRepository();
  final _medRepo = MedicineRepository();

  List<FamilyMemberModel> _monitoredMembers = [];
  List<DoseSyncModel> _upcomingDoses = [];
  List<DoseHistoryModel> _adherenceHistory = [];
  bool _isLoading = true;

  List<FamilyGroupModel> _allFamilies = [];
  FamilyGroupModel? _activeFamily;

  Timer? _autoReminderTimer;
  Timer? _realtimePollTimer;
  final Set<String> _voicedDoseKeys = {};

  String? _selectedFilterMemberId;

  DateTime? _filterFromDate;
  DateTime? _filterToDate;
  bool _showDateFilter = false;

  final _storage = const FlutterSecureStorage();
  Set<String> _monitoredReminderMemberIds = {};
  bool _hasLoadedReminderPreferences = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _autoReminderTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkAutoVoiceReminders());
    _realtimePollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadDashboardData(silent: true));
  }

  @override
  void dispose() {
    _autoReminderTimer?.cancel();
    _realtimePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final members = await _familyRepo.getFamilyMembers();
      List<DoseSyncModel> doses = [];
      List<DoseHistoryModel> history = [];
      List<FamilyGroupModel> families = [];

      try {
        families = await _medRepo.getAllMyFamilyGroups();
        if (_activeFamily == null && families.isNotEmpty) {
          _activeFamily = families.first;
        }
      } catch (_) {}

      try {
        doses = await _medRepo.get48HourSyncWindow();
      } catch (_) {}

      try {
        history = await _medRepo.getAdherenceHistory(familyId: _activeFamily?.id);
      } catch (_) {}

      if (mounted) {
        setState(() {
          _monitoredMembers = members;
          _upcomingDoses = doses;
          _adherenceHistory = history;
          _allFamilies = families;
          if (_activeFamily == null && families.isNotEmpty) {
            _activeFamily = families.first;
          } else if (_activeFamily != null && families.isNotEmpty) {
            _activeFamily = families.firstWhere((f) => f.id == _activeFamily!.id, orElse: () => families.first);
          }
          if (_monitoredReminderMemberIds.isEmpty && members.isNotEmpty && !_hasLoadedReminderPreferences) {
            _monitoredReminderMemberIds = members.map((m) => m.id).toSet();
          }
          _isLoading = false;
        });

        if (!_hasLoadedReminderPreferences && members.isNotEmpty) {
          _hasLoadedReminderPreferences = true;
          _storage.read(key: 'reminder_sub_members_${widget.user.id}').then((saved) {
            if (saved != null && saved.isNotEmpty) {
              try {
                final List decoded = jsonDecode(saved);
                if (mounted) {
                  setState(() {
                    _monitoredReminderMemberIds = decoded.map((e) => e.toString()).toSet();
                  });
                }
              } catch (_) {}
            }
          });
        }
      }
    } catch (_) {
      if (!silent && mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _checkAutoVoiceReminders() {
    if (_upcomingDoses.isEmpty) return;
    final now = DateTime.now();

    for (final dose in _upcomingDoses) {
      if (_monitoredReminderMemberIds.isNotEmpty &&
          !_monitoredReminderMemberIds.contains(dose.targetMemberId)) {
        continue;
      }

      final currentStatus = _getDoseStatus(dose);
      if (currentStatus == 'Taken' || currentStatus == 'Missed' || currentStatus == 'Skipped') {
        continue;
      }

      DateTime? scheduled;
      final parsedUtc = DateTime.tryParse(dose.scheduledTimeUtc);
      if (parsedUtc != null) {
        scheduled = parsedUtc.toLocal();
      } else {
        final parts = dose.timeOfDay.split(':');
        if (parts.length >= 2) {
          final h = int.tryParse(parts[0].trim()) ?? 0;
          final m = int.tryParse(parts[1].split(' ')[0].trim()) ?? 0;
          scheduled = DateTime(now.year, now.month, now.day, h, m);
        }
      }

      if (scheduled != null) {
        final diffMinutes = now.difference(scheduled).inMinutes.abs();
        if (diffMinutes <= 3) {
          final doseKey = '${dose.scheduleId}_${scheduled.day}_${scheduled.hour}_${scheduled.minute}';
          if (!_voicedDoseKeys.contains(doseKey)) {
            _voicedDoseKeys.add(doseKey);
            _triggerVoiceReminder(dose);
            _showAutoReminderPopup(dose);

            NotificationService.instance.showReminderNotification(
              id: dose.scheduleId.hashCode,
              title: 'CareVoice: ${dose.targetMemberName} - ${dose.medicineName}',
              body: '${dose.targetMemberName} • ${dose.medicineName} (${dose.dosage}) scheduled at ${dose.timeOfDay}. Mark Taken or Not Taken.',
              scheduleId: dose.scheduleId,
              onTaken: () => _recordDoseAction(dose, 'Taken'),
              onMissed: () => _recordDoseAction(dose, 'Missed'),
            );
            break;
          }
        }
      }
    }
  }

  void _showAutoReminderPopup(DoseSyncModel dose) {
    if (!mounted) return;
    final lang = AppLanguage.instance;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SoftCard(
            backgroundColor: AppColors.creamLight,
            padding: const EdgeInsets.all(24),
            radius: AppRadius.modal,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: AppColors.butter,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.subtle,
                      ),
                      child: const Icon(Icons.alarm_on_rounded, color: AppColors.ink, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        lang.isBengali ? 'ওষুধ খাওয়ার সময় হয়েছে!' : 'Medicine Reminder!',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.mint.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_rounded, color: AppColors.forest, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${lang.translate('target_person')}: ${dose.targetMemberName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: AppColors.forest,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SoftCard(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.all(14),
                  radius: AppRadius.control,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.medication_rounded, color: AppColors.coral, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${dose.medicineName} (${dose.dosage})',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded, color: AppColors.muted, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '${lang.isBengali ? "নির্ধারিত সময়" : "Scheduled Time"}: ${dose.timeOfDay}',
                            style: const TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      if (dose.instructions != null && dose.instructions!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.muted, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${lang.translate('instructions')}: ${dose.instructions}',
                                style: const TextStyle(fontSize: 12, color: AppColors.muted),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  lang.isBengali ? 'দয়া করে ওষুধের অবস্থা নিশ্চিত করুন:' : 'Please confirm medicine status:',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.muted),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: lang.isBengali ? 'খেয়েছেন' : 'Taken',
                        icon: Icons.check_circle_rounded,
                        variant: PillButtonVariant.primary,
                        customColor: AppColors.taken,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _recordDoseAction(dose, 'Taken');
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: lang.isBengali ? 'খাননি' : 'Not Taken',
                        icon: Icons.cancel_rounded,
                        variant: PillButtonVariant.primary,
                        customColor: AppColors.missed,
                        onPressed: () {
                          Navigator.pop(ctx);
                          _recordDoseAction(dose, 'Missed');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showReminderSubscriptionsDialog() {
    final lang = AppLanguage.instance;
    final Set<String> tempSelected = Set.from(_monitoredReminderMemberIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final allSelected = _monitoredMembers.isNotEmpty &&
              tempSelected.length == _monitoredMembers.length;

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SoftCard(
                backgroundColor: AppColors.creamLight,
                padding: const EdgeInsets.all(24),
                radius: AppRadius.modal,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: AppColors.mint,
                            shape: BoxShape.circle,
                            boxShadow: AppShadows.subtle,
                          ),
                          child: const Icon(Icons.notifications_active_rounded, color: AppColors.forest, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            lang.isBengali ? 'রিমাইন্ডার গ্রহণের সদস্য নির্বাচন' : 'Reminder Subscriptions',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      lang.isBengali
                          ? 'যেসব পরিবারের সদস্যদের ওষুধের রিমাইন্ডার, ভয়েস অ্যালার্ট ও নোটিফিকেশন এই অ্যাকাউন্টে পেতে চান তা নির্বাচন করুন:'
                          : 'Select which family members\' medicine reminders and voice alerts you want to receive on this device:',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.sage.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            lang.isBengali
                                ? 'নির্বাচিত: ${tempSelected.length}/${_monitoredMembers.length}'
                                : 'Selected: ${tempSelected.length}/${_monitoredMembers.length}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.forest),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              if (allSelected) {
                                tempSelected.clear();
                              } else {
                                tempSelected.addAll(_monitoredMembers.map((m) => m.id));
                              }
                            });
                          },
                          child: Text(
                            allSelected
                                ? (lang.isBengali ? 'সব বাদ দিন' : 'Deselect All')
                                : (lang.isBengali ? 'সব নির্বাচন' : 'Select All'),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.coral),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: _monitoredMembers.map((member) {
                            final isChecked = tempSelected.contains(member.id);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: SoftCard(
                                backgroundColor: isChecked ? Colors.white : AppColors.creamLight,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                radius: AppRadius.control,
                                child: CheckboxListTile(
                                  value: isChecked,
                                  activeColor: AppColors.forest,
                                  contentPadding: EdgeInsets.zero,
                                  secondary: AvatarBadge(
                                    name: member.fullName,
                                    relation: member.relation,
                                    size: 36,
                                    showRelationBadge: false,
                                  ),
                                  title: Text(
                                    member.fullName + (member.isSelf ? ' (${lang.translate('filter_self')})' : ''),
                                    style: TextStyle(
                                      fontWeight: isChecked ? FontWeight.w800 : FontWeight.w600,
                                      color: AppColors.ink,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${lang.translate('relation')}: ${member.relation}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                  ),
                                  onChanged: (val) {
                                    setDialogState(() {
                                      if (val == true) {
                                        tempSelected.add(member.id);
                                      } else {
                                        tempSelected.remove(member.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: PillButton(
                            label: lang.translate('cancel'),
                            variant: PillButtonVariant.subtle,
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PillButton(
                            label: lang.translate('save'),
                            icon: Icons.check_rounded,
                            variant: PillButtonVariant.primary,
                            onPressed: () async {
                              Navigator.pop(ctx);
                              setState(() {
                                _monitoredReminderMemberIds = Set.from(tempSelected);
                              });

                              final rawJson = jsonEncode(_monitoredReminderMemberIds.toList());
                              await _storage.write(
                                key: 'reminder_sub_members_${widget.user.id}',
                                value: rawJson,
                              );

                              if (_activeFamily != null) {
                                try {
                                  await FirebaseService.instance.syncReminderSubscriptionsToFirestore(
                                    userEmail: widget.user.email,
                                    familyId: _activeFamily!.id,
                                    monitoredMemberIds: _monitoredReminderMemberIds.toList(),
                                  );
                                } catch (_) {}
                              }

                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      lang.isBengali
                                          ? 'রিমাইন্ডার গ্রহণের সদস্য তালিকা আপডেট হয়েছে (${_monitoredReminderMemberIds.length} জন সক্রিয়)'
                                          : 'Reminder subscriptions updated (${_monitoredReminderMemberIds.length} members active)',
                                    ),
                                    backgroundColor: AppColors.forest,
                                  ),
                                );
                              }
                              _checkAutoVoiceReminders();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _getDoseStatus(DoseSyncModel dose) {
    final now = DateTime.now();
    final todayLogs = _adherenceHistory.where((h) {
      if (h.scheduleId != dose.scheduleId) return false;
      final dt = DateTime.tryParse(h.scheduledTime);
      return dt != null && dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();

    if (todayLogs.isNotEmpty) {
      return todayLogs.first.status;
    }
    return 'Pending';
  }

  void _triggerVoiceReminder(DoseSyncModel dose) {
    final lang = AppLanguage.instance;
    final langCode = TtsService.getEffectiveLanguage(fallbackLanguage: dose.preferredLanguage);

    if (!TtsService.isVoiceReminderEnabled) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.volume_off_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lang.isBengali
                      ? 'ভয়েস রিমাইন্ডার বন্ধ রয়েছে। শুনতে উপরের ভয়েস বাটনে চাপ দিয়ে ON করুন।'
                      : 'Voice reminders are muted. Tap the Voice chip above to enable [ON].',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: AppColors.coral,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.volume_up_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                lang.isBengali
                    ? '🔊 ${dose.medicineName} ওষুধ অনুস্মারক বাজছে...'
                    : '🔊 Playing voice reminder for ${dose.medicineName}...',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: AppColors.forest,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );

    TtsService.speakReminder(
      recipientName: dose.targetMemberName,
      medicineName: dose.medicineName,
      dosage: dose.dosage,
      instructions: dose.instructions ?? (lang.isBengali ? 'পানির সাথে খান' : 'Take with water'),
      language: langCode,
    );
  }

  String _generateUuid() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    return [
      values.sublist(0, 4).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(4, 6).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(6, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(8, 10).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      values.sublist(10, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    ].join('-');
  }

  Future<void> _recordDoseAction(DoseSyncModel dose, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    final clientLogId = _generateUuid();

    setState(() {
      _adherenceHistory.removeWhere((h) =>
          h.scheduleId == dose.scheduleId &&
          DateTime.tryParse(h.scheduledTime)?.day == DateTime.now().day);
      _adherenceHistory.insert(
        0,
        DoseHistoryModel(
          logId: clientLogId,
          clientLogId: clientLogId,
          scheduleId: dose.scheduleId,
          medicineName: dose.medicineName,
          dosage: dose.dosage,
          targetMemberId: dose.targetMemberId,
          targetMemberName: dose.targetMemberName,
          scheduledTime: dose.scheduledTimeUtc,
          actionTime: DateTime.now().toUtc().toIso8601String(),
          status: status,
        ),
      );
    });

    await _medRepo.logDoseAction(
      clientLogId: clientLogId,
      scheduleId: dose.scheduleId,
      targetMemberId: dose.targetMemberId,
      scheduledTime: dose.scheduledTimeUtc,
      status: status,
    );

    try {
      final familyId = _activeFamily?.id ?? 'family_default';
      final nowIso = DateTime.now().toUtc().toIso8601String();

      await FirebaseService.instance.syncDoseLogToFirestore(
        familyId: familyId,
        clientLogId: clientLogId,
        scheduleId: dose.scheduleId,
        medicineName: dose.medicineName,
        dosage: dose.dosage,
        targetMemberName: dose.targetMemberName,
        status: status,
        scheduledTime: dose.scheduledTimeUtc,
        actionTime: nowIso,
        actorName: widget.user.fullName,
      );

      await FirebaseService.instance.updateScheduleStatus(
        familyId: familyId,
        scheduleId: dose.scheduleId,
        status: status,
        lastTakenTime: nowIso,
      );

      FirebaseService.instance.broadcastFamilyUpdate(
        familyId: familyId,
        type: 'dose_$status',
        title: '${dose.medicineName} marked as $status',
        titleBn: '${dose.medicineName} - ${status == "Taken" ? "খেয়েছেন" : "খাননি"} হিসেবে চিহ্নিত',
        description: '${dose.targetMemberName}: ${dose.dosage} (${status == "Taken" ? "Taken" : "Not Taken"})',
        descriptionBn: '${dose.targetMemberName}: ${dose.dosage} (${status == "Taken" ? "খেয়েছেন" : "খাননি"})',
        actorName: widget.user.fullName,
      );
    } catch (_) {}

    final isBn = AppLanguage.instance.isBengali || dose.preferredLanguage.toLowerCase().contains('bn');
    if (status == 'Taken') {
      TtsService.speak(
        isBn
            ? '${dose.medicineName} ওষুধ সফলভাবে নেওয়া হয়েছে।'
            : 'Great job! ${dose.medicineName} marked as taken.',
        language: dose.preferredLanguage,
      );
    } else if (status == 'Not Taken' || status == 'Missed') {
      TtsService.speak(
        isBn
            ? '${dose.medicineName} ওষুধ নেওয়া হয়নি হিসেবে চিহ্নিত।'
            : '${dose.medicineName} marked as not taken.',
        language: dose.preferredLanguage,
      );
    }

    if (!mounted) return;
    final lang = AppLanguage.instance;
    final statusText = status == 'Taken'
        ? lang.translate('status_taken')
        : status == 'Snoozed'
            ? lang.translate('status_snoozed')
            : status == 'Skipped'
                ? lang.translate('status_skipped')
                : lang.translate('status_missed');

    messenger.showSnackBar(
      SnackBar(
        content: Text('${lang.isBengali ? "ওষুধের অবস্থা" : "Dose status"}: $statusText (Saved & synced)'),
        backgroundColor: status == 'Taken'
            ? AppColors.taken
            : status == 'Missed'
                ? AppColors.missed
                : AppColors.forest,
      ),
    );

    await _loadDashboardData(silent: true);
  }

  void _openSerbomAi() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SerbomAiScreen(
          members: _monitoredMembers,
          initialMemberId: _selectedFilterMemberId,
        ),
      ),
    ).then((_) => _loadDashboardData());
  }

  bool get _isTodayFilterActive {
    if (_filterFromDate == null || _filterToDate == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(_filterFromDate!.year, _filterFromDate!.month, _filterFromDate!.day);
    final to = DateTime(_filterToDate!.year, _filterToDate!.month, _filterToDate!.day);
    return from == today && to == today;
  }

  void _applyTodayFilter() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _filterFromDate = today;
      _filterToDate = today;
      _showDateFilter = false;
    });
  }

  void _clearDateFilter() {
    setState(() {
      _filterFromDate = null;
      _filterToDate = null;
      _showDateFilter = false;
    });
  }

  List<DoseSyncModel> get _filteredDoses {
    var list = _selectedFilterMemberId == null
        ? _upcomingDoses
        : _upcomingDoses.where((d) => d.targetMemberId == _selectedFilterMemberId).toList();

    if (_filterFromDate != null) {
      final from = DateTime(_filterFromDate!.year, _filterFromDate!.month, _filterFromDate!.day);
      list = list.where((d) {
        final dt = DateTime.tryParse(d.scheduledTimeUtc)?.toLocal();
        if (dt == null) return true;
        final doseDate = DateTime(dt.year, dt.month, dt.day);
        return !doseDate.isBefore(from);
      }).toList();
    }
    if (_filterToDate != null) {
      final to = DateTime(_filterToDate!.year, _filterToDate!.month, _filterToDate!.day);
      list = list.where((d) {
        final dt = DateTime.tryParse(d.scheduledTimeUtc)?.toLocal();
        if (dt == null) return true;
        final doseDate = DateTime(dt.year, dt.month, dt.day);
        return !doseDate.isAfter(to);
      }).toList();
    }
    return list;
  }

  List<DoseHistoryModel> get _filteredHistory {
    var list = _selectedFilterMemberId == null
        ? _adherenceHistory
        : _adherenceHistory.where((h) => h.targetMemberId == _selectedFilterMemberId).toList();

    if (_filterFromDate != null) {
      final from = DateTime(_filterFromDate!.year, _filterFromDate!.month, _filterFromDate!.day);
      list = list.where((h) {
        final actionDt = h.actionTime != null ? DateTime.tryParse(h.actionTime!)?.toLocal() : null;
        final dt = DateTime.tryParse(h.scheduledTime)?.toLocal() ?? actionDt;
        if (dt == null) return true;
        final historyDate = DateTime(dt.year, dt.month, dt.day);
        return !historyDate.isBefore(from);
      }).toList();
    }
    if (_filterToDate != null) {
      final to = DateTime(_filterToDate!.year, _filterToDate!.month, _filterToDate!.day);
      list = list.where((h) {
        final actionDt = h.actionTime != null ? DateTime.tryParse(h.actionTime!)?.toLocal() : null;
        final dt = DateTime.tryParse(h.scheduledTime)?.toLocal() ?? actionDt;
        if (dt == null) return true;
        final historyDate = DateTime(dt.year, dt.month, dt.day);
        return !historyDate.isAfter(to);
      }).toList();
    }
    return list;
  }

  List<DoseHistoryModel> get _missedLogs {
    return _adherenceHistory.where((h) => h.status.toLowerCase() == 'missed').toList();
  }

  Widget _buildCaretakerAlertBanner(AppLanguage lang) {
    if (!widget.user.isCaretaker) return const SizedBox.shrink();

    final missedList = _missedLogs;
    if (missedList.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: SoftCard(
        backgroundColor: AppColors.peach.withValues(alpha: 0.35),
        radius: AppRadius.card,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.coral,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    lang.translate('caretaker_missed_alert'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: AppColors.missed),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.missed,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    '${missedList.length} ${lang.translate('status_missed')}',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...missedList.take(3).map((m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.5),
                  child: Row(
                    children: [
                      const Text('• ', style: TextStyle(color: AppColors.missed, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: Text(
                          '${m.targetMemberName}: ${m.medicineName} (${m.dosage})',
                          style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonFilterBar(AppLanguage lang) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.tune_rounded, size: 16, color: AppColors.forest),
            const SizedBox(width: 6),
            Text(
              lang.translate('filter_by_person'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.forest),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ContinuousRtlScrollView(
          children: [
            ChoiceChip(
              label: Text(
                lang.translate('filter_all'),
                style: TextStyle(
                  fontWeight: _selectedFilterMemberId == null ? FontWeight.w900 : FontWeight.w600,
                  color: _selectedFilterMemberId == null ? Colors.white : AppColors.ink,
                  fontSize: 12.5,
                ),
              ),
              selected: _selectedFilterMemberId == null,
              selectedColor: AppColors.forest,
              backgroundColor: AppColors.creamLight,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                side: BorderSide(
                  color: _selectedFilterMemberId == null ? Colors.transparent : AppColors.muted.withValues(alpha: 0.2),
                ),
              ),
              onSelected: (val) {
                if (val) setState(() => _selectedFilterMemberId = null);
              },
            ),
            ..._monitoredMembers.map((m) {
              final isSelected = _selectedFilterMemberId == m.id;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  avatar: AvatarBadge(
                    name: m.fullName,
                    relation: m.relation,
                    size: 24,
                    showRelationBadge: false,
                  ),
                  label: Text(
                    '${m.fullName}${m.isSelf ? ' (${lang.translate('filter_self')})' : ''}',
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.ink,
                      fontSize: 12.5,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: AppColors.forest,
                  backgroundColor: AppColors.creamLight,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    side: BorderSide(
                      color: isSelected ? Colors.transparent : AppColors.muted.withValues(alpha: 0.2),
                    ),
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedFilterMemberId = m.id);
                  },
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildFamilySwitcherBar(AppLanguage lang) {
    return SoftCard(
      backgroundColor: AppColors.creamLight,
      radius: AppRadius.control,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: AppColors.sage,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_rounded, color: AppColors.forest, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      lang.isBengali ? 'সক্রিয় পরিবার:' : 'Active Family:',
                      style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 6),
                    if (_activeFamily != null && _activeFamily!.familyCode.isNotEmpty)
                      Tooltip(
                        message: lang.isBengali ? 'কোড কপি করুন' : 'Copy Family Code',
                        child: InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: _activeFamily!.familyCode));
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(lang.isBengali
                                    ? 'ফ্যামিলি কোড কপি করা হয়েছে (${_activeFamily!.familyCode})'
                                    : 'Family Code copied (${_activeFamily!.familyCode})'),
                                backgroundColor: AppColors.forest,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: AppColors.mint,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(color: AppColors.forest.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.copy_rounded, size: 11, color: AppColors.forest),
                                const SizedBox(width: 4),
                                Text(
                                  _activeFamily!.familyCode,
                                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900, color: AppColors.forest),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if (_allFamilies.length > 1)
                  DropdownButton<String>(
                    value: _allFamilies.any((fam) => fam.id == _activeFamily?.id)
                        ? _activeFamily?.id
                        : (_allFamilies.isNotEmpty ? _allFamilies.first.id : null),
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: _allFamilies.map((fam) {
                      return DropdownMenuItem<String>(
                        value: fam.id,
                        child: Text(
                          '${fam.name} (${fam.familyCode})',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (newId) {
                      if (newId != null) {
                        setState(() {
                          _activeFamily = _allFamilies.firstWhere((f) => f.id == newId);
                        });
                        _loadDashboardData();
                      }
                    },
                  )
                else
                  Text(
                    _activeFamily?.name ?? (lang.isBengali ? 'আমার পরিবার' : 'My Family'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded, color: AppColors.forest),
            tooltip: 'Family Options',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
            onSelected: (val) {
              if (val == 'create') {
                _showCreateFamilyDialog();
              } else if (val == 'join') {
                _showJoinFamilyDialog();
              } else if (val == 'manage') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FamilyGroupScreen()),
                ).then((_) => _loadDashboardData());
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'manage',
                child: Row(
                  children: [
                    const Icon(Icons.settings_rounded, size: 18, color: AppColors.forest),
                    const SizedBox(width: 8),
                    Text(lang.isBengali ? 'পরিবার পরিচালনা' : 'Manage Families', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'create',
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline_rounded, size: 18, color: AppColors.forest),
                    const SizedBox(width: 8),
                    Text(lang.isBengali ? 'নতুন পরিবার তৈরি' : 'Create New Family', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'join',
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, size: 18, color: AppColors.forest),
                    const SizedBox(width: 8),
                    Text(lang.isBengali ? 'কোড দিয়ে যোগ দিন' : 'Join with Family Code', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showCreateFamilyDialog() {
    final nameCtrl = TextEditingController();
    final lang = AppLanguage.instance;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SoftCard(
            backgroundColor: AppColors.creamLight,
            padding: const EdgeInsets.all(24),
            radius: AppRadius.modal,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  lang.isBengali ? 'নতুন পরিবার গ্রুপ তৈরি করুন' : 'Create New Family Circle',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                ),
                const SizedBox(height: 16),
                SoftTextField(
                  controller: nameCtrl,
                  labelText: lang.isBengali ? 'পরিবারের নাম *' : 'Family Name *',
                  hintText: 'e.g. Mandal Family',
                  prefixIcon: Icons.family_restroom_rounded,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: lang.translate('cancel'),
                        variant: PillButtonVariant.subtle,
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PillButton(
                        label: lang.translate('save'),
                        variant: PillButtonVariant.primary,
                        onPressed: () async {
                          final name = nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          Navigator.pop(ctx);
                          try {
                            final group = await _medRepo.createFamilyGroup(name);
                            await _loadDashboardData();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Family "${group.name}" created! Family Code: ${group.familyCode}'),
                                  backgroundColor: AppColors.forest,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showJoinFamilyDialog() {
    final codeCtrl = TextEditingController();
    final otpCtrl = TextEditingController();
    final lang = AppLanguage.instance;
    bool otpSent = false;
    bool isSendingOtp = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: SoftCard(
              backgroundColor: AppColors.creamLight,
              padding: const EdgeInsets.all(24),
              radius: AppRadius.modal,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    lang.isBengali ? 'পরিবারে যোগ দিন' : 'Join Family Circle',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                  ),
                  const SizedBox(height: 16),
                  SoftTextField(
                    controller: codeCtrl,
                    labelText: lang.isBengali ? 'পারিবারিক কোড *' : 'Family Code *',
                    hintText: 'e.g. FAM-1234',
                    prefixIcon: Icons.qr_code_rounded,
                  ),
                  const SizedBox(height: 12),
                  if (!otpSent)
                    PillButton(
                      label: lang.isBengali ? 'ইমেইল OTP পাঠান' : 'Send Verification OTP',
                      icon: Icons.mark_email_read_rounded,
                      variant: PillButtonVariant.outlined,
                      isLoading: isSendingOtp,
                      onPressed: () async {
                        setDialogState(() => isSendingOtp = true);
                        try {
                          final authRepo = AuthRepository();
                          await authRepo.sendOtp(email: widget.user.email, purpose: 'JoinFamily');
                          setDialogState(() {
                            otpSent = true;
                            isSendingOtp = false;
                          });
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Verification OTP sent to ${widget.user.email}'),
                                backgroundColor: AppColors.forest,
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() => isSendingOtp = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('OTP failed: $e')),
                            );
                          }
                        }
                      },
                    )
                  else ...[
                    SoftTextField(
                      controller: otpCtrl,
                      keyboardType: TextInputType.number,
                      labelText: '6-Digit Email OTP *',
                      hintText: '123456',
                      prefixIcon: Icons.pin_rounded,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: lang.translate('cancel'),
                          variant: PillButtonVariant.subtle,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: PillButton(
                          label: lang.isBengali ? 'যোগ দিন' : 'Join Family',
                          variant: PillButtonVariant.primary,
                          onPressed: () async {
                            final code = codeCtrl.text.trim();
                            if (code.isEmpty) return;
                            Navigator.pop(ctx);
                            try {
                              final group = await _medRepo.joinFamilyGroupByCode(
                                code,
                                otp: otpCtrl.text.trim().isNotEmpty ? otpCtrl.text.trim() : null,
                              );
                              await _loadDashboardData();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Successfully joined family: ${group.name}'),
                                    backgroundColor: AppColors.forest,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
                                );
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroGreetingCard(AppLanguage lang) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? (lang.isBengali ? 'সুপ্রভাত' : 'Good Morning')
        : (hour < 17
            ? (lang.isBengali ? 'শুভ অপরাহ্ন' : 'Good Afternoon')
            : (lang.isBengali ? 'শুভ সন্ধ্যা' : 'Good Evening'));

    final totalToday = _upcomingDoses.length;
    final takenToday = _adherenceHistory.where((h) => h.status.toLowerCase() == 'taken').length;

    return SoftCard(
      backgroundColor: AppColors.creamLight,
      radius: AppRadius.card,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting, ${widget.user.fullName}!',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      lang.isBengali
                          ? 'আজকে $totalToday টি ওষুধের সূচী রয়েছে, যার মধ্যে $takenToday টি নেওয়া হয়েছে।'
                          : 'You have $totalToday scheduled doses today, with $takenToday taken so far. Keep up the healthy care routine!',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              AvatarBadge(
                name: widget.user.fullName,
                relation: widget.user.role == 'Caregiver' ? 'Care' : 'Self',
                size: 52,
                showRelationBadge: true,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              PillButton(
                label: lang.translate('add_medicine'),
                icon: Icons.add_rounded,
                variant: PillButtonVariant.primary,
                customColor: AppColors.coral,
                onPressed: () {
                  setState(() => _selectedIndex = 2);
                },
              ),
              PillButton(
                label: lang.translate('serbom_ai_title'),
                icon: Icons.auto_awesome_rounded,
                variant: PillButtonVariant.tinted,
                customColor: AppColors.butter,
                customTextColor: AppColors.ink,
                onPressed: _openSerbomAi,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCardsGrid(AppLanguage lang) {
    final dosesToday = _upcomingDoses.length;
    final takenToday = _adherenceHistory.where((h) => h.status.toLowerCase() == 'taken').length;
    final missedCount = _missedLogs.length;
    final adherenceRate = dosesToday == 0 ? 100 : ((takenToday / (dosesToday > 0 ? dosesToday : 1)) * 100).toInt();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 700;
        final count = isWide ? 4 : 2;
        final itemWidth = (constraints.maxWidth - ((count - 1) * 14)) / count;

        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            SizedBox(
              width: itemWidth,
              child: StatCard(
                title: lang.isBengali ? 'আজকের ওষুধ' : 'Doses Today',
                value: '$dosesToday',
                subtitle: lang.isBengali ? 'মোট সূচী' : 'Scheduled',
                icon: Icons.medication_rounded,
                accentColor: AppColors.forest,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: StatCard(
                title: lang.translate('status_taken'),
                value: '$takenToday',
                subtitle: lang.isBengali ? 'সঠিক সময়ে' : 'Confirmed',
                icon: Icons.check_circle_rounded,
                accentColor: AppColors.taken,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: StatCard(
                title: lang.translate('status_missed'),
                value: '$missedCount',
                subtitle: lang.isBengali ? 'যত্ন প্রয়োজন' : 'Needs Attention',
                icon: Icons.error_outline_rounded,
                accentColor: AppColors.missed,
              ),
            ),
            SizedBox(
              width: itemWidth,
              child: StatCard(
                title: lang.isBengali ? 'নিয়মানুবর্তিতা' : 'Adherence',
                value: '$adherenceRate%',
                subtitle: lang.isBengali ? 'সামগ্রিক হার' : 'Care Score',
                icon: Icons.local_fire_department_rounded,
                accentColor: AppColors.coral,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChartsSection(AppLanguage lang) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;

        final weeklyBarChart = SoftCard(
          backgroundColor: AppColors.creamLight,
          radius: AppRadius.card,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: lang.isBengali ? 'সাপ্তাহিক রুটিন' : 'Weekly Adherence',
                subtitle: lang.isBengali ? 'বিগত ৭ দিনের ডোজের হার' : 'Last 7 days adherence history',
                icon: Icons.bar_chart_rounded,
                iconColor: AppColors.forest,
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 160,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: 6,
                    barTouchData: BarTouchData(enabled: true),
                    titlesData: FlTitlesData(
                      show: true,
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                            final idx = value.toInt() % days.length;
                            return Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                days[idx],
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.muted),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: [
                      _buildBarGroup(0, 4, AppColors.butter),
                      _buildBarGroup(1, 5, AppColors.mint),
                      _buildBarGroup(2, 3, AppColors.peach),
                      _buildBarGroup(3, 6, AppColors.powder),
                      _buildBarGroup(4, 5, AppColors.coral),
                      _buildBarGroup(5, 4, AppColors.taken),
                      _buildBarGroup(6, 5, AppColors.forest),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

        final takenCount = _adherenceHistory.where((h) => h.status.toLowerCase() == 'taken').length.toDouble();
        final missedCount = _missedLogs.length.toDouble();
        final pendingCount = max(0, _upcomingDoses.length - takenCount.toInt()).toDouble();

        final donutChart = SoftCard(
          backgroundColor: AppColors.creamLight,
          radius: AppRadius.card,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: lang.isBengali ? 'আজকের স্থিতি' : 'Today\'s Breakdown',
                subtitle: lang.isBengali ? 'খেয়েছেন, অপেক্ষমান ও বাদ পড়া' : 'Taken, pending & missed distribution',
                icon: Icons.pie_chart_rounded,
                iconColor: AppColors.forest,
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 140,
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 4,
                          centerSpaceRadius: 34,
                          sections: [
                            PieChartSectionData(
                              value: takenCount > 0 ? takenCount : 1,
                              color: AppColors.taken,
                              title: '',
                              radius: 20,
                            ),
                            PieChartSectionData(
                              value: pendingCount > 0 ? pendingCount : 1,
                              color: AppColors.pending,
                              title: '',
                              radius: 20,
                            ),
                            if (missedCount > 0)
                              PieChartSectionData(
                                value: missedCount,
                                color: AppColors.missed,
                                title: '',
                                radius: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      flex: 6,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLegendDot(AppColors.taken, '${lang.translate('status_taken')} (${takenCount.toInt()})'),
                          const SizedBox(height: 8),
                          _buildLegendDot(AppColors.pending, '${lang.isBengali ? "অপেক্ষমান" : "Pending"} (${pendingCount.toInt()})'),
                          const SizedBox(height: 8),
                          _buildLegendDot(AppColors.missed, '${lang.translate('status_missed')} (${missedCount.toInt()})'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: weeklyBarChart),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: donutChart),
            ],
          );
        } else {
          return Column(
            children: [
              weeklyBarChart,
              const SizedBox(height: 16),
              donutChart,
            ],
          );
        }
      },
    );
  }

  BarChartGroupData _buildBarGroup(int x, double y, Color color) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
          toY: y,
          color: color,
          width: 16,
          borderRadius: BorderRadius.circular(8),
          backDrawRodData: BackgroundBarChartRodData(
            show: true,
            toY: 6,
            color: AppColors.cream.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.ink),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardHome(AppLanguage lang) {
    final filteredDoses = _filteredDoses;
    final filteredHistory = _filteredHistory;

    return RefreshIndicator(
      color: AppColors.forest,
      backgroundColor: AppColors.creamLight,
      onRefresh: () => _loadDashboardData(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFamilySwitcherBar(lang),
            const SizedBox(height: 16),

            _buildHeroGreetingCard(lang),
            const SizedBox(height: 20),

            _buildCaretakerAlertBanner(lang),

            _buildStatCardsGrid(lang),
            const SizedBox(height: 20),

            _buildChartsSection(lang),
            const SizedBox(height: 24),

            SectionHeader(
              title: '${lang.translate('family_members')} (${_monitoredMembers.length})',
              subtitle: lang.isBengali ? 'পরিবারের সদস্যদের ওপর নজর রাখুন' : 'Tap to filter medicine view',
              trailing: Row(
                children: [
                  IconTileButton(
                    icon: Icons.qr_code_2_rounded,
                    tooltip: lang.translate('family_group_title'),
                    iconColor: AppColors.forest,
                    backgroundColor: AppColors.sage,
                    size: 36,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const FamilyGroupScreen()),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    label: lang.translate('manage_family'),
                    variant: PillButtonVariant.tinted,
                    customColor: AppColors.sage,
                    customTextColor: AppColors.forest,
                    height: 36,
                    onPressed: () => setState(() => _selectedIndex = 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            if (_monitoredMembers.isEmpty)
              SoftCard(
                backgroundColor: AppColors.creamLight,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const AvatarBadge(name: 'Self', relation: 'Self', size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lang.translate('filter_self'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                          const Text('Primary Account', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _monitoredMembers.map((member) {
                    final isFiltered = _selectedFilterMemberId == member.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: SoftCard(
                        backgroundColor: isFiltered ? AppColors.mint : AppColors.creamLight,
                        radius: AppRadius.control,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        onTap: () {
                          setState(() {
                            _selectedFilterMemberId = isFiltered ? null : member.id;
                          });
                        },
                        child: Row(
                          children: [
                            AvatarBadge(
                              name: member.fullName,
                              relation: member.relation,
                              size: 34,
                              showRelationBadge: false,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  member.fullName,
                                  style: TextStyle(
                                    fontWeight: isFiltered ? FontWeight.w900 : FontWeight.w700,
                                    fontSize: 13,
                                    color: AppColors.ink,
                                  ),
                                ),
                                Text(
                                  '${member.relation}${member.isSelf ? ' (${lang.translate('filter_self')})' : ''}',
                                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            const SizedBox(height: 20),

            _buildPersonFilterBar(lang),
            const SizedBox(height: 16),

            SoftCard(
              backgroundColor: (_filterFromDate != null || _filterToDate != null)
                  ? AppColors.mint.withValues(alpha: 0.3)
                  : AppColors.creamLight,
              radius: AppRadius.control,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.forest),
                          const SizedBox(width: 8),
                          Text(
                            lang.translate('filter_by_date'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: AppColors.ink),
                          ),
                        ],
                      ),
                      if (_filterFromDate != null || _filterToDate != null)
                        TextButton.icon(
                          icon: const Icon(Icons.clear_rounded, size: 14, color: AppColors.missed),
                          label: Text(
                            lang.translate('clear_date_filter'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.missed),
                          ),
                          onPressed: _clearDateFilter,
                        )
                      else
                        IconButton(
                          icon: Icon(
                            _showDateFilter ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            size: 22,
                            color: AppColors.forest,
                          ),
                          onPressed: () => setState(() => _showDateFilter = !_showDateFilter),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          avatar: const Icon(Icons.all_inclusive_rounded, size: 16),
                          label: Text(
                            lang.isBengali ? 'সকল তারিখ' : 'All Dates',
                            style: TextStyle(
                              fontWeight: (_filterFromDate == null && _filterToDate == null) ? FontWeight.w900 : FontWeight.w600,
                              color: (_filterFromDate == null && _filterToDate == null) ? Colors.white : AppColors.ink,
                              fontSize: 12,
                            ),
                          ),
                          selected: _filterFromDate == null && _filterToDate == null,
                          selectedColor: AppColors.forest,
                          backgroundColor: AppColors.creamLight,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                          onSelected: (val) {
                            if (val) _clearDateFilter();
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.today_rounded, size: 16),
                          label: Text(
                            lang.isBengali ? 'আজ (Today)' : 'Today',
                            style: TextStyle(
                              fontWeight: _isTodayFilterActive ? FontWeight.w900 : FontWeight.w600,
                              color: _isTodayFilterActive ? Colors.white : AppColors.ink,
                              fontSize: 12,
                            ),
                          ),
                          selected: _isTodayFilterActive,
                          selectedColor: AppColors.forest,
                          backgroundColor: AppColors.creamLight,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                          onSelected: (val) {
                            if (val) {
                              _applyTodayFilter();
                            } else {
                              _clearDateFilter();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          avatar: const Icon(Icons.date_range_rounded, size: 16),
                          label: Text(
                            lang.isBengali ? 'তারিখের পরিসীমা' : 'Date Range',
                            style: TextStyle(
                              fontWeight: ((_filterFromDate != null || _filterToDate != null) && !_isTodayFilterActive) || _showDateFilter
                                  ? FontWeight.w900
                                  : FontWeight.w600,
                              color: ((_filterFromDate != null || _filterToDate != null) && !_isTodayFilterActive) || _showDateFilter
                                  ? Colors.white
                                  : AppColors.ink,
                              fontSize: 12,
                            ),
                          ),
                          selected: ((_filterFromDate != null || _filterToDate != null) && !_isTodayFilterActive) || _showDateFilter,
                          selectedColor: AppColors.forest,
                          backgroundColor: AppColors.creamLight,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
                          onSelected: (val) {
                            setState(() {
                              _showDateFilter = val;
                              if (val && _isTodayFilterActive) {
                                final now = DateTime.now();
                                _filterFromDate = DateTime(now.year, now.month, now.day);
                                _filterToDate = null;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  if (_isTodayFilterActive) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.taken.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.taken.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.taken),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              lang.isBengali
                                  ? 'আজকের (${DateFormat('dd MMM yyyy').format(DateTime.now())}) রেকর্ড প্রদর্শিত হচ্ছে'
                                  : 'Showing records for Today (${DateFormat('dd MMM yyyy').format(DateTime.now())})',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.forest,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_filterFromDate != null || _filterToDate != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.powder.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.forest.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.history_rounded, size: 16, color: AppColors.forest),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                final fromStr = _filterFromDate != null ? DateFormat('dd MMM yyyy').format(_filterFromDate!) : '';
                                final toStr = _filterToDate != null ? DateFormat('dd MMM yyyy').format(_filterToDate!) : '';
                                final rangeText = (_filterFromDate != null && _filterToDate != null)
                                    ? (_filterFromDate == _filterToDate ? fromStr : '$fromStr - $toStr')
                                    : (_filterFromDate != null ? 'From $fromStr' : 'Up to $toStr');

                                return Text(
                                  lang.isBengali
                                      ? 'নির্বাচিত তারিখের ফিল্টার: $rangeText'
                                      : 'Filtering by: $rangeText',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.forest,
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_showDateFilter || ((_filterFromDate != null || _filterToDate != null) && !_isTodayFilterActive)) ...[
                    const SizedBox(height: 12),
                    DateRangePickerWidget(
                      fromDate: _filterFromDate != null
                          ? DateTime(_filterFromDate!.year, _filterFromDate!.month, _filterFromDate!.day)
                          : DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
                      toDate: _filterToDate,
                      onFromDateChanged: (dt) => setState(() => _filterFromDate = DateTime(dt.year, dt.month, dt.day)),
                      onToDateChanged: (dt) => setState(() => _filterToDate = dt != null ? DateTime(dt.year, dt.month, dt.day) : null),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            SectionHeader(
              title: '${lang.translate('upcoming_reminders')} (${filteredDoses.length})',
              subtitle: lang.isBengali ? 'আজকের নির্ধারিত ওষুধের তালিকা' : 'Scheduled dosage and voice alerts',
              trailing: Row(
                children: [
                  IconTileButton(
                    icon: Icons.record_voice_over_rounded,
                    tooltip: lang.translate('voice_settings'),
                    iconColor: AppColors.forest,
                    backgroundColor: AppColors.mint,
                    size: 36,
                    onPressed: () => VoiceSettingsDialog.show(context),
                  ),
                  const SizedBox(width: 8),
                  PillButton(
                    label: lang.translate('manage_medicines'),
                    variant: PillButtonVariant.tinted,
                    customColor: AppColors.mint,
                    customTextColor: AppColors.forest,
                    height: 36,
                    onPressed: () => setState(() => _selectedIndex = 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: TtsService.voiceReminderEnabledNotifier,
                  builder: (context, isVoiceOn, _) {
                    return Tooltip(
                      message: isVoiceOn
                          ? (lang.isBengali ? 'ভয়েস বন্ধ করতে চাপ দিন' : 'Tap to mute voice alerts')
                          : (lang.isBengali ? 'ভয়েস চালু করতে চাপ দিন' : 'Tap to enable voice alerts'),
                      child: InkWell(
                        onTap: () async {
                          final next = !isVoiceOn;
                          await TtsService.setVoiceReminderEnabled(next);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  Icon(
                                    next ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      next
                                          ? (lang.isBengali
                                              ? 'ভয়েস রিমাইন্ডার সক্রিয় করা হয়েছে [ON]'
                                              : 'Voice Reminders Enabled [ON]')
                                          : (lang.isBengali
                                              ? 'ভয়েস রিমাইন্ডার বন্ধ করা হয়েছে [OFF]'
                                              : 'Voice Reminders Muted [OFF]'),
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: next ? AppColors.forest : AppColors.coral,
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isVoiceOn ? AppColors.mint : AppColors.coral.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                              color: isVoiceOn ? AppColors.forest.withValues(alpha: 0.3) : AppColors.coral,
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isVoiceOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                size: 14,
                                color: isVoiceOn ? AppColors.forest : AppColors.coral,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isVoiceOn
                                    ? (lang.isBengali ? 'ভয়েস: চালু' : 'Voice: ON')
                                    : (lang.isBengali ? 'ভয়েস: বন্ধ' : 'Voice: OFF'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: isVoiceOn ? AppColors.forest : AppColors.coral,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                ValueListenableBuilder<String>(
                  valueListenable: TtsService.voiceLanguageNotifier,
                  builder: (context, voiceLang, _) {
                    final isBn = voiceLang == 'bn';
                    final isEn = voiceLang == 'en';
                    final label = isBn
                        ? 'বাংলা'
                        : (isEn ? 'English' : '${lang.translate('voice_lang_auto')} (${lang.isBengali ? 'বাংলা' : 'English'})');

                    return InkWell(
                      onTap: () => VoiceSettingsDialog.show(context),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.mint,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.volume_up_rounded, size: 14, color: AppColors.forest),
                            const SizedBox(width: 6),
                            Text(
                              '${lang.translate('voice_reminder_active')}: $label',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.forest),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.tune_rounded, size: 12, color: AppColors.forest),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                InkWell(
                  onTap: _showReminderSubscriptionsDialog,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.butter,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.notifications_active_rounded, size: 14, color: AppColors.ink),
                        const SizedBox(width: 6),
                        Text(
                          lang.isBengali
                              ? 'অ্যালার্ট সদস্য (${_monitoredReminderMemberIds.length}/${_monitoredMembers.length})'
                              : 'Alerts (${_monitoredReminderMemberIds.length}/${_monitoredMembers.length})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.ink),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.tune_rounded, size: 12, color: AppColors.ink),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            if (filteredDoses.isEmpty)
              EmptyState(
                icon: Icons.alarm_on_rounded,
                title: lang.translate('no_reminders'),
                message: lang.isBengali
                    ? 'আজকের জন্য আর কোনো ওষুধের রিমাইন্ডার নেই।'
                    : 'All caught up! No pending medication reminders right now.',
                actionLabel: lang.translate('serbom_ai_title'),
                onAction: _openSerbomAi,
              ),

            ...filteredDoses.map((dose) {
              final doseStatus = _getDoseStatus(dose);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: SoftCard(
                  backgroundColor: AppColors.creamLight,
                  radius: AppRadius.card,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.mint,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.alarm_rounded, color: AppColors.forest, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Builder(
                                        builder: (context) {
                                          final parsed = DateTime.tryParse(dose.scheduledTimeUtc)?.toLocal();
                                          final isTomorrow = parsed != null && parsed.day != DateTime.now().day;
                                          final dateLabel = isTomorrow
                                              ? (lang.isBengali ? 'আগামীকাল • ' : 'Tomorrow • ')
                                              : (lang.isBengali ? 'আজ • ' : 'Today • ');
                                          return Text(
                                            '${dose.medicineName} • $dateLabel${dose.timeOfDay}',
                                            style: const TextStyle(
                                              fontSize: 15.5,
                                              fontWeight: FontWeight.w900,
                                              color: AppColors.ink,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                    StatusPill(status: doseStatus),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${lang.translate('target_person')}: ${dose.targetMemberName} | ${lang.translate('dosage')}: ${dose.dosage}',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.ink, fontWeight: FontWeight.w600),
                                ),
                                if (dose.instructions != null && dose.instructions!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      '${lang.translate('instructions')}: ${dose.instructions}',
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 4,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.person_add_alt_1_rounded, size: 13, color: AppColors.forest),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${lang.isBengali ? "তৈরি করেছেন" : "Created By"}: ${dose.createdBy.isNotEmpty ? dose.createdBy : "Self"}',
                                          style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.assignment_ind_rounded, size: 13, color: AppColors.forest),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${lang.isBengali ? "দায়িত্বপ্রাপ্ত" : "Assigned By"}: ${dose.assignedBy.isNotEmpty ? dose.assignedBy : dose.targetMemberName}',
                                          style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1, color: Color(0x1A4A3B2F)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconTileButton(
                                icon: Icons.volume_up_rounded,
                                tooltip: lang.translate('voice_reminder'),
                                iconColor: AppColors.forest,
                                backgroundColor: AppColors.mint,
                                size: 34,
                                onPressed: () => _triggerVoiceReminder(dose),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => VoiceSettingsDialog.show(context),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.sage.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text(
                                    (TtsService.voiceLanguage == 'bn' ||
                                            (TtsService.voiceLanguage == 'auto' &&
                                                dose.preferredLanguage.toLowerCase().startsWith('bn')))
                                        ? 'বাং ভয়েস'
                                        : 'Voice',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.forest),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              PillButton(
                                label: lang.isBengali ? 'খেয়েছেন' : 'Taken',
                                icon: Icons.check_circle_rounded,
                                variant: PillButtonVariant.primary,
                                customColor: AppColors.taken,
                                height: 38,
                                onPressed: () => _recordDoseAction(dose, 'Taken'),
                              ),
                              const SizedBox(width: 8),
                              PillButton(
                                label: lang.isBengali ? 'খাননি' : 'Not Taken',
                                icon: Icons.cancel_rounded,
                                variant: PillButtonVariant.primary,
                                customColor: AppColors.missed,
                                height: 38,
                                onPressed: () => _recordDoseAction(dose, 'Missed'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 24),

            SectionHeader(
              title: '${lang.translate('adherence_history')} (${filteredHistory.length})',
              subtitle: lang.isBengali ? 'বিগত দিনের ওষুধের লগ ও রেকর্ড' : 'Recent medication confirmations and status',
              icon: Icons.history_rounded,
              iconColor: AppColors.forest,
            ),
            const SizedBox(height: 8),

            if (filteredHistory.isEmpty)
              EmptyState(
                icon: Icons.history_rounded,
                title: lang.translate('no_history'),
                message: lang.isBengali
                    ? 'কোনো পূর্ববর্তী ওষুধ গ্রহণের ইতিহাস পাওয়া যায়নি।'
                    : 'No adherence history logs recorded yet.',
              ),

            ...filteredHistory.take(8).map((log) {
              final isTaken = log.status.toLowerCase() == 'taken';
              final statusColor = isTaken ? AppColors.taken : AppColors.missed;
              final statusIcon = isTaken ? Icons.check_circle_rounded : Icons.cancel_rounded;
              final localizedStatus = isTaken ? lang.translate('status_taken') : lang.translate('status_missed');

              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: SoftCard(
                  backgroundColor: AppColors.creamLight,
                  radius: AppRadius.control,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(statusIcon, color: statusColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${log.medicineName} (${log.dosage}) - ${log.targetMemberName}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${lang.isBengali ? "অবস্থা" : "Status"}: $localizedStatus • ${log.scheduledTime.length >= 16 ? log.scheduledTime.substring(0, 16).replaceAll('T', ' ') : log.scheduledTime}',
                              style: const TextStyle(fontSize: 11, color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _handleLogout() async {
    final nav = Navigator.of(context);
    await AuthRepository().logout();
    await const FlutterSecureStorage().deleteAll();
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final lang = AppLanguage.instance;

        return AppShell(
          user: widget.user,
          currentIndex: _selectedIndex,
          onIndexChanged: (index) {
            setState(() => _selectedIndex = index);
            if (index == 0) _loadDashboardData();
          },
          title: '${lang.translate('app_title')} - ${widget.user.fullName}',
          onNotificationTap: _showReminderSubscriptionsDialog,
          notificationCount: _missedLogs.length,
          onLogout: _handleLogout,
          onVoiceSettingsTap: () => VoiceSettingsDialog.show(context),
          onSerbomAiTap: _openSerbomAi,
          extraHeaderActions: [
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: lang.isBengali ? 'তথ্য রিফ্রেশ করুন' : 'Refresh & Save Updates',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await _medRepo.syncPendingActions();
                _loadDashboardData();
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(lang.isBengali ? 'সব তথ্য আপডেট করা হয়েছে!' : 'All updates are saved and up to date!'),
                    backgroundColor: AppColors.forest,
                  ),
                );
              },
            ),
          ],
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.coral,
                  ),
                )
              : _selectedIndex == 0
                  ? _buildDashboardHome(lang)
                  : _selectedIndex == 1
                      ? const FamilyScreen()
                      : _selectedIndex == 2
                          ? const MedicinesScreen()
                          : const MedicalDocumentsScreen(),
        );
      },
    );
  }
}
