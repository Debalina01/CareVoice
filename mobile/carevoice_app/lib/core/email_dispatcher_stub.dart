/// Stub for non-IO platforms (e.g. Web)
Future<bool> sendEmailSmtp({
  required String recipientEmail,
  required String subject,
  required String htmlBody,
  required String textBody,
}) async {
  return false;
}

Future<String?> testSmtpConnection({
  required String host,
  required int port,
  required String user,
  required String password,
}) async {
  return 'SMTP socket not supported on this platform';
}
