import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../domain/models.dart';

class LocalDatabase {
  static Database? _database;
  static const _storage = FlutterSecureStorage();
  static const _webSchedulesKey = 'carevoice_web_schedules';
  static const _webLogsKey = 'carevoice_web_pending_logs';
  static const _membersKey = 'carevoice_cached_members';
  static const _medicinesKey = 'carevoice_cached_medicines';

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'carevoice_offline.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cached_schedules (
            id TEXT PRIMARY KEY,
            medicineId TEXT,
            medicineName TEXT,
            dosage TEXT,
            targetMemberId TEXT,
            targetMemberName TEXT,
            timeOfDay TEXT,
            daysOfWeekMask INTEGER,
            createdBy TEXT,
            assignedBy TEXT,
            instructions TEXT,
            foodRelation TEXT,
            status TEXT
          )
        ''');

        await db.execute('''
          CREATE TABLE pending_logs (
            clientLogId TEXT PRIMARY KEY,
            scheduleId TEXT,
            targetMemberId TEXT,
            scheduledTime TEXT,
            actionTime TEXT,
            status TEXT,
            isSynced INTEGER DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try { await db.execute('ALTER TABLE cached_schedules ADD COLUMN targetMemberName TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE cached_schedules ADD COLUMN createdBy TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE cached_schedules ADD COLUMN assignedBy TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE cached_schedules ADD COLUMN instructions TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE cached_schedules ADD COLUMN foodRelation TEXT'); } catch (_) {}
          try { await db.execute('ALTER TABLE cached_schedules ADD COLUMN status TEXT'); } catch (_) {}
        }
      },
    );
  }

  static Future<void> cacheSchedules(List<MedicineScheduleModel> schedules) async {
    if (kIsWeb) {
      final jsonStr = jsonEncode(schedules.map((s) => s.toMap()).toList());
      await _storage.write(key: _webSchedulesKey, value: jsonStr);
      return;
    }

    final db = await database;
    final batch = db.batch();
    batch.delete('cached_schedules');
    for (var s in schedules) {
      batch.insert('cached_schedules', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit();
  }

  static Future<List<MedicineScheduleModel>> getCachedSchedules() async {
    List<MedicineScheduleModel> result = [];
    if (kIsWeb) {
      final jsonStr = await _storage.read(key: _webSchedulesKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        try {
          final List list = jsonDecode(jsonStr);
          result = list.map((m) => MedicineScheduleModel.fromJson(m)).toList();
        } catch (_) {}
      }
    } else {
      try {
        final db = await database;
        final maps = await db.query('cached_schedules');
        result = maps.map((m) => MedicineScheduleModel.fromJson(m)).toList();
      } catch (_) {}
    }

    final hasInitialized = await _storage.read(key: 'carevoice_schedules_init_v2');
    if (result.isEmpty && hasInitialized == null) {
      await _storage.write(key: 'carevoice_schedules_init_v2', value: '1');
      result = [];
    }
    return result;
  }

  static Future<void> addCachedSchedule(MedicineScheduleModel schedule) async {
    final list = await getCachedSchedules();
    list.removeWhere((s) => s.id == schedule.id);
    list.add(schedule);
    await cacheSchedules(list);
  }

  static Future<void> deleteCachedSchedule(String scheduleId) async {
    final list = await getCachedSchedules();
    list.removeWhere((s) => s.id == scheduleId);
    await cacheSchedules(list);
  }

  static Future<List<FamilyMemberModel>> getCachedMembers() async {
    final jsonStr = await _storage.read(key: _membersKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List list = jsonDecode(jsonStr);
        final members = list.map((m) => FamilyMemberModel.fromJson(m)).toList();
        if (members.isNotEmpty) return members;
      } catch (_) {}
    }

    final initial = [
      FamilyMemberModel(
        id: '910d7db8-e77d-4fa8-8e04-6c52b243d792',
        fullName: 'Primary Caregiver',
        relation: 'Self',
        preferredLanguage: 'en',
        voicePreference: 'en-US-Standard-A',
        isSelf: true,
      ),
      FamilyMemberModel(
        id: 'a21e8ec9-f88e-5fb9-9f15-7d63c354e803',
        fullName: 'Papa',
        relation: 'Parent',
        preferredLanguage: 'bn',
        voicePreference: 'bn-BD-Standard-A',
        isSelf: false,
      ),
    ];
    await saveCachedMembers(initial);
    return initial;
  }

  static Future<void> saveCachedMembers(List<FamilyMemberModel> members) async {
    final str = jsonEncode(members.map((m) => m.toJson()).toList());
    await _storage.write(key: _membersKey, value: str);
  }

  static Future<void> addCachedMember(FamilyMemberModel member) async {
    final list = await getCachedMembers();
    list.removeWhere((m) => m.id == member.id);
    list.add(member);
    await saveCachedMembers(list);
  }

  static Future<void> deleteCachedMember(String memberId) async {
    final list = await getCachedMembers();
    list.removeWhere((m) => m.id == memberId);
    await saveCachedMembers(list);
  }

  static Future<List<MedicineModel>> getCachedMedicines() async {
    final jsonStr = await _storage.read(key: _medicinesKey);
    if (jsonStr != null && jsonStr.isNotEmpty) {
      try {
        final List list = jsonDecode(jsonStr);
        final meds = list.map((m) => MedicineModel.fromJson(m)).toList();
        if (meds.isNotEmpty) return meds;
      } catch (_) {}
    }

    final initial = [
      MedicineModel(
        id: 'med_default_bp',
        name: 'bp',
        dosage: '1 tablet',
        instructions: 'food',
        foodRelation: 'NoRelation',
        ownerMemberId: '910d7db8-e77d-4fa8-8e04-6c52b243d792',
        ownerMemberName: 'Primary Caregiver',
        startDate: DateTime.now().subtract(const Duration(days: 7)),
        endDate: DateTime.now().add(const Duration(days: 30)),
      ),
    ];
    await saveCachedMedicines(initial);
    return initial;
  }

  static Future<void> saveCachedMedicines(List<MedicineModel> medicines) async {
    final str = jsonEncode(medicines.map((m) => m.toJson()).toList());
    await _storage.write(key: _medicinesKey, value: str);
  }

  static Future<void> addCachedMedicine(MedicineModel medicine) async {
    final list = await getCachedMedicines();
    list.removeWhere((m) => m.id == medicine.id);
    list.add(medicine);
    await saveCachedMedicines(list);
  }

  static Future<void> deleteCachedMedicine(String id) async {
    final list = await getCachedMedicines();
    list.removeWhere((m) => m.id == id);
    await saveCachedMedicines(list);
  }

  static Future<void> savePendingLog({
    required String clientLogId,
    required String scheduleId,
    required String targetMemberId,
    required String scheduledTime,
    required String actionTime,
    required String status,
  }) async {
    final record = {
      'clientLogId': clientLogId,
      'scheduleId': scheduleId,
      'targetMemberId': targetMemberId,
      'scheduledTime': scheduledTime,
      'actionTime': actionTime,
      'status': status,
      'isSynced': 0,
    };

    if (kIsWeb) {
      final existing = await _getWebLogs();
      existing.removeWhere((l) => l['clientLogId'] == clientLogId);
      existing.add(record);
      await _saveWebLogs(existing);
      return;
    }

    final db = await database;
    await db.insert(
      'pending_logs',
      record,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Map<String, dynamic>>> getPendingLogs() async {
    if (kIsWeb) {
      final logs = await _getWebLogs();
      return logs.where((l) => l['isSynced'] == 0).toList();
    }

    final db = await database;
    return await db.query('pending_logs', where: 'isSynced = ?', whereArgs: [0]);
  }

  static Future<List<Map<String, dynamic>>> getAllLogs() async {
    if (kIsWeb) {
      final logs = await _getWebLogs();
      return logs;
    }

    try {
      final db = await database;
      return await db.query('pending_logs', orderBy: 'scheduledTime DESC');
    } catch (_) {
      return [];
    }
  }

  static Future<void> markLogSynced(String clientLogId) async {
    if (kIsWeb) {
      final logs = await _getWebLogs();
      for (var l in logs) {
        if (l['clientLogId'] == clientLogId) {
          l['isSynced'] = 1;
        }
      }
      await _saveWebLogs(logs);
      return;
    }

    final db = await database;
    await db.update('pending_logs', {'isSynced': 1}, where: 'clientLogId = ?', whereArgs: [clientLogId]);
  }

  static Future<List<Map<String, dynamic>>> _getWebLogs() async {
    final str = await _storage.read(key: _webLogsKey);
    if (str == null || str.isEmpty) return [];
    try {
      final List list = jsonDecode(str);
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveWebLogs(List<Map<String, dynamic>> logs) async {
    await _storage.write(key: _webLogsKey, value: jsonEncode(logs));
  }

  static final Set<String> _inMemoryAnnouncedKeys = {};

  static Future<bool> shouldAnnounceReminder(String announcementKey) async {
    if (_inMemoryAnnouncedKeys.contains(announcementKey)) {
      return false;
    }
    final key = 'ann_$announcementKey';
    try {
      final val = await _storage.read(key: key);
      if (val != null) {
        _inMemoryAnnouncedKeys.add(announcementKey);
        return false;
      }
      _inMemoryAnnouncedKeys.add(announcementKey);
      await _storage.write(key: key, value: DateTime.now().toIso8601String());
      return true;
    } catch (_) {
      final isFirst = !_inMemoryAnnouncedKeys.contains(announcementKey);
      _inMemoryAnnouncedKeys.add(announcementKey);
      return isFirst;
    }
  }
}
