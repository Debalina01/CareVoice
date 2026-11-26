import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../domain/models.dart';

/// Real-time shared family synchronization service backed by Cloud Firestore.
class FirebaseService {
  static final FirebaseService instance = FirebaseService._();
  FirebaseService._();

  String _firebaseProjectId = 'carevoice-health-app';
  String? _firebaseApiKey = 'AIzaSyCxfMCcN5NA6qm6iKsAeH5G19reTjRuxZU';
  bool _isConfigured = true;

  bool get isConfigured => _isConfigured;
  String get projectId => _firebaseProjectId;
  String? get apiKey => _firebaseApiKey;

  void configure({required String projectId, String? apiKey}) {
    if (projectId.trim().isNotEmpty) {
      _firebaseProjectId = projectId.trim();
    }
    _firebaseApiKey = apiKey?.trim();
    _isConfigured = _firebaseProjectId.isNotEmpty;
  }

  String get _firestoreBaseUrl =>
      'https://firestore.googleapis.com/v1/projects/$_firebaseProjectId/databases/(default)/documents';

  String _toSafeDocId(String str) =>
      str.toLowerCase().trim().replaceAll('@', '_at_').replaceAll('.', '_dot_').replaceAll('/', '_');

  dynamic _parseFirestoreValue(dynamic val) {
    if (val is! Map) return val;
    if (val.containsKey('stringValue')) return val['stringValue'];
    if (val.containsKey('booleanValue')) return val['booleanValue'];
    if (val.containsKey('integerValue')) return int.tryParse(val['integerValue'].toString()) ?? 0;
    if (val.containsKey('doubleValue')) return double.tryParse(val['doubleValue'].toString()) ?? 0.0;
    if (val.containsKey('timestampValue')) return val['timestampValue'];
    if (val.containsKey('nullValue')) return null;
    if (val.containsKey('arrayValue')) {
      final values = val['arrayValue']?['values'] as List?;
      if (values == null) return [];
      return values.map((v) => _parseFirestoreValue(v)).toList();
    }
    if (val.containsKey('mapValue')) {
      final fields = val['mapValue']?['fields'] as Map?;
      if (fields == null) return {};
      final map = <String, dynamic>{};
      fields.forEach((k, v) {
        map[k.toString()] = _parseFirestoreValue(v);
      });
      return map;
    }
    return val.toString();
  }

  Map<String, dynamic> _parseDocumentFields(Map<String, dynamic>? fields) {
    final result = <String, dynamic>{};
    if (fields == null) return result;
    fields.forEach((key, val) {
      result[key] = _parseFirestoreValue(val);
    });
    return result;
  }

  Map<String, dynamic> _toFirestoreFields(Map<String, dynamic> data) {
    final fields = <String, dynamic>{};
    data.forEach((key, val) {
      if (val == null) {
        fields[key] = {'nullValue': null};
      } else if (val is bool) {
        fields[key] = {'booleanValue': val};
      } else if (val is int) {
        fields[key] = {'integerValue': val.toString()};
      } else if (val is double) {
        fields[key] = {'doubleValue': val};
      } else if (val is List) {
        fields[key] = {
          'arrayValue': {
            'values': val.map((item) {
              if (item is Map) {
                return {'mapValue': {'fields': _toFirestoreFields(item.cast<String, dynamic>())}};
              }
              return {'stringValue': item.toString()};
            }).toList()
          }
        };
      } else if (val is Map) {
        fields[key] = {
          'mapValue': {'fields': _toFirestoreFields(val.cast<String, dynamic>())}
        };
      } else {
        fields[key] = {'stringValue': val.toString()};
      }
    });
    return fields;
  }

  /// Retrieves user profile and auth state from Cloud Firestore
  Future<Map<String, dynamic>?> getUserFromFirestore(String email) async {
    if (!_isConfigured) return null;
    try {
      final safeDocId = _toSafeDocId(email);
      final url = Uri.parse('$_firestoreBaseUrl/users/$safeDocId');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return _parseDocumentFields(data['fields']);
      }
    } catch (_) {}
    return null;
  }

  /// Saves or updates user in Firestore with verified status, roles, and family memberships
  Future<void> saveUserInFirestore({
    required String email,
    required String fullName,
    required String userId,
    required String role,
    required String passwordHash,
    String? phoneNumber,
    bool isEmailVerified = false,
    List<String> familyIds = const [],
    String? activeFamilyId,
  }) async {
    if (!_isConfigured) return;
    try {
      final safeDocId = _toSafeDocId(email);
      final url = Uri.parse('$_firestoreBaseUrl/users/$safeDocId');

      final userPayload = {
        'userId': userId,
        'email': email.toLowerCase().trim(),
        'fullName': fullName.trim(),
        'phoneNumber': phoneNumber ?? '',
        'role': role,
        'passwordHash': passwordHash,
        'isEmailVerified': isEmailVerified,
        'familyIds': familyIds,
        'activeFamilyId': activeFamilyId ?? (familyIds.isNotEmpty ? familyIds.first : 'family_default'),
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(userPayload)}),
      );
    } catch (_) {}
  }

  /// Syncs basic user profile data to Cloud Firestore.
  Future<void> syncUserToFirestore({
    required String email,
    required String fullName,
    required String userId,
    required String role,
    String? phoneNumber,
    bool isEmailVerified = true,
  }) async {
    final existing = await getUserFromFirestore(email);
    final fams = (existing?['familyIds'] as List?)?.map((e) => e.toString()).toList() ?? ['family_default'];
    await saveUserInFirestore(
      email: email,
      fullName: fullName,
      userId: userId,
      role: role,
      passwordHash: existing?['passwordHash'] ?? '',
      phoneNumber: phoneNumber ?? existing?['phoneNumber'],
      isEmailVerified: isEmailVerified,
      familyIds: fams,
      activeFamilyId: existing?['activeFamilyId'] ?? fams.first,
    );
  }

  /// Marks a user's email address as verified in Cloud Firestore
  Future<void> markEmailVerified(String email) async {
    if (!_isConfigured) return;
    try {
      final safeDocId = _toSafeDocId(email);
      final url = Uri.parse('$_firestoreBaseUrl/users/$safeDocId?updateMask.fieldPaths=isEmailVerified&updateMask.fieldPaths=updatedAt');
      final payload = {
        'fields': {
          'isEmailVerified': {'booleanValue': true},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };
      await http.patch(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    } catch (_) {}
  }

  /// Updates active family for a user
  Future<void> updateUserActiveFamily({required String email, required String familyId}) async {
    if (!_isConfigured) return;
    try {
      final safeDocId = _toSafeDocId(email);
      final url = Uri.parse('$_firestoreBaseUrl/users/$safeDocId?updateMask.fieldPaths=activeFamilyId&updateMask.fieldPaths=updatedAt');
      final payload = {
        'fields': {
          'activeFamilyId': {'stringValue': familyId},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };
      await http.patch(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    } catch (_) {}
  }

  /// Syncs monitored reminder subscriptions
  Future<void> syncReminderSubscriptionsToFirestore({
    required String userEmail,
    required String familyId,
    required List<String> monitoredMemberIds,
  }) async {
    if (!_isConfigured) return;
    try {
      final safeDocId = _toSafeDocId(userEmail);
      final url = Uri.parse('$_firestoreBaseUrl/families/$familyId/subscriptions/$safeDocId');
      final payload = {
        'fields': {
          'userEmail': {'stringValue': userEmail},
          'familyId': {'stringValue': familyId},
          'monitoredMembers': {
            'arrayValue': {
              'values': monitoredMemberIds.map((m) => {'stringValue': m}).toList(),
            }
          },
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };
      await http.patch(url, headers: {'Content-Type': 'application/json'}, body: jsonEncode(payload));
    } catch (_) {}
  }

  /// Stores OTP for mandatory verification in Cloud Firestore
  Future<void> saveOtpToFirestore({
    required String email,
    required String otp,
    required String purpose,
    required DateTime expiresAt,
  }) async {
    if (!_isConfigured) return;
    try {
      final safeDocId = _toSafeDocId(email);
      final url = Uri.parse('$_firestoreBaseUrl/otps/$safeDocId');
      final payload = {
        'email': email.toLowerCase().trim(),
        'otp': otp.trim(),
        'purpose': purpose,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'isUsed': false,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(payload)}),
      );
    } catch (_) {}
  }

  /// Verifies entered OTP against Firestore record
  Future<bool> verifyOtpInFirestore({required String email, required String otp}) async {
    if (!_isConfigured) return false;
    try {
      final safeDocId = _toSafeDocId(email);
      final url = Uri.parse('$_firestoreBaseUrl/otps/$safeDocId');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final fields = _parseDocumentFields(data['fields']);
        final storedOtp = fields['otp']?.toString() ?? '';
        final isUsed = fields['isUsed'] == true;
        final expiresAtStr = fields['expiresAt']?.toString() ?? '';
        final expiresAt = DateTime.tryParse(expiresAtStr);

        if (storedOtp == otp.trim() && !isUsed) {
          if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) {
            return false;
          }
          await http.patch(
            Uri.parse('$_firestoreBaseUrl/otps/$safeDocId?updateMask.fieldPaths=isUsed'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'fields': {'isUsed': {'booleanValue': true}}}),
          );
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Syncs or creates a family group in Cloud Firestore
  Future<void> syncFamilyGroupToFirestore({
    required String familyId,
    required String familyCode,
    required String familyName,
    required String creatorUserId,
    required String creatorName,
    bool isPublic = true,
  }) async {
    if (!_isConfigured) return;
    try {
      final url = Uri.parse('$_firestoreBaseUrl/families/$familyId');
      final payload = {
        'familyId': familyId,
        'familyCode': familyCode,
        'name': familyName,
        'creatorUserId': creatorUserId,
        'creatorName': creatorName,
        'isPublic': isPublic,
        'memberCount': 1,
        'memberUserIds': [creatorUserId],
        'members': [
          {
            'id': 'member_${DateTime.now().millisecondsSinceEpoch}',
            'userId': creatorUserId,
            'fullName': creatorName,
            'email': '',
            'role': 'Admin',
            'status': 'Approved',
            'joinedAt': DateTime.now().toUtc().toIso8601String(),
          }
        ],
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(payload)}),
      );
    } catch (_) {}
  }

  /// Creates a new family in Cloud Firestore and attaches creator
  Future<FamilyGroupModel> createFamilyInFirestore(FamilyGroupModel family) async {
    if (!_isConfigured) return family;
    try {
      final url = Uri.parse('$_firestoreBaseUrl/families/${family.id}');
      final raw = family.toJson();
      raw['memberUserIds'] = [family.creatorUserId];
      raw['updatedAt'] = DateTime.now().toUtc().toIso8601String();

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(raw)}),
      );
    } catch (_) {}
    return family;
  }

  /// Retrieves a specific family document by ID
  Future<FamilyGroupModel?> getFamilyById(String familyId) async {
    if (!_isConfigured) return null;
    try {
      final url = Uri.parse('$_firestoreBaseUrl/families/$familyId');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final map = _parseDocumentFields(data['fields']);
        return FamilyGroupModel.fromJson(map);
      }
    } catch (_) {}
    return null;
  }

  /// Finds a family group by its unique 6-character Family Code
  Future<FamilyGroupModel?> getFamilyByCode(String code) async {
    if (!_isConfigured) return null;
    try {
      final cleanCode = code.trim().toUpperCase();
      final url = Uri.parse('$_firestoreBaseUrl/families?pageSize=100');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List<dynamic>?;
        if (docs != null) {
          for (final doc in docs) {
            final map = _parseDocumentFields(doc['fields']);
            if (map['familyCode']?.toString().toUpperCase() == cleanCode ||
                map['familyId']?.toString() == code.trim()) {
              return FamilyGroupModel.fromJson(map);
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Fetches all families associated with a list of family IDs for the logged-in user
  Future<List<FamilyGroupModel>> fetchUserFamilies(List<String> familyIds) async {
    final List<FamilyGroupModel> list = [];
    final safeIds = familyIds.isEmpty ? ['family_default'] : familyIds.toSet().toList();

    for (final id in safeIds) {
      final fam = await getFamilyById(id);
      if (fam != null) {
        list.add(fam);
      }
    }

    if (list.isEmpty) {
      list.add(FamilyGroupModel(
        id: 'family_default',
        familyCode: 'CV-1001',
        name: 'My Primary Family',
        creatorUserId: 'creator_default',
        creatorName: 'Primary Caregiver',
        isCreator: true,
        membersCount: 2,
        userMembershipStatus: 'Approved',
        members: [
          FamilyGroupMemberModel(
            id: 'm1',
            userId: 'user_1',
            fullName: 'Primary Caregiver',
            email: 'caregiver@carevoice.app',
            role: 'Family Admin',
            status: 'Approved',
            joinedAt: DateTime.now().toUtc().toIso8601String(),
          ),
          FamilyGroupMemberModel(
            id: 'm2',
            userId: 'user_2',
            fullName: 'Papa',
            email: 'papa@carevoice.app',
            role: 'Family Member',
            status: 'Approved',
            joinedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ],
        pendingRequests: [],
      ));
    }
    return list;
  }

  /// Fetches discoverable family groups.
  Future<List<FamilyGroupModel>> fetchPublicFamilies() async {
    if (!_isConfigured) return [];
    try {
      final url = Uri.parse('$_firestoreBaseUrl/families?pageSize=100');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List<dynamic>?;
        if (docs == null) return [];

        final List<FamilyGroupModel> groups = [];
        for (final doc in docs) {
          final map = _parseDocumentFields(doc['fields']);
          groups.add(FamilyGroupModel.fromJson(map));
        }
        return groups;
      }
    } catch (_) {}
    return [];
  }

  /// Adds a user to a family (joining via code or Family ID)
  Future<FamilyGroupModel> joinFamilyInFirestore({
    required String familyId,
    required UserModel user,
  }) async {
    final existingFamily = await getFamilyById(familyId);
    if (existingFamily == null) {
      throw Exception('Family with ID/Code "$familyId" was not found in CareVoice.');
    }

    final updatedMembers = List<FamilyGroupMemberModel>.from(existingFamily.members);
    final alreadyMember = updatedMembers.any((m) => m.userId == user.id || m.email == user.email);

    if (!alreadyMember) {
      updatedMembers.add(FamilyGroupMemberModel(
        id: 'member_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        fullName: user.fullName,
        email: user.email,
        role: user.role,
        status: 'Approved',
        joinedAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final updatedFamily = FamilyGroupModel(
        id: existingFamily.id,
        familyCode: existingFamily.familyCode,
        name: existingFamily.name,
        creatorUserId: existingFamily.creatorUserId,
        creatorName: existingFamily.creatorName,
        isCreator: existingFamily.creatorUserId == user.id,
        membersCount: updatedMembers.length,
        userMembershipStatus: 'Approved',
        members: updatedMembers,
        pendingRequests: existingFamily.pendingRequests,
      );

      final raw = updatedFamily.toJson();
      raw['memberUserIds'] = updatedMembers.map((m) => m.userId).toList();
      raw['updatedAt'] = DateTime.now().toUtc().toIso8601String();

      await http.patch(
        Uri.parse('$_firestoreBaseUrl/families/${existingFamily.id}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(raw)}),
      );

      final userDoc = await getUserFromFirestore(user.email);
      final userFamilies = (userDoc?['familyIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      if (!userFamilies.contains(existingFamily.id)) {
        userFamilies.add(existingFamily.id);
        await saveUserInFirestore(
          email: user.email,
          fullName: user.fullName,
          userId: user.id,
          role: user.role,
          passwordHash: userDoc?['passwordHash'] ?? '',
          phoneNumber: user.phoneNumber,
          isEmailVerified: true,
          familyIds: userFamilies,
          activeFamilyId: existingFamily.id,
        );
      }
      return updatedFamily;
    }
    return existingFamily;
  }

  /// Approves a pending membership request in a family
  Future<bool> approveMemberInFirestore({required String familyId, required String targetUserId}) async {
    final family = await getFamilyById(familyId);
    if (family == null) return false;

    final pending = List<FamilyGroupMemberModel>.from(family.pendingRequests);
    final match = pending.where((p) => p.userId == targetUserId).toList();
    if (match.isEmpty) return true;

    final target = match.first;
    pending.removeWhere((p) => p.userId == targetUserId);
    final members = List<FamilyGroupMemberModel>.from(family.members);
    members.add(FamilyGroupMemberModel(
      id: target.id,
      userId: target.userId,
      fullName: target.fullName,
      email: target.email,
      role: target.role,
      status: 'Approved',
      joinedAt: DateTime.now().toUtc().toIso8601String(),
    ));

    final raw = family.toJson();
    raw['members'] = members.map((m) => m.toJson()).toList();
    raw['pendingRequests'] = pending.map((p) => p.toJson()).toList();
    raw['memberCount'] = members.length;
    raw['memberUserIds'] = members.map((m) => m.userId).toList();
    raw['updatedAt'] = DateTime.now().toUtc().toIso8601String();

    await http.patch(
      Uri.parse('$_firestoreBaseUrl/families/$familyId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': _toFirestoreFields(raw)}),
    );
    return true;
  }

  /// Removes a member from a family group
  Future<bool> leaveFamilyInFirestore({
    required String familyId,
    required String userId,
    required String userEmail,
  }) async {
    final family = await getFamilyById(familyId);
    if (family == null) return false;

    final members = List<FamilyGroupMemberModel>.from(family.members);
    members.removeWhere((m) => m.userId == userId || m.email == userEmail);

    final raw = family.toJson();
    raw['members'] = members.map((m) => m.toJson()).toList();
    raw['memberCount'] = members.length;
    raw['memberUserIds'] = members.map((m) => m.userId).toList();
    raw['updatedAt'] = DateTime.now().toUtc().toIso8601String();

    await http.patch(
      Uri.parse('$_firestoreBaseUrl/families/$familyId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': _toFirestoreFields(raw)}),
    );

    final userDoc = await getUserFromFirestore(userEmail);
    if (userDoc != null) {
      final userFamilies = (userDoc['familyIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      userFamilies.remove(familyId);
      final newActive = userFamilies.isNotEmpty ? userFamilies.first : 'family_default';
      await saveUserInFirestore(
        email: userEmail,
        fullName: userDoc['fullName'] ?? '',
        userId: userId,
        role: userDoc['role'] ?? 'Family Member',
        passwordHash: userDoc['passwordHash'] ?? '',
        phoneNumber: userDoc['phoneNumber'],
        isEmailVerified: true,
        familyIds: userFamilies,
        activeFamilyId: newActive,
      );
    }
    return true;
  }

  /// Syncs a medicine reminder schedule to Cloud Firestore with rich creator and assignment details
  Future<void> syncScheduleToFirestore({
    required String familyId,
    required String scheduleId,
    required String medicineId,
    required String medicineName,
    required String dosage,
    required String timeOfDay,
    required String targetMemberName,
    String? targetMemberId,
    String? instructions,
    String? foodRelation,
    int daysOfWeekMask = 127,
    String createdBy = 'Primary Caregiver',
    String assignedBy = 'Self',
    String status = 'Pending',
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/schedules/$scheduleId');

      final payload = {
        'scheduleId': scheduleId,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'dosage': dosage,
        'timeOfDay': timeOfDay,
        'targetMemberName': targetMemberName,
        'targetMemberId': targetMemberId ?? '',
        'instructions': instructions ?? '',
        'foodRelation': foodRelation ?? 'NoRelation',
        'daysOfWeekMask': daysOfWeekMask,
        'createdBy': createdBy,
        'assignedBy': assignedBy,
        'status': status,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(payload)}),
      );
    } catch (_) {}
  }

  /// Fetches all configured reminder schedules for a family from Cloud Firestore
  Future<List<MedicineScheduleModel>> fetchSchedulesFromFirestore({required String familyId}) async {
    if (!_isConfigured) return [];
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/schedules?pageSize=100');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List<dynamic>?;
        if (docs == null) return [];

        final List<MedicineScheduleModel> schedules = [];
        for (final doc in docs) {
          final fields = _parseDocumentFields(doc['fields']);
          schedules.add(MedicineScheduleModel(
            id: fields['scheduleId']?.toString() ?? '',
            medicineId: fields['medicineId']?.toString() ?? '',
            medicineName: fields['medicineName']?.toString() ?? 'Medicine',
            dosage: fields['dosage']?.toString() ?? '',
            targetMemberId: fields['targetMemberId']?.toString() ?? '',
            targetMemberName: fields['targetMemberName']?.toString(),
            timeOfDay: fields['timeOfDay']?.toString() ?? '08:00:00',
            daysOfWeekMask: fields['daysOfWeekMask'] is int
                ? fields['daysOfWeekMask']
                : int.tryParse(fields['daysOfWeekMask']?.toString() ?? '127') ?? 127,
            createdBy: fields['createdBy']?.toString() ?? 'Primary Caregiver',
            assignedBy: fields['assignedBy']?.toString() ?? 'Self',
            instructions: fields['instructions']?.toString(),
            foodRelation: fields['foodRelation']?.toString(),
            status: fields['status']?.toString() ?? fields['lastStatus']?.toString(),
          ));
        }
        return schedules;
      }
    } catch (_) {}
    return [];
  }

  /// Syncs an adherence log (Taken / Not Taken / Missed) to Cloud Firestore
  Future<void> syncDoseLogToFirestore({
    required String familyId,
    required String clientLogId,
    required String scheduleId,
    required String medicineName,
    required String dosage,
    required String targetMemberName,
    required String status,
    required String scheduledTime,
    String? actionTime,
    required String actorName,
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/logs/$clientLogId');
      final payload = {
        'clientLogId': clientLogId,
        'scheduleId': scheduleId,
        'medicineName': medicineName,
        'dosage': dosage,
        'targetMemberName': targetMemberName,
        'status': status,
        'scheduledTime': scheduledTime,
        'actionTime': actionTime ?? DateTime.now().toUtc().toIso8601String(),
        'actorName': actorName,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(payload)}),
      );

      await broadcastFamilyUpdate(
        familyId: effectiveFamily,
        type: 'dose_$status',
        title: '$medicineName marked as $status',
        titleBn: '$medicineName - ${status == "Taken" ? "খেয়েছেন" : "খাননি"} হিসেবে চিহ্নিত',
        description: '$targetMemberName: $dosage ($status)',
        descriptionBn: '$targetMemberName: $dosage (${status == "Taken" ? "খেয়েছেন" : "খাননি"})',
        actorName: actorName,
      );
    } catch (_) {}
  }

  /// Fetches adherence dose logs from Cloud Firestore for a family
  Future<List<Map<String, dynamic>>> fetchDoseLogsFromFirestore({required String familyId}) async {
    if (!_isConfigured) return [];
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/logs?pageSize=100');
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final docs = data['documents'] as List<dynamic>?;
        if (docs == null) return [];

        final List<Map<String, dynamic>> logs = [];
        for (final doc in docs) {
          final fields = _parseDocumentFields(doc['fields']);
          logs.add(fields);
        }
        return logs;
      }
    } catch (_) {}
    return [];
  }

  /// Updates schedule document in Cloud Firestore with latest adherence status and lastTakenTime
  Future<void> updateScheduleStatus({
    required String familyId,
    required String scheduleId,
    required String status,
    required String lastTakenTime,
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse(
        '$_firestoreBaseUrl/families/$effectiveFamily/schedules/$scheduleId?updateMask.fieldPaths=lastStatus&updateMask.fieldPaths=status&updateMask.fieldPaths=lastTakenTime',
      );
      final payload = {
        'lastStatus': status,
        'status': status,
        'lastTakenTime': lastTakenTime,
      };
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(payload)}),
      );
    } catch (_) {}
  }

  /// Deletes a schedule from Cloud Firestore
  Future<void> deleteScheduleFromFirestore({
    required String familyId,
    required String scheduleId,
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/schedules/$scheduleId');
      await http.delete(url);
    } catch (_) {}
  }

  /// Syncs a medicine to Cloud Firestore
  Future<void> syncMedicineToFirestore({
    required String familyId,
    required MedicineModel medicine,
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/medicines/${medicine.id}');
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(medicine.toJson())}),
      );
    } catch (_) {}
  }

  /// Fetches all medicines for a family from Cloud Firestore
  Future<List<MedicineModel>> fetchMedicinesFromFirestore({required String familyId}) async {
    if (!_isConfigured) return [];
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/medicines?pageSize=100');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List<dynamic>?;
        if (docs == null) return [];
        return docs.map((d) => MedicineModel.fromJson(_parseDocumentFields(d['fields']))).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Deletes a medicine from Cloud Firestore
  Future<void> deleteMedicineFromFirestore({
    required String familyId,
    required String medicineId,
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      await http.delete(Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/medicines/$medicineId'));
    } catch (_) {}
  }

  /// Syncs a family member to Cloud Firestore
  Future<void> syncMemberToFirestore({
    required String familyId,
    required FamilyMemberModel member,
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/members/${member.id}');
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(member.toJson())}),
      );
    } catch (_) {}
  }

  /// Fetches family members from Cloud Firestore
  Future<List<FamilyMemberModel>> fetchMembersFromFirestore({required String familyId}) async {
    if (!_isConfigured) return [];
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/members?pageSize=100');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List<dynamic>?;
        if (docs == null) return [];
        return docs.map((d) => FamilyMemberModel.fromJson(_parseDocumentFields(d['fields']))).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Deletes a family member from Cloud Firestore
  Future<void> deleteMemberFromFirestore({
    required String familyId,
    required String memberId,
  }) async {
    if (!_isConfigured) return;
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      await http.delete(Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/members/$memberId'));
    } catch (_) {}
  }

  /// Broadcasts a real-time medicine update to all family members
  Future<void> broadcastFamilyUpdate({
    required String familyId,
    required String type,
    required String title,
    required String titleBn,
    required String description,
    required String descriptionBn,
    required String actorName,
  }) async {
    if (!_isConfigured) return;
    try {
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      final url = Uri.parse('$_firestoreBaseUrl/families/$familyId/updates/$docId');
      final payload = {
        'type': type,
        'title': title,
        'titleBn': titleBn,
        'description': description,
        'descriptionBn': descriptionBn,
        'actorName': actorName,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };

      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'fields': _toFirestoreFields(payload)}),
      );
    } catch (_) {}
  }

  /// Fetches shared family activity stream from Cloud Firestore
  Future<List<SharedFamilyUpdateModel>> fetchFamilyUpdates({required String familyId}) async {
    if (!_isConfigured) return [];
    try {
      final effectiveFamily = familyId.isEmpty ? 'family_default' : familyId;
      final url = Uri.parse('$_firestoreBaseUrl/families/$effectiveFamily/updates?pageSize=50');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['documents'] as List<dynamic>?;
        if (docs == null) return [];
        final List<SharedFamilyUpdateModel> updates = [];
        for (final doc in docs) {
          final fields = _parseDocumentFields(doc['fields']);
          updates.add(SharedFamilyUpdateModel(
            id: doc['name']?.toString().split('/').last ?? '',
            familyGroupId: effectiveFamily,
            type: fields['type']?.toString() ?? 'general',
            title: fields['title']?.toString() ?? '',
            titleBn: fields['titleBn']?.toString() ?? '',
            description: fields['description']?.toString() ?? '',
            descriptionBn: fields['descriptionBn']?.toString() ?? '',
            actorName: fields['actorName']?.toString() ?? 'Caregiver',
            timestamp: fields['timestamp']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
          ));
        }
        return updates;
      }
    } catch (_) {}
    return [];
  }
}
