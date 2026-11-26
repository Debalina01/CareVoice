import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'constants.dart';
import 'email_dispatcher_stub.dart'
    if (dart.library.io) 'email_dispatcher_io.dart';

class EmailDispatchResult {
  final bool success;
  final String message;
  final bool isDeliveredViaSmtp;

  EmailDispatchResult({
    required this.success,
    required this.message,
    this.isDeliveredViaSmtp = true,
  });
}

class EmailDispatcher {
  /// Tests SMTP connection with provided or saved credentials
  static Future<String?> testConnection({
    required String host,
    required int port,
    required String user,
    required String password,
  }) async {
    return testSmtpConnection(
      host: host,
      port: port,
      user: user,
      password: password,
    );
  }

  /// Dispatches an OTP verification email via the backend API or configured SMTP relay.
  static Future<EmailDispatchResult> dispatchOtpEmail({
    required String recipientEmail,
    required String otp,
    required String purpose,
  }) async {
    final cleanEmail = recipientEmail.trim().toLowerCase();
    final subject = 'CareVoice Verification Code: $otp';

    final textBody = '''
Hello,

Your verification code for $purpose in CareVoice is: $otp

This code will expire in 10 minutes.
Please enter this code into the CareVoice app to verify your email.

If you did not request this verification, please ignore this email.

Best regards,
CareVoice Family Medicine Reminder Team
Sender: anirbanmandal666@gmail.com
''';

    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>CareVoice Verification Code</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #F8F9FA; margin: 0; padding: 30px;">
  <div style="max-width: 520px; margin: 0 auto; background-color: #FFFFFF; border-radius: 14px; padding: 32px; box-shadow: 0 4px 16px rgba(0,0,0,0.06); border: 1px solid #EAEAEA;">
    <div style="text-align: center; margin-bottom: 24px;">
      <h2 style="color: #2D5A27; margin: 0; font-size: 24px; font-weight: 800;">CareVoice</h2>
      <p style="color: #6C757D; margin-top: 4px; font-size: 13px;">Family Medicine Reminder & Care</p>
    </div>
    <div style="border-top: 1px solid #ECECEC; padding-top: 20px;">
      <p style="color: #333333; font-size: 15px; line-height: 1.5;">Hello,</p>
      <p style="color: #555555; font-size: 14px; line-height: 1.5;">
        You requested an email verification code for <strong>$purpose</strong> in CareVoice. Please use the one-time verification code below:
      </p>
      <div style="background-color: #F0F7EE; border: 1px dashed #7AA975; border-radius: 10px; padding: 18px; text-align: center; margin: 24px 0;">
        <span style="font-size: 32px; font-weight: 900; letter-spacing: 8px; color: #1E4620; font-family: monospace;">$otp</span>
      </div>
      <p style="color: #777777; font-size: 12.5px; line-height: 1.4;">
        ⏱️ <strong>This code will expire in 10 minutes.</strong><br>
        🔒 For your security, never share this code with anyone.
      </p>
    </div>
    <div style="border-top: 1px solid #ECECEC; margin-top: 28px; padding-top: 16px; text-align: center;">
      <p style="color: #999999; font-size: 11px; margin: 0;">
        CareVoice Family Medicine Reminder • Sent automatically from anirbanmandal666@gmail.com
      </p>
    </div>
  </div>
</body>
</html>
''';

    String lastError = 'Unable to deliver verification email to $cleanEmail. Please check the backend email configuration or network connection.';
    
    await ApiConstants.loadCustomUrl();
    final primaryUrl = ApiConstants.baseUrl;
    final cloudUrl = ApiConstants.productionCloudUrl;

    final candidateUrls = <String>[primaryUrl];
    if (primaryUrl != cloudUrl) {
      candidateUrls.add(cloudUrl);
    }

    for (int i = 0; i < candidateUrls.length; i++) {
      final currentUrl = candidateUrls[i];
      final isLocal = ApiConstants.isLocalOrPrivateHost(Uri.tryParse(currentUrl)?.host);
      final timeoutDuration = isLocal ? const Duration(seconds: 5) : const Duration(seconds: 12);

      try {
        final uri = Uri.parse('$currentUrl/api/auth/send-otp');
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': cleanEmail,
            'purpose': purpose,
            'code': otp,
          }),
        ).timeout(timeoutDuration);

        try {
          final data = jsonDecode(res.body);
          if (res.statusCode == 200 && data['success'] == true) {
            final isSmtp = data['isDeliveredViaSmtp'] == true;
            return EmailDispatchResult(
              success: true,
              message: data['message']?.toString() ?? 'Verification code generated successfully for $cleanEmail.',
              isDeliveredViaSmtp: isSmtp,
            );
          } else if (res.statusCode == 404) {
            lastError = 'Verification service is temporarily unavailable. Please try again in a moment.';
          } else if (data['message'] != null) {
            lastError = data['message'].toString();
          }
        } catch (_) {
          if (res.statusCode == 200) {
            return EmailDispatchResult(
              success: true,
              message: 'Verification code sent to $cleanEmail.',
              isDeliveredViaSmtp: false,
            );
          } else if (res.statusCode == 404) {
            lastError = 'Verification service is temporarily unavailable. Please try again in a moment.';
          }
        }
      } catch (e) {
        if (e is TimeoutException) {
          lastError = 'The request took too long. Please check your internet connection and try again.';
        } else {
          lastError = 'Unable to connect right now. Please check your internet connection and try again.';
        }
      }
    }

    try {
      final smtpDelivered = await sendEmailSmtp(
        recipientEmail: cleanEmail,
        subject: subject,
        htmlBody: htmlBody,
        textBody: textBody,
      );
      if (smtpDelivered) {
        return EmailDispatchResult(
          success: true,
          message: 'Verification code sent successfully to $cleanEmail from anirbanmandal666@gmail.com.',
        );
      }
    } catch (_) {}

    return EmailDispatchResult(
      success: false,
      message: lastError,
    );
  }
}
