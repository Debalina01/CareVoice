import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../core/firebase_service.dart';
import '../domain/models.dart';
import 'api_client.dart';
import 'local_db.dart';

class FamilyRepository {
  final _storage = const FlutterSecureStorage();
  final _client = ApiClient.instance;

  Future<List<FamilyMemberModel>> getFamilyMembers({String? familyId}) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : (await _storage.read(key: 'carevoice_active_family_id') ?? 'family_default');

    if (await _client.hasJwtToken()) {
      try {
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http.get(_client.uri('/api/family-members'), headers: headers).timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200) {
          final List list = jsonDecode(res.body);
          final members = list.map((m) => FamilyMemberModel.fromJson(m)).toList();
          if (members.isNotEmpty) {
            await LocalDatabase.saveCachedMembers(members);
            return members;
          }
        }
      } catch (_) {}
    }

    final cached = await LocalDatabase.getCachedMembers();
    _syncMembersInBackground(effectiveFamily);
    return cached;
  }

  void _syncMembersInBackground(String familyId) async {
    try {
      final remoteMembers = await FirebaseService.instance.fetchMembersFromFirestore(familyId: familyId);
      if (remoteMembers.isNotEmpty) {
        await LocalDatabase.saveCachedMembers(remoteMembers);
      }
    } catch (_) {}
  }

  Future<FamilyMemberModel> createFamilyMember({
    required String fullName,
    required String relation,
    String preferredLanguage = 'en',
    String voicePreference = 'en-US-Standard-A',
    String? username,
    String? password,
    String? familyId,
  }) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : (await _storage.read(key: 'carevoice_active_family_id') ?? 'family_default');

    FamilyMemberModel? created;

    if (await _client.hasJwtToken()) {
      try {
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http
              .post(
                _client.uri('/api/family-members'),
                headers: headers,
                body: jsonEncode({
                  'fullName': fullName.trim(),
                  'relation': relation.trim(),
                  'preferredLanguage': preferredLanguage,
                  'voicePreference': voicePreference,
                  if (username != null && username.trim().isNotEmpty) 'username': username.trim(),
                  if (password != null && password.trim().isNotEmpty) 'password': password.trim(),
                }),
              )
              .timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200 || res.statusCode == 201) {
          created = FamilyMemberModel.fromJson(jsonDecode(res.body));
        }
      } catch (_) {}
    }

    created ??= FamilyMemberModel(
      id: 'member_${DateTime.now().millisecondsSinceEpoch}',
      fullName: fullName,
      relation: relation,
      preferredLanguage: preferredLanguage,
      voicePreference: voicePreference,
      username: username,
      hasLoginCredentials: username != null && username.trim().isNotEmpty,
    );

    await LocalDatabase.addCachedMember(created);
    await FirebaseService.instance.syncMemberToFirestore(familyId: effectiveFamily, member: created);
    await FirebaseService.instance.broadcastFamilyUpdate(
      familyId: effectiveFamily,
      type: 'member_added',
      title: 'Member Added: $fullName',
      titleBn: 'নতুন সদস্য যুক্ত হয়েছে: $fullName',
      description: 'Relation: $relation',
      descriptionBn: 'সম্পর্ক: $relation',
      actorName: 'Primary Caregiver',
    );

    return created;
  }

  Future<void> updateFamilyMember({
    required String id,
    required String fullName,
    required String relation,
    String? age,
    String? notes,
    String? preferredLanguage,
    String? voicePreference,
    String? familyId,
  }) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : (await _storage.read(key: 'carevoice_active_family_id') ?? 'family_default');

    FamilyMemberModel updated = FamilyMemberModel(
      id: id,
      fullName: fullName,
      relation: relation,
      preferredLanguage: preferredLanguage ?? 'en',
      voicePreference: voicePreference ?? 'en-US-Standard-A',
    );

    if (await _client.hasJwtToken()) {
      try {
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http
              .put(
                _client.uri('/api/family-members/$id'),
                headers: headers,
                body: jsonEncode({
                  'fullName': fullName.trim(),
                  'relation': relation.trim(),
                  'preferredLanguage': preferredLanguage ?? 'en',
                  'voicePreference': voicePreference ?? 'en-US-Standard-A',
                }),
              )
              .timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200) {
          updated = FamilyMemberModel.fromJson(jsonDecode(res.body));
        }
      } catch (_) {}
    }

    await LocalDatabase.addCachedMember(updated);
    await FirebaseService.instance.syncMemberToFirestore(familyId: effectiveFamily, member: updated);
  }

  Future<void> deleteFamilyMember(String id, {String? familyId, String? memberEmail}) async {
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : (await _storage.read(key: 'carevoice_active_family_id') ?? 'family_default');

    if (await _client.hasJwtToken()) {
      try {
        await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http.delete(_client.uri('/api/family-members/$id'), headers: headers).timeout(const Duration(seconds: 10));
        });
      } catch (_) {}
    }

    await LocalDatabase.deleteCachedMember(id);
    await FirebaseService.instance.deleteMemberFromFirestore(familyId: effectiveFamily, memberId: id);

    if (memberEmail != null && memberEmail.trim().isNotEmpty) {
      try {
        await FirebaseService.instance.leaveFamilyInFirestore(
          familyId: effectiveFamily,
          userId: id,
          userEmail: memberEmail.trim().toLowerCase(),
        );
      } catch (_) {}
    }
  }

  Future<FamilyMemberModel> addExistingUserToFamily({
    required String email,
    required String relation,
    String? familyId,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final effectiveFamily = (familyId != null && familyId.isNotEmpty)
        ? familyId
        : (await _storage.read(key: 'carevoice_active_family_id') ?? 'family_default');

    final userDoc = await FirebaseService.instance.getUserFromFirestore(cleanEmail);
    if (userDoc == null) {
      throw Exception('No CareVoice account found for "$cleanEmail". Please ask them to register first.');
    }

    final String userId = userDoc['userId']?.toString() ?? 'user_${DateTime.now().millisecondsSinceEpoch}';
    final String fullName = userDoc['fullName']?.toString() ?? cleanEmail.split('@').first;
    final String role = userDoc['role']?.toString() ?? 'Family Member';
    final List<String> familyIds = (userDoc['familyIds'] as List?)?.map((e) => e.toString()).toList() ?? [];

    if (familyIds.contains(effectiveFamily)) {
      throw Exception('$fullName ($cleanEmail) is already in this family group.');
    }

    final currentMembers = await getFamilyMembers(familyId: effectiveFamily);
    if (currentMembers.any((m) => m.username?.toLowerCase() == cleanEmail || m.id == userId)) {
      throw Exception('$fullName ($cleanEmail) is already in this family.');
    }

    familyIds.add(effectiveFamily);
    await FirebaseService.instance.saveUserInFirestore(
      email: cleanEmail,
      fullName: fullName,
      userId: userId,
      role: role,
      passwordHash: userDoc['passwordHash'] ?? '',
      phoneNumber: userDoc['phoneNumber'],
      isEmailVerified: true,
      familyIds: familyIds,
      activeFamilyId: effectiveFamily,
    );

    final newMember = FamilyMemberModel(
      id: userId,
      fullName: fullName,
      relation: relation,
      preferredLanguage: 'en',
      voicePreference: 'en-US-Standard-A',
      username: cleanEmail,
      hasLoginCredentials: true,
    );

    await LocalDatabase.addCachedMember(newMember);
    await FirebaseService.instance.syncMemberToFirestore(familyId: effectiveFamily, member: newMember);

    try {
      await FirebaseService.instance.joinFamilyInFirestore(
        familyId: effectiveFamily,
        user: UserModel(
          id: userId,
          email: cleanEmail,
          fullName: fullName,
          role: role,
          defaultFamilyMemberId: userId,
          isEmailVerified: true,
          familyIds: familyIds,
          activeFamilyId: effectiveFamily,
        ),
      );
    } catch (_) {}

    await FirebaseService.instance.broadcastFamilyUpdate(
      familyId: effectiveFamily,
      type: 'member_added',
      title: 'Member Added: $fullName',
      titleBn: 'নতুন সদস্য যুক্ত হয়েছে: $fullName',
      description: 'Added to family as $relation',
      descriptionBn: 'পরিবারে $relation হিসেবে যুক্ত হয়েছেন',
      actorName: 'Family Admin',
    );

    return newMember;
  }

  Future<InviteModel> createInvite(String email) async {
    if (await _client.hasJwtToken()) {
      try {
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http
              .post(
                _client.uri('/api/invites'),
                headers: headers,
                body: jsonEncode({'invitedEmail': email.trim(), 'canSetReminders': true, 'canViewLogs': true}),
              )
              .timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200 || res.statusCode == 201) {
          return InviteModel.fromJson(jsonDecode(res.body));
        }
      } catch (_) {}
    }

    final token = 'CV-${Random().nextInt(9000) + 1000}';
    return InviteModel(
      id: 'inv_${DateTime.now().millisecondsSinceEpoch}',
      inviterMemberId: 'self',
      inviterName: 'Primary Caregiver',
      invitedEmail: email,
      inviteToken: token,
      status: 'Pending',
      expiresAt: DateTime.now().add(const Duration(days: 7)).toIso8601String(),
    );
  }

  Future<bool> acceptInvite(String token) async {
    if (await _client.hasJwtToken()) {
      try {
        final res = await _client.sendWithRefresh(() async {
          final headers = await _client.authHeaders();
          return http
              .post(_client.uri('/api/invites/accept'), headers: headers, body: jsonEncode({'inviteToken': token.trim()}))
              .timeout(const Duration(seconds: 10));
        });
        if (res.statusCode == 200) return true;
      } catch (_) {}
    }
    return true;
  }
}
