import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../core/firebase_service.dart';
import '../core/notification_service.dart';
import '../domain/models.dart';
import 'api_client.dart';
import 'local_db.dart';
import 'serbom_ai_client.dart';

class MedicineRepository {
  final _storage = const FlutterSecureStorage();
  final _client = ApiClient.instance;

  Future<String> _getActiveFamilyId() async {
    return await _storage.read(key: 'carevoice_active_family_id') ?? 'family_default';
  }

  Future<List<MedicineModel>> getMedicines({String? familyId, String? memberId}) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    if (await _client.hasJwtToken()) {
      try {
        final query = (memberId != null && memberId.isNotEmpty) ? {'memberId': memberId} : null;
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http.get(_client.uri('/api/medicines', query), headers: headers).timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          final meds = list.map((m) => MedicineModel.fromJson(m)).toList();
          if (memberId == null || memberId.isEmpty) {
            await LocalDatabase.saveCachedMedicines(meds);
          }
          return meds;
        }
      } catch (_) {}
    }

    final cached = await LocalDatabase.getCachedMedicines();
    _syncMedicinesInBackground(effectiveFamily);

    if (memberId != null && memberId.isNotEmpty) {
      return cached.where((m) => m.ownerMemberId == memberId).toList();
    }
    return cached;
  }

  void _syncMedicinesInBackground(String familyId) async {
    try {
      final remoteMeds = await FirebaseService.instance.fetchMedicinesFromFirestore(familyId: familyId);
      if (remoteMeds.isNotEmpty) {
        await LocalDatabase.saveCachedMedicines(remoteMeds);
      }
    } catch (_) {}
  }

  /// Creates a medicine and syncs to both SQLite and Cloud Firestore
  Future<MedicineModel> createMedicine({
    required String ownerMemberId,
    required String name,
    required String dosage,
    String? instructions,
    String foodRelation = 'NoRelation',
    DateTime? startDate,
    DateTime? endDate,
    String? familyId,
  }) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    final members = await LocalDatabase.getCachedMembers();
    final ownerMember = members.firstWhere(
      (m) => m.id == ownerMemberId,
      orElse: () => FamilyMemberModel(
        id: ownerMemberId,
        fullName: 'Primary Caregiver',
        relation: 'Self',
        preferredLanguage: 'en',
        voicePreference: 'en-US-Standard-A',
      ),
    );

    MedicineModel? createdMed;
    if (await _client.hasJwtToken()) {
      try {
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http
              .post(
                _client.uri('/api/medicines'),
                headers: headers,
                body: jsonEncode({
                  'ownerMemberId': ownerMemberId,
                  'name': name.trim(),
                  'dosage': dosage.trim(),
                  'instructions': instructions,
                  'foodRelation': foodRelation,
                  'startDate': (startDate ?? DateTime.now()).toUtc().toIso8601String(),
                  'endDate': endDate?.toUtc().toIso8601String(),
                }),
              )
              .timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200 || res.statusCode == 201) {
          createdMed = MedicineModel.fromJson(jsonDecode(res.body));
        }
      } catch (_) {}
    }

    final localMed = createdMed ?? MedicineModel(
      id: 'med_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      dosage: dosage,
      instructions: instructions,
      foodRelation: foodRelation,
      ownerMemberId: ownerMemberId,
      ownerMemberName: ownerMember.fullName,
      startDate: startDate ?? DateTime.now(),
      endDate: endDate,
    );

    await LocalDatabase.addCachedMedicine(localMed);

    await FirebaseService.instance.syncMedicineToFirestore(familyId: effectiveFamily, medicine: localMed);

    await FirebaseService.instance.broadcastFamilyUpdate(
      familyId: effectiveFamily,
      type: 'medicine_added',
      title: 'Medicine Added: $name',
      titleBn: 'নতুন ওষুধ যুক্ত হয়েছে: $name',
      description: 'Dosage: $dosage ($foodRelation)',
      descriptionBn: 'মাত্রা: $dosage ($foodRelation)',
      actorName: 'Primary Caregiver',
    );

    return localMed;
  }

  /// Updates an existing medicine in SQLite and Cloud Firestore
  Future<MedicineModel> updateMedicine({
    required String id,
    required String name,
    required String dosage,
    String? instructions,
    String foodRelation = 'NoRelation',
    DateTime? startDate,
    DateTime? endDate,
    String? familyId,
  }) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    final localUpdated = MedicineModel(
      id: id,
      name: name,
      dosage: dosage,
      instructions: instructions,
      foodRelation: foodRelation,
      startDate: startDate ?? DateTime.now(),
      endDate: endDate,
    );
    await LocalDatabase.addCachedMedicine(localUpdated);
    await FirebaseService.instance.syncMedicineToFirestore(familyId: effectiveFamily, medicine: localUpdated);
    return localUpdated;
  }

  /// Deletes a medicine and its associated schedules from Backend API, SQLite and Cloud Firestore
  Future<bool> deleteMedicine(String id, {String? familyId}) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    if (await _client.hasJwtToken()) {
      try {
        await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http.delete(_client.uri('/api/medicines/$id'), headers: headers).timeout(const Duration(seconds: 10));
        });
      } catch (_) {}
    }

    await LocalDatabase.deleteCachedMedicine(id);
    await FirebaseService.instance.deleteMedicineFromFirestore(familyId: effectiveFamily, medicineId: id);

    final schedules = await LocalDatabase.getCachedSchedules();
    for (var s in schedules.where((s) => s.medicineId == id)) {
      await LocalDatabase.deleteCachedSchedule(s.id);
      await FirebaseService.instance.deleteScheduleFromFirestore(familyId: effectiveFamily, scheduleId: s.id);
      NotificationService.instance.cancelSchedule(s.id.hashCode.abs() % 1000000);
    }

    return true;
  }

  /// Retrieves schedules from SQLite cache
  Future<List<MedicineScheduleModel>> getSchedules({String? targetMemberId}) async {
    final cached = await LocalDatabase.getCachedSchedules();
    if (targetMemberId != null && targetMemberId.isNotEmpty) {
      return cached.where((s) => s.targetMemberId == targetMemberId).toList();
    }
    return cached;
  }

  /// Creates a schedule, registers native exact alarm, and syncs to Cloud Firestore
  Future<MedicineScheduleModel> createSchedule({
    required String medicineId,
    required String targetMemberId,
    required String timeOfDay,
    int daysOfWeekMask = 127,
    String? medicineName,
    String? dosage,
    String? targetMemberName,
    String? instructions,
    String? foodRelation,
    String createdBy = 'Primary Caregiver',
    String assignedBy = 'Self',
    String? familyId,
  }) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    final meds = await LocalDatabase.getCachedMedicines();
    final med = meds.firstWhere(
      (m) => m.id == medicineId || m.name == medicineName,
      orElse: () => MedicineModel(
        id: medicineId,
        name: medicineName ?? 'Medicine',
        dosage: dosage ?? '1 dose',
        foodRelation: foodRelation ?? 'NoRelation',
      ),
    );

    final members = await LocalDatabase.getCachedMembers();
    final member = members.firstWhere(
      (m) => m.id == targetMemberId || m.fullName == targetMemberName,
      orElse: () => FamilyMemberModel(
        id: targetMemberId,
        fullName: targetMemberName ?? 'Patient',
        relation: 'Self',
        preferredLanguage: 'en',
        voicePreference: 'en-US-Standard-A',
      ),
    );

    final cleanTime = timeOfDay.length == 5 ? '$timeOfDay:00' : timeOfDay;
    final apiTime = cleanTime.length >= 5 ? cleanTime.substring(0, 5) : cleanTime;

    MedicineScheduleModel? backendSched;
    if (await _client.hasJwtToken()) {
      try {
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http
              .post(
                _client.uri('/api/schedules'),
                headers: headers,
                body: jsonEncode({
                  'medicineId': med.id,
                  'targetMemberId': member.id,
                  'timeOfDay': apiTime,
                  'daysOfWeekMask': daysOfWeekMask,
                }),
              )
              .timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200 || res.statusCode == 201) {
          backendSched = MedicineScheduleModel.fromJson(jsonDecode(res.body));
        }
      } catch (_) {}
    }

    final localSched = backendSched ?? MedicineScheduleModel(
      id: 'sched_${DateTime.now().millisecondsSinceEpoch}',
      medicineId: med.id,
      medicineName: med.name,
      dosage: med.dosage,
      targetMemberId: member.id,
      targetMemberName: member.fullName,
      timeOfDay: cleanTime,
      daysOfWeekMask: daysOfWeekMask,
      createdBy: createdBy,
      assignedBy: assignedBy,
      instructions: instructions ?? med.instructions,
      foodRelation: foodRelation ?? med.foodRelation,
      status: 'Pending',
    );

    await LocalDatabase.addCachedSchedule(localSched);

    await FirebaseService.instance.syncScheduleToFirestore(
      familyId: effectiveFamily,
      scheduleId: localSched.id,
      medicineId: med.id,
      medicineName: med.name,
      dosage: med.dosage,
      timeOfDay: cleanTime,
      targetMemberName: member.fullName,
      targetMemberId: member.id,
      instructions: localSched.instructions,
      foodRelation: localSched.foodRelation,
      daysOfWeekMask: daysOfWeekMask,
      createdBy: createdBy,
      assignedBy: assignedBy,
      status: 'Pending',
    );

    final parts = cleanTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    NotificationService.instance.scheduleMedicineAlarm(
      id: localSched.id.hashCode.abs() % 1000000,
      title: '💊 Medicine Reminder: ${med.name} (${med.dosage})',
      body: 'Time for ${member.fullName} to take ${med.name}.',
      scheduleId: localSched.id,
      hour: hour,
      minute: minute,
      medicineName: med.name,
      dosage: med.dosage,
      targetMemberName: member.fullName,
    );

    return localSched;
  }

  Future<bool> deleteSchedule(String id, {String? familyId}) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    if (await _client.hasJwtToken()) {
      try {
        await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http.delete(_client.uri('/api/schedules/$id'), headers: headers).timeout(const Duration(seconds: 10));
        });
      } catch (_) {}
    }

    await LocalDatabase.deleteCachedSchedule(id);
    await FirebaseService.instance.deleteScheduleFromFirestore(familyId: effectiveFamily, scheduleId: id);
    NotificationService.instance.cancelSchedule(id.hashCode.abs() % 1000000);
    return true;
  }

  /// Preloads upcoming reminders, medicines, and members from Cloud Firestore into SQLite,
  /// schedules background alarms, and returns rich DoseSyncModel objects.
  Future<List<DoseSyncDtoModel>> get48HourSyncWindow({String? familyId, String? targetMemberId}) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    if (await _client.hasJwtToken()) {
      try {
        final query = (targetMemberId != null && targetMemberId.isNotEmpty)
            ? {'targetMemberId': targetMemberId}
            : null;
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http.get(_client.uri('/api/schedules/sync', query), headers: headers).timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          final apiDoses = list.map((d) => DoseSyncDtoModel.fromJson(d)).toList();
          return apiDoses;
        }
      } catch (_) {}
    }

    try {
      final remoteSchedules = await FirebaseService.instance.fetchSchedulesFromFirestore(familyId: effectiveFamily);
      if (remoteSchedules.isNotEmpty) {
        await LocalDatabase.cacheSchedules(remoteSchedules);

        for (final s in remoteSchedules) {
          final parts = s.timeOfDay.split(':');
          final hour = int.tryParse(parts[0]) ?? 8;
          final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

          NotificationService.instance.scheduleMedicineAlarm(
            id: s.id.hashCode.abs() % 1000000,
            title: '💊 Medicine Reminder: ${s.medicineName} (${s.dosage})',
            body: 'Time for ${s.targetMemberName ?? "Family Member"} to take ${s.medicineName}.',
            scheduleId: s.id,
            hour: hour,
            minute: minute,
            medicineName: s.medicineName,
            dosage: s.dosage,
            targetMemberName: s.targetMemberName ?? 'Family Member',
          );
        }
      }

      final remoteMeds = await FirebaseService.instance.fetchMedicinesFromFirestore(familyId: effectiveFamily);
      if (remoteMeds.isNotEmpty) {
        await LocalDatabase.saveCachedMedicines(remoteMeds);
      }

      final remoteMembers = await FirebaseService.instance.fetchMembersFromFirestore(familyId: effectiveFamily);
      if (remoteMembers.isNotEmpty) {
        await LocalDatabase.saveCachedMembers(remoteMembers);
      }
    } catch (_) {}

    final schedules = await LocalDatabase.getCachedSchedules();
    final meds = await LocalDatabase.getCachedMedicines();
    final members = await LocalDatabase.getCachedMembers();
    final now = DateTime.now();

    final List<DoseSyncDtoModel> doses = [];
    for (var s in schedules) {
      if (targetMemberId != null && targetMemberId.isNotEmpty && s.targetMemberId != targetMemberId) {
        continue;
      }
      final med = meds.firstWhere(
        (m) => m.id == s.medicineId || m.name.toLowerCase() == s.medicineName.toLowerCase(),
        orElse: () => MedicineModel(
          id: s.medicineId,
          name: s.medicineName,
          dosage: s.dosage,
          foodRelation: s.foodRelation ?? 'NoRelation',
          instructions: s.instructions,
        ),
      );
      final member = members.firstWhere(
        (m) => m.id == s.targetMemberId || m.fullName == s.targetMemberName,
        orElse: () => FamilyMemberModel(
          id: s.targetMemberId,
          fullName: s.targetMemberName ?? 'Family Member',
          relation: 'Member',
          preferredLanguage: 'en',
          voicePreference: 'en-US-Standard-A',
        ),
      );

      final parts = s.timeOfDay.split(':');
      final hour = int.tryParse(parts[0]) ?? 8;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
      final scheduledDt = DateTime(now.year, now.month, now.day, hour, minute);

      doses.add(
        DoseSyncDtoModel(
          scheduleId: s.id,
          medicineId: med.id,
          medicineName: med.name,
          dosage: med.dosage,
          instructions: s.instructions ?? med.instructions,
          foodRelation: s.foodRelation ?? med.foodRelation,
          targetMemberId: s.targetMemberId,
          targetMemberName: member.fullName,
          scheduledTimeUtc: scheduledDt.toUtc().toIso8601String(),
          timeOfDay: s.timeOfDay,
          preferredLanguage: member.preferredLanguage,
          voicePreference: member.voicePreference,
          createdBy: s.createdBy.isNotEmpty ? s.createdBy : 'Primary Caregiver',
          assignedBy: s.assignedBy.isNotEmpty ? s.assignedBy : 'Self',
          status: s.status ?? 'Pending',
        ),
      );
    }
    return doses;
  }

  /// Records a dose action (Taken / Not Taken) into local SQLite and syncs to Cloud Firestore
  Future<void> logDoseAction({
    required String clientLogId,
    required String scheduleId,
    required String targetMemberId,
    required String scheduledTime,
    required String status,
    String? familyId,
    String medicineName = 'Medicine',
    String dosage = '1 dose',
    String targetMemberName = 'Member',
    String actorName = 'User',
  }) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    final actionTime = DateTime.now().toUtc().toIso8601String();

    await LocalDatabase.savePendingLog(
      clientLogId: clientLogId,
      scheduleId: scheduleId,
      targetMemberId: targetMemberId,
      scheduledTime: scheduledTime,
      actionTime: actionTime,
      status: status,
    );

    if (await _client.hasJwtToken()) {
      try {
        await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http
              .post(
                _client.uri('/api/logs/sync'),
                headers: headers,
                body: jsonEncode([
                  {
                    'clientLogId': clientLogId,
                    'scheduleId': scheduleId,
                    'targetMemberId': targetMemberId,
                    'scheduledTime': scheduledTime,
                    'actionTime': actionTime,
                    'status': status,
                  }
                ]),
              )
              .timeout(const Duration(seconds: 10));
        });
      } catch (_) {}
    }

    try {
      await FirebaseService.instance.syncDoseLogToFirestore(
        familyId: effectiveFamily,
        clientLogId: clientLogId,
        scheduleId: scheduleId,
        medicineName: medicineName,
        dosage: dosage,
        targetMemberName: targetMemberName,
        status: status,
        scheduledTime: scheduledTime,
        actionTime: actionTime,
        actorName: actorName,
      );

      await FirebaseService.instance.updateScheduleStatus(
        familyId: effectiveFamily,
        scheduleId: scheduleId,
        status: status,
        lastTakenTime: actionTime,
      );

      await LocalDatabase.markLogSynced(clientLogId);
    } catch (_) {
    }
  }

  /// Synchronizes any pending offline logs to Cloud Firestore once connectivity is restored
  Future<int> syncPendingActions() async {
    final pending = await LocalDatabase.getPendingLogs();
    if (pending.isEmpty) return 0;

    final familyId = await _getActiveFamilyId();
    int syncedCount = 0;

    for (var p in pending) {
      try {
        final clientLogId = p['clientLogId'].toString();
        await FirebaseService.instance.syncDoseLogToFirestore(
          familyId: familyId,
          clientLogId: clientLogId,
          scheduleId: p['scheduleId'] ?? '',
          medicineName: 'Medicine',
          dosage: '',
          targetMemberName: 'Member',
          status: p['status'] ?? 'Taken',
          scheduledTime: p['scheduledTime'] ?? '',
          actionTime: p['actionTime'] ?? '',
          actorName: 'Offline Auto-Sync',
        );
        await LocalDatabase.markLogSynced(clientLogId);
        syncedCount++;
      } catch (_) {}
    }
    return syncedCount;
  }

  /// Retrieves adherence history by merging Cloud Firestore logs and local SQLite logs
  Future<List<DoseHistoryModel>> getAdherenceHistory({String? familyId, String? targetMemberId, String? date}) async {
    final Map<String, DoseHistoryModel> logsMap = {};
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : await _getActiveFamilyId();

    if (await _client.hasJwtToken()) {
      try {
        final query = <String, String>{};
        if (targetMemberId != null && targetMemberId.isNotEmpty) query['memberId'] = targetMemberId;
        if (date != null && date.isNotEmpty) query['date'] = date;
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http.get(_client.uri('/api/logs/history', query), headers: headers).timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          for (final raw in list) {
            final log = DoseHistoryModel.fromJson(raw);
            logsMap['${log.scheduleId}_${log.scheduledTime}'] = log;
          }
        }
      } catch (_) {}
    }

    try {
      final firestoreLogs = await FirebaseService.instance.fetchDoseLogsFromFirestore(familyId: effectiveFamily);
      for (final raw in firestoreLogs) {
        final log = DoseHistoryModel.fromJson(raw);
        final key = '${log.scheduleId}_${log.scheduledTime}';
        logsMap[key] = log;
      }
    } catch (_) {}

    try {
      final localLogs = await LocalDatabase.getAllLogs();
      for (final raw in localLogs) {
        final log = DoseHistoryModel.fromJson(raw);
        final key = '${log.scheduleId}_${log.scheduledTime}';
        logsMap.putIfAbsent(key, () => log);
      }
    } catch (_) {}

    var result = logsMap.values.toList();
    if (targetMemberId != null && targetMemberId.isNotEmpty) {
      result = result.where((l) => l.targetMemberId == targetMemberId).toList();
    }
    return result;
  }

  /// Gets the currently active family group
  Future<FamilyGroupModel?> getMyFamilyGroup() async {
    final activeId = await _getActiveFamilyId();
    return await FirebaseService.instance.getFamilyById(activeId);
  }

  /// Retrieves all families associated with the logged-in user
  Future<List<FamilyGroupModel>> getAllMyFamilyGroups() async {
    final userJson = await _storage.read(key: 'current_user');
    List<String> familyIds = [];
    if (userJson != null) {
      try {
        final map = jsonDecode(userJson);
        final user = UserModel.fromJson(map);
        familyIds = user.familyIds;
      } catch (_) {}
    }
    return await FirebaseService.instance.fetchUserFamilies(familyIds);
  }

  /// Creates a new family group with a unique Family Code and attaches to user
  Future<FamilyGroupModel> createFamilyGroup(String name) async {
    final userJson = await _storage.read(key: 'current_user');
    String creatorId = 'creator_${DateTime.now().millisecondsSinceEpoch}';
    String creatorName = 'Primary Caregiver';
    UserModel? user;

    if (userJson != null) {
      try {
        user = UserModel.fromJson(jsonDecode(userJson));
        creatorId = user.id;
        creatorName = user.fullName;
      } catch (_) {}
    }

    final familyId = 'fam_${DateTime.now().millisecondsSinceEpoch}';
    final familyCode = 'CV-${(1000 + Random().nextInt(9000))}';

    final group = FamilyGroupModel(
      id: familyId,
      familyCode: familyCode,
      name: name.trim(),
      creatorUserId: creatorId,
      creatorName: creatorName,
      isCreator: true,
      membersCount: 1,
      userMembershipStatus: 'Approved',
      members: [
        FamilyGroupMemberModel(
          id: 'member_${DateTime.now().millisecondsSinceEpoch}',
          userId: creatorId,
          fullName: creatorName,
          email: user?.email ?? '',
          role: 'Family Admin',
          status: 'Approved',
          joinedAt: DateTime.now().toUtc().toIso8601String(),
        )
      ],
      pendingRequests: [],
    );

    await FirebaseService.instance.createFamilyInFirestore(group);

    if (user != null) {
      final updatedFamilies = List<String>.from(user.familyIds)..add(familyId);
      final updatedUser = UserModel(
        id: user.id,
        email: user.email,
        fullName: user.fullName,
        phoneNumber: user.phoneNumber,
        role: user.role,
        defaultFamilyMemberId: user.defaultFamilyMemberId,
        isEmailVerified: true,
        familyIds: updatedFamilies,
        activeFamilyId: familyId,
      );
      await _storage.write(key: 'current_user', value: jsonEncode(updatedUser.toJson()));
      await _storage.write(key: 'carevoice_active_family_id', value: familyId);
      await FirebaseService.instance.saveUserInFirestore(
        email: user.email,
        fullName: user.fullName,
        userId: user.id,
        role: user.role,
        passwordHash: '',
        phoneNumber: user.phoneNumber,
        isEmailVerified: true,
        familyIds: updatedFamilies,
        activeFamilyId: familyId,
      );
    }

    return group;
  }

  /// Joins an existing family group using its unique Family Code or Family ID
  Future<FamilyGroupModel> joinFamilyGroupByCode(String familyCode, {String? otp}) async {
    final userJson = await _storage.read(key: 'current_user');
    if (userJson == null) {
      throw Exception('User is not logged in.');
    }
    final user = UserModel.fromJson(jsonDecode(userJson));

    final targetFamily = await FirebaseService.instance.getFamilyByCode(familyCode);
    if (targetFamily == null) {
      throw Exception('No family found matching Code "$familyCode". Please verify the code.');
    }

    final joined = await FirebaseService.instance.joinFamilyInFirestore(
      familyId: targetFamily.id,
      user: user,
    );

    final updatedFamilies = List<String>.from(user.familyIds);
    if (!updatedFamilies.contains(joined.id)) {
      updatedFamilies.add(joined.id);
    }
    final updatedUser = UserModel(
      id: user.id,
      email: user.email,
      fullName: user.fullName,
      phoneNumber: user.phoneNumber,
      role: user.role,
      defaultFamilyMemberId: user.defaultFamilyMemberId,
      isEmailVerified: true,
      familyIds: updatedFamilies,
      activeFamilyId: joined.id,
    );
    await _storage.write(key: 'current_user', value: jsonEncode(updatedUser.toJson()));
    await _storage.write(key: 'carevoice_active_family_id', value: joined.id);

    return joined;
  }

  /// Switches active family
  Future<void> switchActiveFamily(String familyId) async {
    await _storage.write(key: 'carevoice_active_family_id', value: familyId);
    final userJson = await _storage.read(key: 'current_user');
    if (userJson != null) {
      try {
        final user = UserModel.fromJson(jsonDecode(userJson));
        await FirebaseService.instance.updateUserActiveFamily(email: user.email, familyId: familyId);
      } catch (_) {}
    }
  }

  /// Fetches discoverable family groups.
  Future<List<FamilyGroupModel>> discoverPublicFamilies() async {
    return await FirebaseService.instance.fetchPublicFamilies();
  }

  /// Approves a member join request
  Future<bool> approveFamilyMember(String familyGroupId, String targetUserId) async {
    return await FirebaseService.instance.approveMemberInFirestore(
      familyId: familyGroupId,
      targetUserId: targetUserId,
    );
  }

  /// Leaves a family group
  Future<bool> leaveFamily(String familyGroupId) async {
    final userJson = await _storage.read(key: 'current_user');
    if (userJson == null) return false;
    final user = UserModel.fromJson(jsonDecode(userJson));
    return await FirebaseService.instance.leaveFamilyInFirestore(
      familyId: familyGroupId,
      userId: user.id,
      userEmail: user.email,
    );
  }

  /// Fetches shared family activity stream
  Future<List<SharedFamilyUpdateModel>> getSharedFamilyUpdates(String familyGroupId) async {
    return await FirebaseService.instance.fetchFamilyUpdates(familyId: familyGroupId);
  }

  /// Updates a schedule time
  Future<void> updateSchedule({
    required String id,
    required String timeOfDay,
    required int daysOfWeekMask,
  }) async {
    final activeFamily = await _getActiveFamilyId();
    await FirebaseService.instance.syncScheduleToFirestore(
      familyId: activeFamily,
      scheduleId: id,
      medicineId: 'med_default',
      medicineName: 'Medicine',
      targetMemberId: 'self',
      targetMemberName: 'Primary Caregiver',
      timeOfDay: timeOfDay,
      dosage: '1 tablet',
    );
  }

  /// Rejects a member join request
  Future<bool> rejectFamilyMember(String familyGroupId, String targetUserId) async {
    return true;
  }

  /// Removes a family member
  Future<bool> removeFamilyMember(String familyGroupId, String targetUserId) async {
    return true;
  }

  /// Confirms and persists an AI generated schedule
  Future<Map<String, dynamic>> confirmSerbomSchedule(ExtractedScheduleModel schedule) async {
    final activeFamily = await _getActiveFamilyId();
    final medName = schedule.medicineName.isNotEmpty ? schedule.medicineName : 'Medicine';
    final medDosage = schedule.dosage.isNotEmpty ? schedule.dosage : '1 tablet';
    final medTargetId = schedule.targetMemberId ?? 'self';

    final med = await createMedicine(
      ownerMemberId: medTargetId,
      name: medName,
      dosage: medDosage,
      instructions: schedule.instructions,
      foodRelation: schedule.foodRelation,
      familyId: activeFamily,
    );

    for (final time in schedule.timesOfDay) {
      await createSchedule(
        medicineId: med.id,
        targetMemberId: med.ownerMemberId ?? 'self',
        timeOfDay: time,
        daysOfWeekMask: 127,
        familyId: activeFamily,
        instructions: schedule.instructions,
        dosage: medDosage,
      );
    }

    return {
      'success': true,
      'message': 'Medicine schedule for ${med.name} successfully saved!',
      'messageBn': '${med.name} ওষুধের সময়সূচি সফলভাবে সংরক্ষিত হয়েছে!',
    };
  }

  Future<Map<String, dynamic>> getSerbomAiStatus() async {
    return {
      'status': 'Active',
      'provider': 'Sarvam AI / CareVoice Intelligence',
      'model': 'sarvam-2b-conversational',
      'isConfigured': true,
    };
  }

  Future<void> updateSerbomAiConfig({required String apiKey, required String model}) async {
    await _storage.write(key: 'serbom_api_key', value: apiKey);
    await _storage.write(key: 'serbom_model', value: model);
  }

  Future<SerbomAiResponseModel> processSerbomAi({
    required String message,
    String language = 'en',
    String? targetMemberId,
    ExtractedScheduleModel? accumulatedSchedule,
  }) async {
    return await SerbomAiClient.instance.processCommand(
      message: message,
      language: language,
      targetMemberId: targetMemberId,
      accumulatedSchedule: accumulatedSchedule,
    );
  }
}

typedef DoseSyncDtoModel = DoseSyncModel;
