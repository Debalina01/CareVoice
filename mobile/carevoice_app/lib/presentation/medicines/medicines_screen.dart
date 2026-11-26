import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/firebase_service.dart';
import '../../core/localization.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/notification_service.dart';
import '../../core/tts_service.dart';
import '../../data/medicine_repository.dart';
import '../../data/family_repository.dart';
import '../../domain/models.dart';
import '../ai/serbom_ai_screen.dart';
import '../widgets/avatar_badge.dart';
import '../widgets/continuous_rtl_scroll_view.dart';
import '../widgets/date_range_picker_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/icon_tile_button.dart';
import '../widgets/pill_button.dart';
import '../widgets/section_header.dart';
import '../widgets/soft_card.dart';
import '../widgets/soft_text_field.dart';
import '../widgets/status_pill.dart';

class MedicinesScreen extends StatefulWidget {
  const MedicinesScreen({super.key});

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends State<MedicinesScreen> {
  final _medRepo = MedicineRepository();
  final _familyRepo = FamilyRepository();

  List<MedicineModel> _medicines = [];
  List<FamilyMemberModel> _familyMembers = [];
  List<DoseSyncModel> _upcomingDoses = [];
  List<DoseHistoryModel> _adherenceHistory = [];
  bool _isLoading = true;
  String? _errorMessage;

  String? _selectedFilterMemberId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String _generateUuid() {
    final random = math.Random();
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

  Future<void> _recordDoseAction(DoseSyncModel dose, String status) async {
    final messenger = ScaffoldMessenger.of(context);
    final clientLogId = _generateUuid();
    final lang = AppLanguage.instance;

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

    try {
      await _medRepo.logDoseAction(
        clientLogId: clientLogId,
        scheduleId: dose.scheduleId,
        targetMemberId: dose.targetMemberId,
        scheduledTime: dose.scheduledTimeUtc,
        status: status,
      );
    } catch (_) {}

    try {
      final familyId = 'family_default';
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
        actorName: 'Family Member',
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
        actorName: 'Family Member',
      );
    } catch (_) {}

    if (mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            status == 'Taken'
                ? (lang.isBengali ? 'ওষুধ সফলভাবে নেওয়া হয়েছে!' : 'Marked as Taken! Great job.')
                : (lang.isBengali ? 'ওষুধ নেওয়া হয়নি হিসেবে চিহ্নিত।' : 'Marked as Not Taken.'),
          ),
          backgroundColor: status == 'Taken' ? AppColors.taken : AppColors.missed,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final meds = await _medRepo.getMedicines(memberId: _selectedFilterMemberId);
      final members = await _familyRepo.getFamilyMembers();
      List<DoseSyncModel> doses = [];
      List<DoseHistoryModel> history = [];
      try {
        doses = await _medRepo.get48HourSyncWindow();
      } catch (_) {}
      try {
        history = await _medRepo.getAdherenceHistory();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _medicines = meds;
          _familyMembers = members;
          _upcomingDoses = doses;
          _adherenceHistory = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _onFilterMemberChanged(String? memberId) {
    setState(() {
      _selectedFilterMemberId = memberId;
    });
    _loadData();
  }

  void _openSerbomAi() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SerbomAiScreen(
          members: _familyMembers,
          initialMemberId: _selectedFilterMemberId,
        ),
      ),
    ).then((_) => _loadData());
  }

  void _showAddMedicineDialog(AppLanguage lang) {
    final nameCtrl = TextEditingController();
    final dosageCtrl = TextEditingController();
    final instructionsCtrl = TextEditingController();
    String foodRelation = 'NoRelation';
    String voiceLang = TtsService.voiceLanguage;
    bool hasCourseDuration = false;
    DateTime? fromDate;
    DateTime? toDate;
    TimeOfDay reminderTime = TimeOfDay.now();
    String? selectedMemberId = _selectedFilterMemberId ?? (_familyMembers.isNotEmpty ? _familyMembers.first.id : null);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SoftCard(
              backgroundColor: AppColors.creamLight,
              padding: const EdgeInsets.all(24),
              radius: AppRadius.modal,
              child: SingleChildScrollView(
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
                          ),
                          child: const Icon(Icons.medication_rounded, color: AppColors.forest, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            lang.translate('add_medicine'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_familyMembers.isNotEmpty)
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _familyMembers.any((m) => m.id == selectedMemberId)
                            ? selectedMemberId
                            : _familyMembers.first.id,
                        decoration: InputDecoration(
                          labelText: lang.translate('target_person'),
                          prefixIcon: const Icon(Icons.person_rounded, color: AppColors.forest),
                        ),
                        items: _familyMembers.map((m) => DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.fullName} (${m.relation})', overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedMemberId = val);
                        },
                      ),
                    const SizedBox(height: 12),
                    SoftTextField(
                      controller: nameCtrl,
                      labelText: '${lang.translate('medicine_name')} * (e.g. Paracetamol)',
                      prefixIcon: Icons.healing_rounded,
                    ),
                    const SizedBox(height: 12),
                    SoftTextField(
                      controller: dosageCtrl,
                      labelText: '${lang.translate('dosage')} * (e.g. 500mg, 1 tablet)',
                      prefixIcon: Icons.format_list_numbered_rounded,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: foodRelation,
                      decoration: InputDecoration(
                        labelText: lang.translate('food_relation'),
                        prefixIcon: const Icon(Icons.restaurant_rounded, color: AppColors.forest),
                      ),
                      items: [
                        DropdownMenuItem(value: 'NoRelation', child: Text(lang.translate('no_relation'), overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'BeforeMeal', child: Text(lang.translate('before_meal'), overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'AfterMeal', child: Text(lang.translate('after_meal'), overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'WithMeal', child: Text(lang.translate('with_meal'), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => foodRelation = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: TtsService.supportedIndianLanguages.containsKey(voiceLang) ? voiceLang : 'auto',
                      decoration: InputDecoration(
                        labelText: '${lang.translate('voice_reminder_language')} / ভয়েস অ্যালার্টের ভাষা',
                        prefixIcon: const Icon(Icons.record_voice_over_rounded, color: AppColors.forest),
                      ),
                      items: TtsService.supportedIndianLanguages.entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => voiceLang = val);
                          TtsService.setVoiceLanguage(val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    SoftTextField(
                      controller: instructionsCtrl,
                      labelText: '${lang.translate('instructions')} (e.g. with water)',
                      prefixIcon: Icons.info_outline_rounded,
                    ),
                    const SizedBox(height: 14),

                    InkWell(
                      onTap: () {
                        setDialogState(() {
                          hasCourseDuration = !hasCourseDuration;
                          if (hasCourseDuration) {
                            fromDate = DateTime.now();
                            toDate = DateTime.now().add(const Duration(days: 7));
                          } else {
                            fromDate = null;
                            toDate = null;
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Checkbox(
                            value: hasCourseDuration,
                            activeColor: AppColors.forest,
                            onChanged: (val) {
                              setDialogState(() {
                                hasCourseDuration = val ?? false;
                                if (hasCourseDuration) {
                                  fromDate = DateTime.now();
                                  toDate = DateTime.now().add(const Duration(days: 7));
                                } else {
                                  fromDate = null;
                                  toDate = null;
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Text(
                              lang.isBengali ? 'মেয়াদ বা তারিখ নির্ধারণ করুন (ঐচ্ছিক)' : 'Course Duration (From Date - To Date)',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!hasCourseDuration)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.mint.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(AppRadius.control),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.all_inclusive_rounded, size: 18, color: AppColors.forest),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                lang.isBengali
                                    ? 'চলমান ওষুধ (কোনো নির্দিষ্ট শেষ তারিখ নেই, আজ থেকেই কার্যকর)'
                                    : 'Ongoing medicine (No end date, active daily starting today)',
                                style: const TextStyle(fontSize: 12, color: AppColors.forest, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (hasCourseDuration) ...[
                      const SizedBox(height: 8),
                      DateRangePickerWidget(
                        label: '${lang.translate('course_duration')} (${lang.translate('from_date')} - ${lang.translate('to_date')})',
                        fromDate: fromDate ?? DateTime.now(),
                        toDate: toDate,
                        onFromDateChanged: (dt) => setDialogState(() => fromDate = dt),
                        onToDateChanged: (dt) => setDialogState(() => toDate = dt),
                      ),
                    ],
                    const SizedBox(height: 14),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        boxShadow: AppShadows.subtle,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.alarm_rounded, color: AppColors.coral, size: 24),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lang.isBengali ? 'দৈনিক স্মরণ সময়' : 'Daily Reminder Time',
                                    style: const TextStyle(fontSize: 11.5, color: AppColors.muted, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    reminderTime.format(context),
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: AppColors.ink),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          PillButton(
                            label: lang.isBengali ? 'পরিবর্তন' : 'Change',
                            variant: PillButtonVariant.tinted,
                            customColor: AppColors.mint,
                            customTextColor: AppColors.forest,
                            height: 34,
                            icon: Icons.edit_rounded,
                            onPressed: () async {
                              final picked = await showTimePicker(context: context, initialTime: reminderTime);
                              if (picked != null) {
                                setDialogState(() => reminderTime = picked);
                              }
                            },
                          ),
                        ],
                      ),
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
                            label: lang.translate('confirm_and_save'),
                            variant: PillButtonVariant.primary,
                            customColor: AppColors.coral,
                            onPressed: () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(lang.isBengali ? 'অনুগ্রহ করে ওষুধের নাম লিখুন' : 'Please enter medicine name'),
                                    backgroundColor: AppColors.missed,
                                  ),
                                );
                                return;
                              }
                              if (dosageCtrl.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(lang.isBengali ? 'অনুগ্রহ করে ওষুধের মাত্রা (dosage) লিখুন' : 'Please enter dosage'),
                                    backgroundColor: AppColors.missed,
                                  ),
                                );
                                return;
                              }
                              selectedMemberId ??= _familyMembers.isNotEmpty
                                  ? _familyMembers.first.id
                                  : '910d7db8-e77d-4fa8-8e04-6c52b243d792';
                              if (hasCourseDuration && toDate != null && fromDate != null && toDate!.isBefore(fromDate!)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(lang.translate('invalid_date_range')),
                                    backgroundColor: AppColors.missed,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(ctx);
                              try {
                                final createdMed = await _medRepo.createMedicine(
                                  ownerMemberId: selectedMemberId!,
                                  name: nameCtrl.text.trim(),
                                  dosage: dosageCtrl.text.trim(),
                                  instructions: instructionsCtrl.text.trim(),
                                  foodRelation: foodRelation,
                                  startDate: hasCourseDuration ? (fromDate ?? DateTime.now()) : DateTime.now(),
                                  endDate: hasCourseDuration ? toDate : null,
                                );

                                final timeStr = '${reminderTime.hour.toString().padLeft(2, '0')}:${reminderTime.minute.toString().padLeft(2, '0')}';
                                final createdSchedule = await _medRepo.createSchedule(
                                  medicineId: createdMed.id,
                                  targetMemberId: selectedMemberId!,
                                  timeOfDay: timeStr,
                                  daysOfWeekMask: 127,
                                );

                                final targetName = _familyMembers.firstWhere(
                                  (m) => m.id == selectedMemberId,
                                  orElse: () => _familyMembers.first,
                                ).fullName;

                                await NotificationService.instance.scheduleMedicineAlarm(
                                  id: createdSchedule.id.hashCode.abs() % 1000000,
                                  title: lang.isBengali
                                      ? '💊 ওষুধ স্মরণসূচী: ${createdMed.name} (${createdMed.dosage})'
                                      : '💊 Medicine Reminder: ${createdMed.name} (${createdMed.dosage})',
                                  body: lang.isBengali
                                      ? '$targetName-এর জন্য ${createdMed.name} খাওয়ার সময় হয়েছে। গ্রহণের পর Taken এ চাপুন।'
                                      : 'Time for $targetName to take ${createdMed.name}. Tap Taken or Not Taken.',
                                  scheduleId: createdSchedule.id,
                                  hour: reminderTime.hour,
                                  minute: reminderTime.minute,
                                  medicineName: createdMed.name,
                                  dosage: createdMed.dosage,
                                  targetMemberName: targetName,
                                  preferredLanguage: lang.currentLanguage,
                                );

                                await FirebaseService.instance.syncScheduleToFirestore(
                                  familyId: selectedMemberId!,
                                  scheduleId: createdSchedule.id,
                                  medicineId: createdMed.id,
                                  medicineName: createdMed.name,
                                  dosage: createdMed.dosage,
                                  timeOfDay: timeStr,
                                  targetMemberName: targetName,
                                  instructions: createdMed.instructions,
                                  foodRelation: foodRelation,
                                );

                                _loadData();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(lang.isBengali ? 'ওষুধ ও স্মরণসূচী সফলভাবে সংরক্ষিত হয়েছে!' : 'Medicine & reminder schedule saved successfully!'),
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
      ),
    );
  }

  void _showEditMedicineDialog(MedicineModel med, AppLanguage lang) {
    final nameCtrl = TextEditingController(text: med.name);
    final dosageCtrl = TextEditingController(text: med.dosage);
    final instructionsCtrl = TextEditingController(text: med.instructions ?? '');
    String foodRelation = med.foodRelation;
    bool hasCourseDuration = med.endDate != null;
    DateTime? fromDate = med.startDate;
    DateTime? toDate = med.endDate;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SoftCard(
              backgroundColor: AppColors.creamLight,
              padding: const EdgeInsets.all(24),
              radius: AppRadius.modal,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      lang.isBengali ? 'ওষুধ সম্পাদনা করুন' : 'Edit Medicine Details',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                    ),
                    const SizedBox(height: 16),
                    SoftTextField(
                      controller: nameCtrl,
                      labelText: '${lang.translate('medicine_name')} *',
                      prefixIcon: Icons.healing_rounded,
                    ),
                    const SizedBox(height: 12),
                    SoftTextField(
                      controller: dosageCtrl,
                      labelText: '${lang.translate('dosage')} *',
                      prefixIcon: Icons.format_list_numbered_rounded,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: ['NoRelation', 'BeforeMeal', 'AfterMeal', 'WithMeal'].contains(foodRelation) ? foodRelation : 'NoRelation',
                      decoration: InputDecoration(
                        labelText: lang.translate('food_relation'),
                        prefixIcon: const Icon(Icons.restaurant_rounded, color: AppColors.forest),
                      ),
                      items: [
                        DropdownMenuItem(value: 'NoRelation', child: Text(lang.translate('no_relation'), overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'BeforeMeal', child: Text(lang.translate('before_meal'), overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'AfterMeal', child: Text(lang.translate('after_meal'), overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'WithMeal', child: Text(lang.translate('with_meal'), overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => foodRelation = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    SoftTextField(
                      controller: instructionsCtrl,
                      labelText: lang.translate('instructions'),
                      prefixIcon: Icons.info_outline_rounded,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () {
                        setDialogState(() {
                          hasCourseDuration = !hasCourseDuration;
                          if (hasCourseDuration) {
                            fromDate = DateTime.now();
                            toDate = DateTime.now().add(const Duration(days: 7));
                          } else {
                            fromDate = null;
                            toDate = null;
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Checkbox(
                            value: hasCourseDuration,
                            activeColor: AppColors.forest,
                            onChanged: (val) {
                              setDialogState(() {
                                hasCourseDuration = val ?? false;
                                if (hasCourseDuration) {
                                  fromDate = DateTime.now();
                                  toDate = DateTime.now().add(const Duration(days: 7));
                                } else {
                                  fromDate = null;
                                  toDate = null;
                                }
                              });
                            },
                          ),
                          Expanded(
                            child: Text(
                              lang.isBengali ? 'মেয়াদ বা তারিখ নির্ধারণ করুন (ঐচ্ছিক)' : 'Set Course Duration (Optional)',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasCourseDuration) ...[
                      const SizedBox(height: 8),
                      DateRangePickerWidget(
                        label: '${lang.translate('course_duration')} (${lang.translate('from_date')} - ${lang.translate('to_date')})',
                        fromDate: fromDate ?? DateTime.now(),
                        toDate: toDate,
                        onFromDateChanged: (dt) => setDialogState(() => fromDate = dt),
                        onToDateChanged: (dt) => setDialogState(() => toDate = dt),
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
                            label: lang.isBengali ? 'সংরক্ষণ' : 'Save Changes',
                            variant: PillButtonVariant.primary,
                            customColor: AppColors.forest,
                            onPressed: () async {
                              if (nameCtrl.text.trim().isEmpty || dosageCtrl.text.trim().isEmpty) return;
                              Navigator.pop(ctx);
                              try {
                                await _medRepo.updateMedicine(
                                  id: med.id,
                                  name: nameCtrl.text.trim(),
                                  dosage: dosageCtrl.text.trim(),
                                  instructions: instructionsCtrl.text.trim(),
                                  foodRelation: foodRelation,
                                  startDate: hasCourseDuration ? (fromDate ?? DateTime.now()) : DateTime.now(),
                                  endDate: hasCourseDuration ? toDate : null,
                                );
                                _loadData();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(lang.isBengali ? 'ওষুধ সফলভাবে আপডেট করা হয়েছে!' : 'Medicine updated successfully!'),
                                      backgroundColor: AppColors.forest,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
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
      ),
    );
  }

  void _showEditScheduleDialog(DoseSyncModel dose, AppLanguage lang) async {
    final parts = dose.timeOfDay.split(':');
    final initialH = parts.isNotEmpty ? (int.tryParse(parts[0].trim()) ?? 8) : 8;
    final initialM = parts.length > 1 ? (int.tryParse(parts[1].split(' ')[0].trim()) ?? 0) : 0;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initialH, minute: initialM),
    );

    if (pickedTime == null || !mounted) return;

    final hourStr = pickedTime.hour.toString().padLeft(2, '0');
    final minStr = pickedTime.minute.toString().padLeft(2, '0');
    final formattedTime = '$hourStr:$minStr';

    try {
      await _medRepo.updateSchedule(
        id: dose.scheduleId,
        timeOfDay: formattedTime,
        daysOfWeekMask: 127,
      );

      await FirebaseService.instance.syncScheduleToFirestore(
        familyId: dose.targetMemberId,
        scheduleId: dose.scheduleId,
        medicineId: dose.medicineId,
        medicineName: dose.medicineName,
        dosage: dose.dosage,
        timeOfDay: formattedTime,
        targetMemberName: dose.targetMemberName,
        instructions: dose.instructions,
      );

      await NotificationService.instance.scheduleMedicineAlarm(
        id: dose.scheduleId.hashCode.abs() % 1000000,
        title: lang.isBengali ? '💊 ওষুধ স্মরণসূচী: ${dose.medicineName} (${dose.dosage})' : '💊 Medicine Reminder: ${dose.medicineName} (${dose.dosage})',
        body: lang.isBengali ? '${dose.targetMemberName}-এর জন্য ${dose.medicineName} খাওয়ার সময় হয়েছে।' : 'Time for ${dose.targetMemberName} to take ${dose.medicineName}.',
        scheduleId: dose.scheduleId,
        hour: pickedTime.hour,
        minute: pickedTime.minute,
        medicineName: dose.medicineName,
        dosage: dose.dosage,
        targetMemberName: dose.targetMemberName,
        preferredLanguage: lang.currentLanguage,
      );

      _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(lang.isBengali ? 'স্মরণসূচী সফলভাবে আপডেট হয়েছে: $formattedTime' : 'Reminder schedule updated to $formattedTime!'),
            backgroundColor: AppColors.forest,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating schedule: $e')),
        );
      }
    }
  }

  void _showAddScheduleDialog(MedicineModel med, AppLanguage lang) async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );

    if (pickedTime == null || !mounted) return;

    final hourStr = pickedTime.hour.toString().padLeft(2, '0');
    final minStr = pickedTime.minute.toString().padLeft(2, '0');
    final formattedTime = '$hourStr:$minStr';

    String? selectedMemberId = _selectedFilterMemberId ?? (_familyMembers.isNotEmpty ? _familyMembers.first.id : null);
    String scheduleVoiceLang = TtsService.voiceLanguage;
    DateTime schedFromDate = DateTime.now();
    DateTime? schedToDate = DateTime.now().add(const Duration(days: 30));

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SoftCard(
              backgroundColor: AppColors.creamLight,
              padding: const EdgeInsets.all(24),
              radius: AppRadius.modal,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${lang.translate('schedule_time')}: ${med.name}',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: AppColors.ink),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.mint.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.alarm_rounded, color: AppColors.forest, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${lang.translate('times_of_day')}: $formattedTime',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.forest),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (_familyMembers.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _familyMembers.any((m) => m.id == selectedMemberId)
                            ? selectedMemberId
                            : _familyMembers.first.id,
                        decoration: InputDecoration(
                          labelText: lang.translate('target_person'),
                          prefixIcon: const Icon(Icons.person_rounded, color: AppColors.forest),
                        ),
                        items: _familyMembers.map((m) => DropdownMenuItem(
                          value: m.id,
                          child: Text('${m.fullName} (${m.relation})', overflow: TextOverflow.ellipsis),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedMemberId = val);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: TtsService.supportedIndianLanguages.containsKey(scheduleVoiceLang)
                          ? scheduleVoiceLang
                          : 'auto',
                      decoration: InputDecoration(
                        labelText: '${lang.translate('voice_reminder_language')} / ভয়েস অ্যালার্টের ভাষা',
                        prefixIcon: const Icon(Icons.record_voice_over_rounded, color: AppColors.forest),
                      ),
                      items: TtsService.supportedIndianLanguages.entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => scheduleVoiceLang = val);
                          TtsService.setVoiceLanguage(val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    DateRangePickerWidget(
                      label: '${lang.translate('date_range')} (${lang.translate('from_date')} - ${lang.translate('to_date')})',
                      fromDate: schedFromDate,
                      toDate: schedToDate,
                      onFromDateChanged: (dt) => setDialogState(() => schedFromDate = dt),
                      onToDateChanged: (dt) => setDialogState(() => schedToDate = dt),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      lang.isBengali ? 'পুনরাবৃত্তি: প্রতিদিন (সপ্তাহের ৭ দিন)' : 'Recurrence: Daily (7 days a week)',
                      style: const TextStyle(fontSize: 12, color: AppColors.muted),
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
                            label: lang.translate('confirm_and_save'),
                            variant: PillButtonVariant.primary,
                            customColor: AppColors.coral,
                            onPressed: () async {
                              selectedMemberId ??= med.ownerMemberId ?? (_familyMembers.isNotEmpty ? _familyMembers.first.id : '910d7db8-e77d-4fa8-8e04-6c52b243d792');
                              if (schedToDate != null && schedToDate!.isBefore(schedFromDate)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(lang.translate('invalid_date_range')),
                                    backgroundColor: AppColors.missed,
                                  ),
                                );
                                return;
                              }
                              Navigator.pop(ctx);
                              try {
                                final newSched = await _medRepo.createSchedule(
                                  medicineId: med.id,
                                  targetMemberId: selectedMemberId!,
                                  timeOfDay: formattedTime,
                                );
                                final targetMember = _familyMembers.firstWhere(
                                  (m) => m.id == selectedMemberId,
                                  orElse: () => _familyMembers.isNotEmpty
                                      ? _familyMembers.first
                                      : FamilyMemberModel(
                                          id: selectedMemberId!,
                                          fullName: 'Patient',
                                          relation: 'Self',
                                          preferredLanguage: lang.currentLanguage,
                                          voicePreference: 'Female',
                                        ),
                                );
                                await NotificationService.instance.scheduleMedicineAlarm(
                                  id: newSched.id.hashCode.abs() % 1000000,
                                  title: lang.isBengali ? '💊 ওষুধ স্মরণসূচী: ${med.name} (${med.dosage})' : '💊 Medicine Reminder: ${med.name} (${med.dosage})',
                                  body: lang.isBengali ? '${targetMember.fullName}-এর জন্য ${med.name} খাওয়ার সময় হয়েছে।' : 'Time for ${targetMember.fullName} to take ${med.name}.',
                                  scheduleId: newSched.id,
                                  hour: pickedTime.hour,
                                  minute: pickedTime.minute,
                                  medicineName: med.name,
                                  dosage: med.dosage,
                                  targetMemberName: targetMember.fullName,
                                  preferredLanguage: lang.currentLanguage,
                                );
                                _loadData();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(lang.isBengali ? '${med.name}-এর সময়সূচী $formattedTime এ সংরক্ষিত হয়েছে' : 'Schedule created for ${med.name} at $formattedTime'),
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
      ),
    );
  }

  String _formatFoodRelation(String rel, AppLanguage lang) {
    switch (rel) {
      case 'BeforeMeal':
      case 'BeforeFood':
        return lang.translate('before_meal');
      case 'AfterMeal':
      case 'AfterFood':
        return lang.translate('after_meal');
      case 'WithMeal':
      case 'WithFood':
        return lang.translate('with_meal');
      default:
        return lang.translate('no_relation');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLanguage.instance,
      builder: (context, _) {
        final lang = AppLanguage.instance;

        return Scaffold(
          backgroundColor: AppColors.cream,
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.coral),
                )
              : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.missed),
                            const SizedBox(height: 12),
                            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.missed)),
                            const SizedBox(height: 16),
                            PillButton(
                              label: 'Retry',
                              variant: PillButtonVariant.primary,
                              onPressed: _loadData,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: AppColors.forest,
                      backgroundColor: AppColors.creamLight,
                      onRefresh: _loadData,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
                        children: [
                          SoftCard(
                            backgroundColor: AppColors.mint,
                            radius: AppRadius.card,
                            padding: const EdgeInsets.all(18),
                            onTap: _openSerbomAi,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: AppShadows.subtle,
                                  ),
                                  child: const Icon(Icons.auto_awesome_rounded, color: AppColors.coral, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang.translate('serbom_ai_title'),
                                        style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w900, fontSize: 16),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        lang.isBengali
                                            ? 'কথা বা টেক্সট লিখে সহজে ওষুধ ও স্মরণসূচী তৈরি করুন'
                                            : 'Conversational voice & text medicine scheduler',
                                        style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.forest, size: 16),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              const Icon(Icons.tune_rounded, size: 16, color: AppColors.forest),
                              const SizedBox(width: 6),
                              Text(
                                lang.translate('filter_by_person'),
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.forest),
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
                                  if (val) _onFilterMemberChanged(null);
                                },
                              ),
                              ..._familyMembers.map((m) {
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
                                      if (val) _onFilterMemberChanged(m.id);
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 18),

                          PillButton(
                            label: lang.translate('add_medicine'),
                            icon: Icons.add_rounded,
                            variant: PillButtonVariant.primary,
                            customColor: AppColors.coral,
                            height: 48,
                            onPressed: () => _showAddMedicineDialog(lang),
                          ),
                          const SizedBox(height: 24),

                          SectionHeader(
                            title: '${lang.isBengali ? "সংরক্ষিত ওষুধসমূহ" : "Prescribed Medications"} (${_medicines.length})',
                            subtitle: lang.isBengali ? 'নির্ধারিত প্রেসক্রিপশন ও অনুস্মারক' : 'Manage doses, instructions & schedules',
                            icon: Icons.medication_rounded,
                            iconColor: AppColors.forest,
                          ),
                          const SizedBox(height: 10),

                          if (_medicines.isEmpty)
                            EmptyState(
                              icon: Icons.medication_liquid_rounded,
                              title: lang.isBengali ? 'কোনো ওষুধ যোগ করা হয়নি' : 'No medicines added yet',
                              message: lang.isBengali
                                  ? 'সারবম এআই ব্যবহার করুন অথবা "+ ওষুধ যোগ করুন" বোতাম চাপুন।'
                                  : 'Use Serbom AI or tap "+ Add Medicine" to configure your schedule.',
                              actionLabel: lang.translate('add_medicine'),
                              onAction: () => _showAddMedicineDialog(lang),
                            ),

                          ..._medicines.map((med) {
                            final matchingDoses = _upcomingDoses.where((d) => d.medicineId == med.id).toList();
                            final distinctDoses = <String, DoseSyncModel>{};
                            for (final d in matchingDoses) {
                              distinctDoses.putIfAbsent(d.scheduleId, () => d);
                            }

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14.0),
                              child: SoftCard(
                                backgroundColor: AppColors.creamLight,
                                radius: AppRadius.card,
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: const BoxDecoration(
                                            color: AppColors.sage,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.medication_liquid_rounded, color: AppColors.forest, size: 24),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                med.name,
                                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ink),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${lang.translate('dosage')}: ${med.dosage}',
                                                style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                        IconTileButton(
                                          icon: Icons.volume_up_rounded,
                                          tooltip: lang.translate('voice_reminder'),
                                          iconColor: AppColors.forest,
                                          backgroundColor: AppColors.mint,
                                          size: 34,
                                          onPressed: () {
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
                                                              ? 'ভয়েস রিমাইন্ডার বন্ধ রয়েছে। ড্যাশবোর্ড থেকে ভয়েস চালু করুন।'
                                                              : 'Voice reminders are muted. Enable Voice [ON] from settings or dashboard.',
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

                                            final recipient = (med.ownerMemberName != null && med.ownerMemberName!.isNotEmpty)
                                                ? med.ownerMemberName!
                                                : (lang.isBengali ? 'ব্যবহারকারী' : 'User');
                                            final langCode = TtsService.voiceLanguage == 'auto'
                                                ? (lang.isBengali ? 'bn' : 'en')
                                                : TtsService.voiceLanguage;

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
                                                            ? '🔊 ${med.name} ওষুধ অনুস্মারক বাজছে...'
                                                            : '🔊 Playing voice reminder for ${med.name}...',
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
                                              recipientName: recipient,
                                              medicineName: med.name,
                                              dosage: med.dosage,
                                              instructions: (med.instructions != null && med.instructions!.trim().isNotEmpty)
                                                  ? med.instructions
                                                  : (med.foodRelation != 'NoRelation' ? med.foodRelation : null),
                                              language: langCode,
                                            );
                                          },
                                        ),
                                        const SizedBox(width: 6),
                                        IconTileButton(
                                          icon: Icons.edit_rounded,
                                          tooltip: lang.isBengali ? 'ওষুধ সম্পাদনা' : 'Edit Medicine',
                                          iconColor: AppColors.forest,
                                          backgroundColor: AppColors.sage,
                                          size: 34,
                                          onPressed: () => _showEditMedicineDialog(med, lang),
                                        ),
                                        const SizedBox(width: 6),
                                        IconTileButton(
                                          icon: Icons.delete_outline_rounded,
                                          tooltip: lang.isBengali ? 'মুছে ফেলুন' : 'Delete Medicine',
                                          iconColor: AppColors.missed,
                                          backgroundColor: AppColors.peach.withValues(alpha: 0.4),
                                          size: 34,
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                                                title: Text(lang.isBengali ? 'নিশ্চিত করুন' : 'Confirm Delete'),
                                                content: Text(lang.isBengali ? 'আপনি কি "${med.name}" মুছে ফেলতে চান?' : 'Delete "${med.name}" and its reminders?'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(lang.translate('cancel'))),
                                                  PillButton(
                                                    label: lang.isBengali ? 'মুছুন' : 'Delete',
                                                    variant: PillButtonVariant.primary,
                                                    customColor: AppColors.missed,
                                                    height: 36,
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await _medRepo.deleteMedicine(med.id);
                                              _loadData();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (med.instructions != null && med.instructions!.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${lang.translate('instructions')}: ${med.instructions}',
                                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: AppColors.sage.withValues(alpha: 0.6),
                                              borderRadius: BorderRadius.circular(AppRadius.pill),
                                            ),
                                            child: Text(
                                              _formatFoodRelation(med.foodRelation, lang),
                                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.forest),
                                            ),
                                          ),
                                          if (med.endDate != null)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.powder,
                                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                              ),
                                              child: Text(
                                                '${lang.translate('course_duration')}: ${med.startDate != null ? "${med.startDate!.day}/${med.startDate!.month}" : ""} - ${med.endDate!.day}/${med.endDate!.month}',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.forest),
                                              ),
                                            )
                                          else
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: AppColors.mint,
                                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                              ),
                                              child: Text(
                                                lang.isBengali ? 'চলমান (Ongoing)' : 'Ongoing',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.forest),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    PillButton(
                                      label: lang.isBengali ? 'সময়সূচী যোগ' : '+ Schedule',
                                      icon: Icons.alarm_add_rounded,
                                      variant: PillButtonVariant.tinted,
                                      customColor: AppColors.butter,
                                      customTextColor: AppColors.ink,
                                      height: 32,
                                      onPressed: () => _showAddScheduleDialog(med, lang),
                                    ),
                                  ],
                                ),

                                    if (distinctDoses.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      const Divider(height: 1, color: Color(0x1A4A3B2F)),
                                      const SizedBox(height: 10),
                                      ...distinctDoses.values.map((dose) {
                                        final doseStatus = _getDoseStatus(dose);

                                        return Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          child: LayoutBuilder(
                                            builder: (context, constraints) {
                                              final isNarrow = constraints.maxWidth < 430;

                                              if (isNarrow) {
                                                return Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.cream.withValues(alpha: 0.5),
                                                    borderRadius: BorderRadius.circular(AppRadius.sm),
                                                  ),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              const Icon(Icons.alarm_rounded, size: 18, color: AppColors.forest),
                                                              const SizedBox(width: 6),
                                                              Text(
                                                                dose.timeOfDay,
                                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppColors.ink),
                                                              ),
                                                              const SizedBox(width: 8),
                                                              StatusPill(status: doseStatus),
                                                            ],
                                                          ),
                                                          Row(
                                                            children: [
                                                              IconTileButton(
                                                                icon: Icons.edit_calendar_rounded,
                                                                tooltip: lang.isBengali ? 'সময় পরিবর্তন' : 'Edit Reminder Time',
                                                                iconColor: AppColors.forest,
                                                                backgroundColor: AppColors.mint,
                                                                size: 30,
                                                                onPressed: () => _showEditScheduleDialog(dose, lang),
                                                              ),
                                                              const SizedBox(width: 6),
                                                              IconTileButton(
                                                                icon: Icons.delete_outline_rounded,
                                                                tooltip: lang.isBengali ? 'মুছুন' : 'Delete Reminder',
                                                                iconColor: AppColors.missed,
                                                                backgroundColor: AppColors.peach.withValues(alpha: 0.4),
                                                                size: 30,
                                                                onPressed: () async {
                                                                  final confirm = await showDialog<bool>(
                                                                    context: context,
                                                                    builder: (ctx) => AlertDialog(
                                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                                                                      title: Text(lang.isBengali ? 'নিশ্চিত করুন' : 'Confirm Delete'),
                                                                      content: Text(lang.isBengali ? 'এই সময়সূচীটি মুছে ফেলতে চান (${dose.timeOfDay})?' : 'Delete reminder at ${dose.timeOfDay}?'),
                                                                      actions: [
                                                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(lang.translate('cancel'))),
                                                                        PillButton(
                                                                          label: lang.isBengali ? 'মুছুন' : 'Delete',
                                                                          variant: PillButtonVariant.primary,
                                                                          customColor: AppColors.missed,
                                                                          height: 34,
                                                                          onPressed: () => Navigator.pop(ctx, true),
                                                                        ),
                                                                      ],
                                                                    ),
                                                                  );
                                                                  if (confirm == true) {
                                                                    await _medRepo.deleteSchedule(dose.scheduleId);
                                                                    _loadData();
                                                                  }
                                                                },
                                                              ),
                                                            ],
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: PillButton(
                                                              label: lang.isBengali ? 'খেয়েছেন' : 'Taken',
                                                              icon: Icons.check_circle_rounded,
                                                              variant: PillButtonVariant.primary,
                                                              customColor: AppColors.taken,
                                                              height: 32,
                                                              onPressed: () => _recordDoseAction(dose, 'Taken'),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Expanded(
                                                            child: PillButton(
                                                              label: lang.isBengali ? 'খাননি' : 'Not Taken',
                                                              icon: Icons.cancel_rounded,
                                                              variant: PillButtonVariant.primary,
                                                              customColor: AppColors.missed,
                                                              height: 32,
                                                              onPressed: () => _recordDoseAction(dose, 'Missed'),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              }

                                              return SingleChildScrollView(
                                                scrollDirection: Axis.horizontal,
                                                child: Row(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        const Icon(Icons.alarm_rounded, size: 18, color: AppColors.forest),
                                                        const SizedBox(width: 6),
                                                        Text(
                                                          dose.timeOfDay,
                                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: AppColors.ink),
                                                        ),
                                                        const SizedBox(width: 10),
                                                        StatusPill(status: doseStatus),
                                                      ],
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Row(
                                                      children: [
                                                        PillButton(
                                                          label: lang.isBengali ? 'খেয়েছেন' : 'Taken',
                                                          icon: Icons.check_circle_rounded,
                                                          variant: PillButtonVariant.primary,
                                                          customColor: AppColors.taken,
                                                          height: 32,
                                                          onPressed: () => _recordDoseAction(dose, 'Taken'),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        PillButton(
                                                          label: lang.isBengali ? 'খাননি' : 'Not Taken',
                                                          icon: Icons.cancel_rounded,
                                                          variant: PillButtonVariant.primary,
                                                          customColor: AppColors.missed,
                                                          height: 32,
                                                          onPressed: () => _recordDoseAction(dose, 'Missed'),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        IconTileButton(
                                                          icon: Icons.edit_calendar_rounded,
                                                          tooltip: lang.isBengali ? 'সময় পরিবর্তন' : 'Edit Reminder Time',
                                                          iconColor: AppColors.forest,
                                                          backgroundColor: AppColors.mint,
                                                          size: 32,
                                                          onPressed: () => _showEditScheduleDialog(dose, lang),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        IconTileButton(
                                                          icon: Icons.delete_outline_rounded,
                                                          tooltip: lang.isBengali ? 'মুছুন' : 'Delete Reminder',
                                                          iconColor: AppColors.missed,
                                                          backgroundColor: AppColors.peach.withValues(alpha: 0.4),
                                                          size: 32,
                                                          onPressed: () async {
                                                            final confirm = await showDialog<bool>(
                                                              context: context,
                                                              builder: (ctx) => AlertDialog(
                                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                                                                title: Text(lang.isBengali ? 'নিশ্চিত করুন' : 'Confirm Delete'),
                                                                content: Text(lang.isBengali ? 'এই সময়সূচীটি মুছে ফেলতে চান (${dose.timeOfDay})?' : 'Delete reminder at ${dose.timeOfDay}?'),
                                                                actions: [
                                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(lang.translate('cancel'))),
                                                                  PillButton(
                                                                    label: lang.isBengali ? 'মুছুন' : 'Delete',
                                                                    variant: PillButtonVariant.primary,
                                                                    customColor: AppColors.missed,
                                                                    height: 34,
                                                                    onPressed: () => Navigator.pop(ctx, true),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                            if (confirm == true) {
                                                              await _medRepo.deleteSchedule(dose.scheduleId);
                                                              _loadData();
                                                            }
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      }),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
        );
      },
    );
  }
}
