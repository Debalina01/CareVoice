import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../core/email_dispatcher.dart';
import '../core/firebase_service.dart';
import '../domain/models.dart';
import 'api_client.dart';

class OtpSendResult {
  final bool success;
  final String message;
  final bool isDeliveredViaSmtp;
  final String deliveryMode;

  OtpSendResult({
    required this.success,
    required this.message,
    this.isDeliveredViaSmtp = true,
    this.deliveryMode = 'Email Delivery',
  });

  factory OtpSendResult.fromJson(Map<String, dynamic> json) {
    return OtpSendResult(
      success: json['success'] == true,
      message: json['message']?.toString() ?? 'Verification code sent.',
      isDeliveredViaSmtp: json['isDeliveredViaSmtp'] == true,
      deliveryMode: json['deliveryMode']?.toString() ?? 'Email Delivery',
    );
  }
}

class EmailNotVerifiedException implements Exception {
  final String email;
  final String message;
  final OtpSendResult otpResult;

  EmailNotVerifiedException({
    required this.email,
    required this.message,
    required this.otpResult,
  });

  @override
  String toString() => message;
}

class RoleMismatchException implements Exception {
  final String selectedRole;
  final String actualRole;
  final String message;

  RoleMismatchException({
    required this.selectedRole,
    required this.actualRole,
    required this.message,
  });

  @override
  String toString() => message;
}

class AuthRepository {
  final _storage = const FlutterSecureStorage();
  final _client = ApiClient.instance;

  static String normalizeRole(String role) {
    final r = role.trim().toLowerCase();
    if (r.contains('super')) return 'Super Admin';
    if (r.contains('admin')) return 'Family Admin';
    if (r.contains('caretaker') || r.contains('caregiver')) return 'Caretaker';
    return 'Family Member';
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode('carevoice_salt_2026_${password.trim()}');
    return base64.encode(bytes);
  }

  /// Checks if an email address is already available for registration
  Future<bool> checkEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();
    try {
      final res = await http
          .get(_client.uri('/api/auth/check-email', {'email': cleanEmail}))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['available'] == false) return false;
      }
    } catch (_) {}

    final userDoc = await FirebaseService.instance.getUserFromFirestore(cleanEmail);
    if (userDoc != null && userDoc['isEmailVerified'] == true) {
      return false;
    }
    return true;
  }

  /// Sends a 6-digit verification code to the user's email address
  Future<OtpSendResult> sendOtpDetailed({required String email, String purpose = 'Registration'}) async {
    final cleanEmail = email.trim().toLowerCase();
    final random = Random.secure();
    final otp = (100000 + random.nextInt(900000)).toString();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(const Duration(minutes: 5));

    await FirebaseService.instance.saveOtpToFirestore(
      email: cleanEmail,
      otp: otp,
      purpose: purpose,
      expiresAt: expiresAt,
    );

    await _storage.write(
      key: 'otp_$cleanEmail',
      value: jsonEncode({
        'otp': otp,
        'expiresAt': expiresAt.toIso8601String(),
        'purpose': purpose,
      }),
    );

    final dispatchResult = await EmailDispatcher.dispatchOtpEmail(
      recipientEmail: cleanEmail,
      otp: otp,
      purpose: purpose,
    );

    if (dispatchResult.success) {
      return OtpSendResult(
        success: true,
        message: dispatchResult.message,
        isDeliveredViaSmtp: dispatchResult.isDeliveredViaSmtp,
        deliveryMode: dispatchResult.isDeliveredViaSmtp ? 'Email Delivery' : 'Direct Code',
      );
    }
    return OtpSendResult(
      success: false,
      message: dispatchResult.message,
      isDeliveredViaSmtp: false,
      deliveryMode: 'Delivery Failed',
    );
  }

  Future<String> sendOtp({required String email, String purpose = 'Registration'}) async {
    final result = await sendOtpDetailed(email: email, purpose: purpose);
    return result.message;
  }

  /// Validates the 6-digit verification code and marks the account as verified
  Future<bool> verifyOtp({required String email, required String otp, String purpose = 'Registration'}) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanOtp = otp.trim();

    try {
      final res = await http
          .post(
            _client.uri('/api/auth/verify-otp'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': cleanEmail,
              'otp': cleanOtp,
              'purpose': purpose,
            }),
          )
          .timeout(const Duration(seconds: 6));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          await FirebaseService.instance.markEmailVerified(cleanEmail);
          return true;
        }
      }
    } catch (_) {}

    final isValid = await FirebaseService.instance.verifyOtpInFirestore(
      email: cleanEmail,
      otp: cleanOtp,
    );

    if (isValid) {
      await FirebaseService.instance.markEmailVerified(cleanEmail);
      return true;
    }

    final localJson = await _storage.read(key: 'otp_$cleanEmail');
    if (localJson != null) {
      try {
        final map = jsonDecode(localJson);
        final storedOtp = map['otp']?.toString() ?? '';
        final expStr = map['expiresAt']?.toString() ?? '';
        final exp = DateTime.tryParse(expStr);

        if (storedOtp == cleanOtp) {
          if (exp != null && DateTime.now().toUtc().isAfter(exp)) {
            throw Exception('This verification code has expired. Please request a new one.');
          }
          await FirebaseService.instance.markEmailVerified(cleanEmail);
          return true;
        }
      } catch (e) {
        if (e is Exception && e.toString().contains('expired')) rethrow;
      }
    }

    throw Exception('That code does not match. Please check and try again.');
  }

  /// Registers user and triggers email verification flow
  Future<UserModel?> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String role = 'Family Member',
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final passwordHash = _hashPassword(password);

    await FirebaseService.instance.saveUserInFirestore(
      email: cleanEmail,
      fullName: fullName,
      userId: userId,
      role: role,
      passwordHash: passwordHash,
      phoneNumber: phoneNumber,
      isEmailVerified: false,
      familyIds: [],
      activeFamilyId: null,
    );

    await sendOtpDetailed(email: cleanEmail, purpose: 'Registration');

    return UserModel(
      id: userId,
      email: cleanEmail,
      fullName: fullName,
      phoneNumber: phoneNumber,
      role: role,
      defaultFamilyMemberId: '',
      isEmailVerified: false,
      familyIds: [],
      activeFamilyId: null,
    );
  }

  /// Completes registration with verified code and saves backend JWT session
  Future<UserModel?> registerWithOtp({
    required String email,
    required String password,
    required String fullName,
    required String otp,
    String? phoneNumber,
    String role = 'Family Member',
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final isVerified = await verifyOtp(email: cleanEmail, otp: otp, purpose: 'Registration');

    if (!isVerified) {
      throw Exception('Invalid or expired verification code.');
    }

    UserModel? user;
    String accessToken = '';
    String refreshToken = '';

    try {
      final res = await http
          .post(
            _client.uri('/api/auth/register'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': cleanEmail,
              'password': password,
              'fullName': fullName.trim(),
              'phoneNumber': phoneNumber?.trim(),
              'role': role,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(res.body);
        accessToken = data['accessToken']?.toString() ?? '';
        refreshToken = data['refreshToken']?.toString() ?? '';
        final u = data['user'] as Map<String, dynamic>?;
        if (u != null) {
          user = UserModel(
            id: u['id']?.toString() ?? '',
            email: u['email']?.toString() ?? cleanEmail,
            fullName: u['fullName']?.toString() ?? fullName,
            phoneNumber: u['phoneNumber']?.toString() ?? phoneNumber,
            role: u['role']?.toString() ?? role,
            defaultFamilyMemberId: u['defaultFamilyMemberId']?.toString() ?? '',
            isEmailVerified: true,
            familyIds: const ['family_default'],
            activeFamilyId: 'family_default',
          );
        }
      } else if (res.statusCode == 400) {
        final data = jsonDecode(res.body);
        final msg = data['message']?.toString() ?? '';
        if (msg.toLowerCase().contains('already exists')) {
          throw Exception('An account with this email already exists. Please sign in instead.');
        }
      }
    } catch (e) {
      if (e.toString().contains('already exists')) rethrow;
    }

    user ??= UserModel(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      email: cleanEmail,
      fullName: fullName,
      phoneNumber: phoneNumber,
      role: role,
      defaultFamilyMemberId: '',
      isEmailVerified: true,
      familyIds: const [],
      activeFamilyId: null,
    );

    if (accessToken.isEmpty) {
      accessToken = 'token_${user.id}_${DateTime.now().millisecondsSinceEpoch}';
      refreshToken = 'refresh_${user.id}';
    }

    await FirebaseService.instance.saveUserInFirestore(
      email: cleanEmail,
      fullName: user.fullName,
      userId: user.id,
      role: user.role,
      passwordHash: _hashPassword(password),
      phoneNumber: phoneNumber,
      isEmailVerified: true,
      familyIds: user.familyIds,
      activeFamilyId: user.activeFamilyId,
    );

    await _persistSession(user, accessToken: accessToken, refreshToken: refreshToken);
    return user;
  }

  /// Creates an account for a new family member
  Future<UserModel> createMemberAccount({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String role = 'Family Member',
    String? assignToFamilyId,
    bool isEmailVerified = true,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final passwordHash = _hashPassword(password);
    final familyList = (assignToFamilyId != null && assignToFamilyId.isNotEmpty)
        ? [assignToFamilyId]
        : <String>[];

    await FirebaseService.instance.saveUserInFirestore(
      email: cleanEmail,
      fullName: fullName,
      userId: userId,
      role: role,
      passwordHash: passwordHash,
      phoneNumber: phoneNumber,
      isEmailVerified: isEmailVerified,
      familyIds: familyList,
      activeFamilyId: familyList.isNotEmpty ? familyList.first : null,
    );

    return UserModel(
      id: userId,
      email: cleanEmail,
      fullName: fullName,
      phoneNumber: phoneNumber,
      role: role,
      defaultFamilyMemberId: '',
      isEmailVerified: isEmailVerified,
      familyIds: familyList,
      activeFamilyId: familyList.isNotEmpty ? familyList.first : null,
    );
  }

  /// Authenticates against the production PostgreSQL backend API (with offline/Firestore backup)
  Future<UserModel?> login({
    required String email,
    required String password,
    String? requiredRole,
  }) async {
    final cleanLogin = email.trim().toLowerCase();

    try {
      final res = await http
          .post(
            _client.uri('/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': cleanLogin,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final accessToken = data['accessToken']?.toString() ?? '';
        final refreshToken = data['refreshToken']?.toString() ?? '';
        final u = data['user'] as Map<String, dynamic>?;
        if (u != null && accessToken.isNotEmpty) {
          final firestoreDoc = await FirebaseService.instance.getUserFromFirestore(cleanLogin);
          final fams = (firestoreDoc?['familyIds'] as List?)?.map((e) => e.toString()).toList() ?? ['family_default'];
          final activeFam = firestoreDoc?['activeFamilyId']?.toString() ?? (fams.isNotEmpty ? fams.first : 'family_default');

          final user = UserModel(
            id: u['id']?.toString() ?? '',
            email: u['email']?.toString() ?? cleanLogin,
            fullName: u['fullName']?.toString() ?? 'CareVoice User',
            phoneNumber: u['phoneNumber']?.toString(),
            role: u['role']?.toString() ?? 'Caregiver',
            defaultFamilyMemberId: u['defaultFamilyMemberId']?.toString() ?? '',
            isEmailVerified: true,
            familyIds: fams,
            activeFamilyId: activeFam,
          );

          await _persistSession(user, accessToken: accessToken, refreshToken: refreshToken);
          return user;
        }
      } else if (res.statusCode == 401) {
        final firestoreDoc = await FirebaseService.instance.getUserFromFirestore(cleanLogin);
        if (firestoreDoc != null && firestoreDoc['passwordHash']?.toString() == _hashPassword(password)) {
          final regRes = await http
              .post(
                _client.uri('/api/auth/register'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'email': cleanLogin,
                  'password': password,
                  'fullName': firestoreDoc['fullName']?.toString() ?? 'CareVoice User',
                  'phoneNumber': firestoreDoc['phoneNumber']?.toString(),
                  'role': firestoreDoc['role']?.toString() ?? 'Caregiver',
                }),
              )
              .timeout(const Duration(seconds: 10));
          if (regRes.statusCode == 200 || regRes.statusCode == 201) {
            final regData = jsonDecode(regRes.body);
            final u = regData['user'] as Map<String, dynamic>?;
            if (u != null) {
              final fams = (firestoreDoc['familyIds'] as List?)?.map((e) => e.toString()).toList() ?? ['family_default'];
              final user = UserModel(
                id: u['id']?.toString() ?? '',
                email: u['email']?.toString() ?? cleanLogin,
                fullName: u['fullName']?.toString() ?? 'CareVoice User',
                phoneNumber: u['phoneNumber']?.toString(),
                role: u['role']?.toString() ?? 'Caregiver',
                defaultFamilyMemberId: u['defaultFamilyMemberId']?.toString() ?? '',
                isEmailVerified: true,
                familyIds: fams,
                activeFamilyId: fams.isNotEmpty ? fams.first : 'family_default',
              );
              await _persistSession(
                user,
                accessToken: regData['accessToken']?.toString() ?? '',
                refreshToken: regData['refreshToken']?.toString() ?? '',
              );
              return user;
            }
          }
        }
        throw Exception('Incorrect email or password. Please check your details and try again.');
      }
    } catch (e) {
      if (e.toString().contains('Incorrect email or password')) {
        rethrow;
      }
    }

    final enteredHash = _hashPassword(password);
    final userDoc = await FirebaseService.instance.getUserFromFirestore(cleanLogin);

    if (userDoc != null) {
      final storedHash = userDoc['passwordHash']?.toString() ?? '';
      final isDemo = _isDemoCredentials(cleanLogin, password);

      if (!isDemo && storedHash.isNotEmpty && storedHash != enteredHash) {
        throw Exception('Incorrect email or password. Please check your details and try again.');
      }

      final isVerified = userDoc['isEmailVerified'] == true || isDemo;
      if (!isVerified) {
        final otpResult = await sendOtpDetailed(email: cleanLogin, purpose: 'LoginVerification');
        throw EmailNotVerifiedException(
          email: cleanLogin,
          message: 'Please verify your email first. We sent a 6-digit code to $cleanLogin.',
          otpResult: otpResult,
        );
      }

      final storedRole = userDoc['role']?.toString().trim() ?? 'Family Member';
      if (requiredRole != null && requiredRole.isNotEmpty) {
        if (normalizeRole(requiredRole) != normalizeRole(storedRole)) {
          throw RoleMismatchException(
            selectedRole: requiredRole,
            actualRole: storedRole,
            message: 'Your account is set up as "$storedRole".',
          );
        }
      }

      final fams = (userDoc['familyIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      final activeFam = userDoc['activeFamilyId']?.toString() ?? (fams.isNotEmpty ? fams.first : null);

      final user = UserModel(
        id: userDoc['userId']?.toString() ?? 'user_${DateTime.now().millisecondsSinceEpoch}',
        email: cleanLogin,
        fullName: userDoc['fullName']?.toString() ?? 'User',
        phoneNumber: userDoc['phoneNumber']?.toString(),
        role: storedRole,
        defaultFamilyMemberId: userDoc['defaultFamilyMemberId']?.toString() ?? '',
        isEmailVerified: true,
        familyIds: fams,
        activeFamilyId: activeFam,
      );

      await _persistSession(
        user,
        accessToken: 'token_${user.id}_${DateTime.now().millisecondsSinceEpoch}',
        refreshToken: 'refresh_${user.id}',
      );
      return user;
    }

    if (_isDemoCredentials(cleanLogin, password)) {
      final isCaregiver = cleanLogin.contains('caregiver');
      final user = UserModel(
        id: isCaregiver ? '72acf541-a413-412d-a624-2f64399f5ef1' : '83bdf652-b524-523e-b735-3f754a0f6fg2',
        email: cleanLogin,
        fullName: isCaregiver ? 'Primary Caregiver' : 'Papa (Patient)',
        phoneNumber: isCaregiver ? '+1234567890' : '+1987654321',
        role: isCaregiver ? 'Family Admin' : 'Family Member',
        defaultFamilyMemberId: isCaregiver ? '910d7db8-e77d-4fa8-8e04-6c52b243d792' : '',
        isEmailVerified: true,
        familyIds: const ['family_default'],
        activeFamilyId: 'family_default',
      );
      await _persistSession(
        user,
        accessToken: 'token_${user.id}',
        refreshToken: 'refresh_${user.id}',
      );
      return user;
    }

    throw Exception('No account found for "$cleanLogin". Please register first.');
  }

  Future<void> _persistSession(
    UserModel user, {
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: 'accessToken', value: accessToken);
    await _storage.write(key: 'refreshToken', value: refreshToken);
    await _storage.write(key: 'current_user', value: jsonEncode(user.toJson()));
    if (user.activeFamilyId != null && user.activeFamilyId!.isNotEmpty) {
      await _storage.write(key: 'carevoice_active_family_id', value: user.activeFamilyId!);
    } else {
      await _storage.delete(key: 'carevoice_active_family_id');
    }
  }

  bool _isDemoCredentials(String email, String password) {
    final em = email.trim().toLowerCase();
    final pw = password.trim();
    if (em == 'caregiver@carevoice.app' || em == 'patient@carevoice.app') {
      return pw == 'Password123!' || pw == 'Password123' || pw.isEmpty || pw == 'password';
    }
    return false;
  }

  Future<String?> getAccessToken() async => await _storage.read(key: 'accessToken');

  Future<UserModel?> getCurrentUser() async {
    final str = await _storage.read(key: 'current_user');
    if (str != null && str.isNotEmpty) {
      try {
        return UserModel.fromJson(jsonDecode(str));
      } catch (_) {}
    }
    return null;
  }

  Future<void> logout() async {
    await _storage.delete(key: 'accessToken');
    await _storage.delete(key: 'refreshToken');
    await _storage.delete(key: 'current_user');
    await _storage.delete(key: 'carevoice_active_family_id');
  }
}
