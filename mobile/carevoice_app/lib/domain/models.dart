class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String? phoneNumber;
  final String role;
  final String defaultFamilyMemberId;
  final bool isEmailVerified;
  final List<String> familyIds;
  final String? activeFamilyId;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    this.phoneNumber,
    this.role = 'Family Admin',
    required this.defaultFamilyMemberId,
    this.isEmailVerified = false,
    this.familyIds = const [],
    this.activeFamilyId,
  });

  bool get isSuperAdmin => role.toLowerCase() == 'super admin';
  bool get isFamilyAdmin =>
      role.toLowerCase() == 'family admin' || role.toLowerCase() == 'caregiver' || isSuperAdmin;
  bool get isCaretaker =>
      role.toLowerCase() == 'caretaker' || isFamilyAdmin;
  bool get isFamilyMember =>
      role.toLowerCase() == 'family member' || role.toLowerCase() == 'individual' || role.toLowerCase() == 'patient';

  factory UserModel.fromJson(Map<String, dynamic> json) {
    List<String> families = [];
    if (json['familyIds'] is List) {
      families = (json['familyIds'] as List).map((e) => e.toString()).toList();
    } else if (json['familyId'] != null) {
      families = [json['familyId'].toString()];
    }

    return UserModel(
      id: json['id'] ?? json['userId'] ?? '',
      email: json['email'] ?? '',
      fullName: json['fullName'] ?? '',
      phoneNumber: json['phoneNumber'],
      role: json['role'] ?? 'Family Admin',
      defaultFamilyMemberId: json['defaultFamilyMemberId'] ?? '',
      isEmailVerified: json['isEmailVerified'] == true,
      familyIds: families,
      activeFamilyId: json['activeFamilyId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': id,
    'email': email,
    'fullName': fullName,
    'phoneNumber': phoneNumber,
    'role': role,
    'defaultFamilyMemberId': defaultFamilyMemberId,
    'isEmailVerified': isEmailVerified,
    'familyIds': familyIds,
    'activeFamilyId': activeFamilyId,
  };
}

class FamilyMemberModel {
  final String id;
  final String fullName;
  final String relation;
  final String preferredLanguage;
  final String voicePreference;
  final bool isSelf;
  final bool canSetReminders;
  final bool canViewLogs;
  final String? username;
  final bool hasLoginCredentials;

  FamilyMemberModel({
    required this.id,
    required this.fullName,
    required this.relation,
    required this.preferredLanguage,
    required this.voicePreference,
    this.isSelf = false,
    this.canSetReminders = true,
    this.canViewLogs = true,
    this.username,
    this.hasLoginCredentials = false,
  });

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    return FamilyMemberModel(
      id: json['id'] ?? '',
      fullName: json['fullName'] ?? '',
      relation: json['relation'] ?? '',
      preferredLanguage: json['preferredLanguage'] ?? 'en',
      voicePreference: json['voicePreference'] ?? 'en-US-Standard-A',
      isSelf: json['isSelf'] ?? false,
      canSetReminders: json['canSetReminders'] ?? true,
      canViewLogs: json['canViewLogs'] ?? true,
      username: json['username'],
      hasLoginCredentials: json['hasLoginCredentials'] ?? (json['username'] != null),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fullName': fullName,
    'relation': relation,
    'preferredLanguage': preferredLanguage,
    'voicePreference': voicePreference,
    'isSelf': isSelf,
    'canSetReminders': canSetReminders,
    'canViewLogs': canViewLogs,
    'username': username,
    'hasLoginCredentials': hasLoginCredentials,
  };
}

class FamilyGroupMemberModel {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final String role;
  final String status;
  final String joinedAt;

  FamilyGroupMemberModel({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.status,
    required this.joinedAt,
  });

  factory FamilyGroupMemberModel.fromJson(Map<String, dynamic> json) {
    return FamilyGroupMemberModel(
      id: json['id'] ?? '',
      userId: json['userId'] ?? '',
      fullName: json['fullName'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'Member',
      status: json['status'] ?? 'Approved',
      joinedAt: json['joinedAt'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'fullName': fullName,
    'email': email,
    'role': role,
    'status': status,
    'joinedAt': joinedAt,
  };
}

class FamilyGroupModel {
  final String id;
  final String familyCode;
  final String name;
  final String creatorUserId;
  final String creatorName;
  final bool isCreator;
  final int membersCount;
  final String userMembershipStatus;
  final List<FamilyGroupMemberModel> members;
  final List<FamilyGroupMemberModel> pendingRequests;
  final bool isPublic;
  final String? description;

  FamilyGroupModel({
    required this.id,
    required this.familyCode,
    required this.name,
    required this.creatorUserId,
    required this.creatorName,
    required this.isCreator,
    required this.membersCount,
    required this.userMembershipStatus,
    required this.members,
    required this.pendingRequests,
    this.isPublic = true,
    this.description,
  });

  factory FamilyGroupModel.fromJson(Map<String, dynamic> json) {
    return FamilyGroupModel(
      id: json['id'] ?? '',
      familyCode: json['familyCode'] ?? '',
      name: json['name'] ?? '',
      creatorUserId: json['creatorUserId'] ?? '',
      creatorName: json['creatorName'] ?? '',
      isCreator: json['isCreator'] ?? false,
      membersCount: json['membersCount'] ?? (json['members'] as List?)?.length ?? 1,
      userMembershipStatus: json['userMembershipStatus'] ?? 'Approved',
      members: (json['members'] as List?)
              ?.map((e) => FamilyGroupMemberModel.fromJson(e))
              .toList() ??
          [],
      pendingRequests: (json['pendingRequests'] as List?)
              ?.map((e) => FamilyGroupMemberModel.fromJson(e))
              .toList() ??
          [],
      isPublic: json['isPublic'] != false,
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyCode': familyCode,
    'name': name,
    'creatorUserId': creatorUserId,
    'creatorName': creatorName,
    'isCreator': isCreator,
    'membersCount': membersCount,
    'userMembershipStatus': userMembershipStatus,
    'members': members.map((m) => m.toJson()).toList(),
    'pendingRequests': pendingRequests.map((p) => p.toJson()).toList(),
    'isPublic': isPublic,
    'description': description,
  };
}

class SharedFamilyUpdateModel {
  final String id;
  final String familyGroupId;
  final String type;
  final String title;
  final String titleBn;
  final String description;
  final String descriptionBn;
  final String actorName;
  final String timestamp;

  SharedFamilyUpdateModel({
    required this.id,
    required this.familyGroupId,
    required this.type,
    required this.title,
    required this.titleBn,
    required this.description,
    required this.descriptionBn,
    required this.actorName,
    required this.timestamp,
  });

  factory SharedFamilyUpdateModel.fromJson(Map<String, dynamic> json) {
    return SharedFamilyUpdateModel(
      id: json['id'] ?? '',
      familyGroupId: json['familyGroupId'] ?? '',
      type: json['type'] ?? '',
      title: json['title'] ?? '',
      titleBn: json['titleBn'] ?? '',
      description: json['description'] ?? '',
      descriptionBn: json['descriptionBn'] ?? '',
      actorName: json['actorName'] ?? '',
      timestamp: json['timestamp'] ?? '',
    );
  }
}

class InviteModel {
  final String id;
  final String inviterMemberId;
  final String inviterName;
  final String invitedEmail;
  final String inviteToken;
  final String status;
  final String expiresAt;

  InviteModel({
    required this.id,
    required this.inviterMemberId,
    required this.inviterName,
    required this.invitedEmail,
    required this.inviteToken,
    required this.status,
    required this.expiresAt,
  });

  factory InviteModel.fromJson(Map<String, dynamic> json) {
    return InviteModel(
      id: json['id'] ?? '',
      inviterMemberId: json['inviterMemberId'] ?? '',
      inviterName: json['inviterName'] ?? '',
      invitedEmail: json['invitedEmail'] ?? '',
      inviteToken: json['inviteToken'] ?? '',
      status: json['status']?.toString() ?? 'Pending',
      expiresAt: json['expiresAt'] ?? '',
    );
  }
}

class MedicineModel {
  final String id;
  final String name;
  final String dosage;
  final String? instructions;
  final String foodRelation;
  final String? ownerMemberId;
  final String? ownerMemberName;
  final DateTime? startDate;
  final DateTime? endDate;

  MedicineModel({
    required this.id,
    required this.name,
    required this.dosage,
    this.instructions,
    required this.foodRelation,
    this.ownerMemberId,
    this.ownerMemberName,
    this.startDate,
    this.endDate,
  });

  factory MedicineModel.fromJson(Map<String, dynamic> json) {
    return MedicineModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      dosage: json['dosage'] ?? '',
      instructions: json['instructions'],
      foodRelation: json['foodRelation'] ?? 'NoRelation',
      ownerMemberId: json['ownerMemberId']?.toString(),
      ownerMemberName: json['ownerMemberName']?.toString(),
      startDate: json['startDate'] != null ? DateTime.tryParse(json['startDate']) : null,
      endDate: json['endDate'] != null ? DateTime.tryParse(json['endDate']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'dosage': dosage,
    'instructions': instructions,
    'foodRelation': foodRelation,
    'ownerMemberId': ownerMemberId,
    'ownerMemberName': ownerMemberName,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
  };
}

class MedicineScheduleModel {
  final String id;
  final String medicineId;
  final String medicineName;
  final String dosage;
  final String targetMemberId;
  final String? targetMemberName;
  final String timeOfDay;
  final int daysOfWeekMask;
  final String createdBy;
  final String assignedBy;
  final String? instructions;
  final String? foodRelation;
  final String? status;

  MedicineScheduleModel({
    required this.id,
    required this.medicineId,
    required this.medicineName,
    required this.dosage,
    required this.targetMemberId,
    this.targetMemberName,
    required this.timeOfDay,
    required this.daysOfWeekMask,
    this.createdBy = 'Primary Caregiver',
    this.assignedBy = 'Self',
    this.instructions,
    this.foodRelation,
    this.status,
  });

  factory MedicineScheduleModel.fromJson(Map<String, dynamic> json) {
    return MedicineScheduleModel(
      id: json['id'] ?? '',
      medicineId: json['medicineId'] ?? '',
      medicineName: json['medicineName'] ?? 'Medicine',
      dosage: json['dosage'] ?? '',
      targetMemberId: json['targetMemberId'] ?? '',
      targetMemberName: json['targetMemberName'],
      timeOfDay: json['timeOfDay'] ?? '08:00:00',
      daysOfWeekMask: json['daysOfWeekMask'] is int
          ? json['daysOfWeekMask']
          : int.tryParse(json['daysOfWeekMask']?.toString() ?? '127') ?? 127,
      createdBy: json['createdBy']?.toString() ?? 'Primary Caregiver',
      assignedBy: json['assignedBy']?.toString() ?? 'Self',
      instructions: json['instructions']?.toString(),
      foodRelation: json['foodRelation']?.toString(),
      status: json['status']?.toString() ?? json['lastStatus']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medicineId': medicineId,
      'medicineName': medicineName,
      'dosage': dosage,
      'targetMemberId': targetMemberId,
      'targetMemberName': targetMemberName ?? '',
      'timeOfDay': timeOfDay,
      'daysOfWeekMask': daysOfWeekMask,
      'createdBy': createdBy,
      'assignedBy': assignedBy,
      'instructions': instructions ?? '',
      'foodRelation': foodRelation ?? 'NoRelation',
      'status': status ?? 'Pending',
    };
  }

  Map<String, dynamic> toJson() => toMap();
}

class DoseSyncModel {
  final String scheduleId;
  final String medicineId;
  final String medicineName;
  final String dosage;
  final String? instructions;
  final String foodRelation;
  final String targetMemberId;
  final String targetMemberName;
  final String scheduledTimeUtc;
  final String timeOfDay;
  final String preferredLanguage;
  final String voicePreference;
  final String createdBy;
  final String assignedBy;
  final String status;

  DoseSyncModel({
    required this.scheduleId,
    required this.medicineId,
    required this.medicineName,
    required this.dosage,
    this.instructions,
    required this.foodRelation,
    required this.targetMemberId,
    required this.targetMemberName,
    required this.scheduledTimeUtc,
    required this.timeOfDay,
    required this.preferredLanguage,
    required this.voicePreference,
    this.createdBy = 'Primary Caregiver',
    this.assignedBy = 'Self',
    this.status = 'Pending',
  });

  factory DoseSyncModel.fromJson(Map<String, dynamic> json) {
    return DoseSyncModel(
      scheduleId: json['scheduleId'] ?? '',
      medicineId: json['medicineId'] ?? '',
      medicineName: json['medicineName'] ?? 'Medicine',
      dosage: json['dosage'] ?? '',
      instructions: json['instructions'],
      foodRelation: json['foodRelation']?.toString() ?? 'NoRelation',
      targetMemberId: json['targetMemberId'] ?? '',
      targetMemberName: json['targetMemberName'] ?? 'Member',
      scheduledTimeUtc: json['scheduledTimeUtc'] ?? '',
      timeOfDay: json['timeOfDay'] ?? '08:00',
      preferredLanguage: json['preferredLanguage'] ?? 'en',
      voicePreference: json['voicePreference'] ?? 'en-US-Standard-A',
      createdBy: json['createdBy']?.toString() ?? 'Primary Caregiver',
      assignedBy: json['assignedBy']?.toString() ?? 'Self',
      status: json['status']?.toString() ?? 'Pending',
    );
  }
}

class DoseHistoryModel {
  final String logId;
  final String clientLogId;
  final String scheduleId;
  final String medicineName;
  final String dosage;
  final String targetMemberId;
  final String targetMemberName;
  final String scheduledTime;
  final String? actionTime;
  final String status;

  DoseHistoryModel({
    required this.logId,
    required this.clientLogId,
    required this.scheduleId,
    required this.medicineName,
    required this.dosage,
    required this.targetMemberId,
    required this.targetMemberName,
    required this.scheduledTime,
    this.actionTime,
    required this.status,
  });

  factory DoseHistoryModel.fromJson(Map<String, dynamic> json) {
    return DoseHistoryModel(
      logId: json['logId'] ?? '',
      clientLogId: json['clientLogId'] ?? '',
      scheduleId: json['scheduleId'] ?? '',
      medicineName: json['medicineName'] ?? 'Medicine',
      dosage: json['dosage'] ?? '',
      targetMemberId: json['targetMemberId'] ?? '',
      targetMemberName: json['targetMemberName'] ?? 'Member',
      scheduledTime: json['scheduledTime'] ?? '',
      actionTime: json['actionTime'],
      status: json['status']?.toString() ?? 'Taken',
    );
  }
}

class ExtractedScheduleModel {
  String medicineName;
  String dosage;
  String foodRelation;
  String? instructions;
  List<String> timesOfDay;
  int daysOfWeekMask;
  int? durationDays;
  String? targetMemberId;
  String? targetMemberName;
  DateTime? startDate;
  DateTime? endDate;

  ExtractedScheduleModel({
    required this.medicineName,
    required this.dosage,
    this.foodRelation = 'NoRelation',
    this.instructions,
    required this.timesOfDay,
    this.daysOfWeekMask = 127,
    this.durationDays,
    this.targetMemberId,
    this.targetMemberName,
    this.startDate,
    this.endDate,
  });

  factory ExtractedScheduleModel.fromJson(Map<String, dynamic> json) {
    return ExtractedScheduleModel(
      medicineName: json['medicineName'] ?? '',
      dosage: json['dosage'] ?? '',
      foodRelation: json['foodRelation']?.toString() ?? 'NoRelation',
      instructions: json['instructions'],
      timesOfDay: (json['timesOfDay'] as List?)?.map((e) => normalizeTimeString(e.toString())).toList() ?? [],
      daysOfWeekMask: json['daysOfWeekMask'] ?? 127,
      durationDays: json['durationDays'],
      targetMemberId: json['targetMemberId'],
      targetMemberName: json['targetMemberName'],
      startDate: json['startDate'] != null ? DateTime.tryParse(json['startDate']) : null,
      endDate: json['endDate'] != null ? DateTime.tryParse(json['endDate']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'medicineName': medicineName,
    'dosage': dosage,
    'foodRelation': foodRelation,
    'instructions': instructions,
    'timesOfDay': timesOfDay.map((e) => normalizeTimeString(e)).toList(),
    'daysOfWeekMask': daysOfWeekMask,
    'durationDays': durationDays,
    'targetMemberId': targetMemberId,
    'targetMemberName': targetMemberName,
    if (startDate != null) 'startDate': startDate!.toUtc().toIso8601String(),
    if (endDate != null) 'endDate': endDate!.toUtc().toIso8601String(),
  };
}

String normalizeTimeString(String? raw, {String fallback = '08:00'}) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  var text = raw.trim();

  const bnDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];
  for (int i = 0; i < bnDigits.length; i++) {
    text = text.replaceAll(bnDigits[i], i.toString());
  }

  final regex = RegExp(
    r'^\s*(?:(সকাল|ভোর|দুপুর|সন্ধ্যা|বিকাল|রাত)\s*)?(\d{1,2})(?:[:.](\d{1,2}))?(?::(\d{1,2}))?\s*(am|pm|টা)?(?:\s*(সকাল|ভোর|দুপুর|সন্ধ্যা|বিকাল|রাত))?\s*$',
    caseSensitive: false,
  );
  final match = regex.firstMatch(text);
  if (match != null) {
    int h = int.tryParse(match.group(2) ?? '') ?? 8;
    int m = int.tryParse(match.group(3) ?? '') ?? 0;
    final ampm = (match.group(5) ?? '').toLowerCase();
    final periodBn = (match.group(1) ?? '') + (match.group(6) ?? '');

    bool isPm = ampm == 'pm' || periodBn == 'রাত' || periodBn == 'সন্ধ্যা' || periodBn == 'বিকাল';
    bool isAm = ampm == 'am' || periodBn == 'সকাল' || periodBn == 'ভোর';

    if (periodBn == 'দুপুর' && h >= 1 && h < 12) {
      isPm = true;
    }

    if (isPm && h < 12) {
      h += 12;
    } else if (isAm && h == 12) {
      h = 0;
    }

    if (h >= 0 && h < 24 && m >= 0 && m < 60) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
  }

  final parts = text.split(':');
  if (parts.length >= 2) {
    int? h = int.tryParse(parts[0]);
    int? m = int.tryParse(parts[1]);
    if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
  }

  return text;
}

class SerbomAiResponseModel {
  final String intent;
  final String status;
  final String replyMessage;
  final String replyMessageBn;
  final ExtractedScheduleModel? extractedSchedule;
  final List<String> missingFields;
  final String? followUpQuestion;
  final String? followUpQuestionBn;

  SerbomAiResponseModel({
    required this.intent,
    required this.status,
    required this.replyMessage,
    required this.replyMessageBn,
    this.extractedSchedule,
    required this.missingFields,
    this.followUpQuestion,
    this.followUpQuestionBn,
  });

  factory SerbomAiResponseModel.fromJson(Map<String, dynamic> json) {
    return SerbomAiResponseModel(
      intent: json['intent'] ?? 'GeneralChat',
      status: json['status'] ?? 'ReadyForConfirmation',
      replyMessage: json['replyMessage'] ?? '',
      replyMessageBn: json['replyMessageBn'] ?? '',
      extractedSchedule: json['extractedSchedule'] != null
          ? ExtractedScheduleModel.fromJson(json['extractedSchedule'])
          : null,
      missingFields: (json['missingFields'] as List?)?.map((e) => e.toString()).toList() ?? [],
      followUpQuestion: json['followUpQuestion'],
      followUpQuestionBn: json['followUpQuestionBn'],
    );
  }
}

class MedicalDocumentModel {
  final String id;
  final String ownerMemberId;
  final String ownerMemberName;
  final String uploadedByUserId;
  final String uploadedByName;
  final String? medicineId;
  final String? medicineName;
  final String title;
  final String category;
  final String? notes;
  final String originalFileName;
  final String contentType;
  final int fileSizeBytes;
  final String createdAt;

  MedicalDocumentModel({
    required this.id,
    required this.ownerMemberId,
    required this.ownerMemberName,
    required this.uploadedByUserId,
    required this.uploadedByName,
    this.medicineId,
    this.medicineName,
    required this.title,
    required this.category,
    this.notes,
    required this.originalFileName,
    required this.contentType,
    required this.fileSizeBytes,
    required this.createdAt,
  });

  bool get isImage => contentType.toLowerCase().startsWith('image/');
  bool get isPdf => contentType.toLowerCase() == 'application/pdf' || originalFileName.toLowerCase().endsWith('.pdf');

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  factory MedicalDocumentModel.fromJson(Map<String, dynamic> json) {
    return MedicalDocumentModel(
      id: json['id']?.toString() ?? '',
      ownerMemberId: json['ownerMemberId']?.toString() ?? '',
      ownerMemberName: json['ownerMemberName']?.toString() ?? '',
      uploadedByUserId: json['uploadedByUserId']?.toString() ?? '',
      uploadedByName: json['uploadedByName']?.toString() ?? '',
      medicineId: json['medicineId']?.toString(),
      medicineName: json['medicineName']?.toString(),
      title: json['title']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Prescription',
      notes: json['notes']?.toString(),
      originalFileName: json['originalFileName']?.toString() ?? 'document',
      contentType: json['contentType']?.toString() ?? 'application/octet-stream',
      fileSizeBytes: (json['fileSizeBytes'] is int)
          ? json['fileSizeBytes'] as int
          : int.tryParse(json['fileSizeBytes']?.toString() ?? '0') ?? 0,
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}
