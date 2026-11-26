import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tests the SMTP connection and authentication credentials
Future<String?> testSmtpConnection({
  required String host,
  required int port,
  required String user,
  required String password,
}) async {
  if (password.trim().isEmpty) {
    return 'Password is empty. Please enter your Gmail App Password or SMTP password.';
  }

  Socket? plainSocket;
  SecureSocket? secureSocket;

  try {
    StreamIterator<String> iterator;

    if (port == 465) {
      secureSocket = await SecureSocket.connect(
        host.trim(),
        port,
        timeout: const Duration(seconds: 8),
        onBadCertificate: (_) => true,
      );
      final stream = secureSocket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
      iterator = StreamIterator(stream);
    } else {
      plainSocket = await Socket.connect(
        host.trim(),
        port,
        timeout: const Duration(seconds: 8),
      );
      var stream = plainSocket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
      iterator = StreamIterator(stream);

      if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        if (!iterator.current.startsWith('220')) {
          return 'Server rejected initial connection: ${iterator.current}';
        }
      }

      plainSocket.write('EHLO carevoice.app\r\n');
      while (await iterator.moveNext().timeout(const Duration(seconds: 4))) {
        final line = iterator.current;
        if (line.startsWith('250 ')) break;
        if (!line.startsWith('250-')) return 'EHLO failed: $line';
      }

      plainSocket.write('STARTTLS\r\n');
      if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        if (!iterator.current.startsWith('220')) {
          return 'STARTTLS failed: ${iterator.current}';
        }
      }

      secureSocket = await SecureSocket.secure(plainSocket, onBadCertificate: (_) => true);
      stream = secureSocket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
      iterator = StreamIterator(stream);
    }

    void send(String command) {
      secureSocket!.write('$command\r\n');
    }

    if (port == 465) {
      if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        if (!iterator.current.startsWith('220')) {
          return 'Server greeting error: ${iterator.current}';
        }
      }
    }

    send('EHLO carevoice.app');
    while (await iterator.moveNext().timeout(const Duration(seconds: 4))) {
      final line = iterator.current;
      if (line.startsWith('250 ')) break;
      if (!line.startsWith('250-')) return 'EHLO rejected: $line';
    }

    send('AUTH LOGIN');
    if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      if (!iterator.current.startsWith('334')) {
        return 'AUTH LOGIN not accepted: ${iterator.current}';
      }
    }

    send(base64.encode(utf8.encode(user.trim())));
    if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      if (!iterator.current.startsWith('334')) {
        return 'Username rejected: ${iterator.current}';
      }
    }

    send(base64.encode(utf8.encode(password.trim().replaceAll(' ', ''))));
    if (await iterator.moveNext().timeout(const Duration(seconds: 6))) {
      if (!iterator.current.startsWith('235')) {
        return 'Authentication failed: ${iterator.current}. Please check your 16-character Google App Password.';
      }
    }

    send('QUIT');
    return null;
  } catch (e) {
    return 'Connection error: ${e.toString().replaceAll('Exception: ', '')}';
  } finally {
    try {
      secureSocket?.destroy();
      plainSocket?.destroy();
    } catch (_) {}
  }
}

/// Native SMTPS email sender using pure dart:io sockets (no external dependencies)
Future<bool> sendEmailSmtp({
  required String recipientEmail,
  required String subject,
  required String htmlBody,
  required String textBody,
}) async {
  const storage = FlutterSecureStorage();
  final smtpHost = (await storage.read(key: 'carevoice_smtp_host')) ?? 'smtp.gmail.com';
  final smtpPortStr = await storage.read(key: 'carevoice_smtp_port');
  final smtpPort = int.tryParse(smtpPortStr ?? '') ?? 465;
  final smtpUser = (await storage.read(key: 'carevoice_smtp_user')) ?? 'anirbanmandal666@gmail.com';
  var smtpPassword = (await storage.read(key: 'carevoice_smtp_password')) ?? '';
  if (smtpPassword.trim().isEmpty) {
    return false;
  }

  smtpPassword = smtpPassword.replaceAll(' ', '').trim();

  Socket? plainSocket;
  SecureSocket? secureSocket;

  try {
    StreamIterator<String> iterator;

    if (smtpPort == 465) {
      secureSocket = await SecureSocket.connect(
        smtpHost.trim(),
        smtpPort,
        timeout: const Duration(seconds: 8),
        onBadCertificate: (_) => true,
      );
      final stream = secureSocket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
      iterator = StreamIterator(stream);

      if (await iterator.moveNext().timeout(const Duration(seconds: 6))) {
        if (!iterator.current.startsWith('220')) {
          throw Exception('Invalid SMTP greeting: ${iterator.current}');
        }
      }
    } else {
      plainSocket = await Socket.connect(
        smtpHost.trim(),
        smtpPort,
        timeout: const Duration(seconds: 8),
      );
      var stream = plainSocket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
      iterator = StreamIterator(stream);

      if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        if (!iterator.current.startsWith('220')) {
          throw Exception('Invalid SMTP greeting: ${iterator.current}');
        }
      }

      plainSocket.write('EHLO carevoice.app\r\n');
      while (await iterator.moveNext().timeout(const Duration(seconds: 4))) {
        final line = iterator.current;
        if (line.startsWith('250 ')) break;
      }

      plainSocket.write('STARTTLS\r\n');
      if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
        if (!iterator.current.startsWith('220')) {
          throw Exception('STARTTLS rejected: ${iterator.current}');
        }
      }

      secureSocket = await SecureSocket.secure(plainSocket, onBadCertificate: (_) => true);
      stream = secureSocket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter());
      iterator = StreamIterator(stream);
    }

    void send(String command) {
      secureSocket!.write('$command\r\n');
    }

    send('EHLO carevoice.app');
    while (await iterator.moveNext().timeout(const Duration(seconds: 4))) {
      final line = iterator.current;
      if (line.startsWith('250 ')) break;
      if (!line.startsWith('250-')) {
        throw Exception('EHLO failed: $line');
      }
    }

    send('AUTH LOGIN');
    if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      final authResp = iterator.current;
      if (!authResp.startsWith('334')) {
        throw Exception('AUTH LOGIN rejected: $authResp');
      }
    }

    send(base64.encode(utf8.encode(smtpUser.trim())));
    if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      final userResp = iterator.current;
      if (!userResp.startsWith('334')) {
        throw Exception('Username rejected: $userResp');
      }
    }

    send(base64.encode(utf8.encode(smtpPassword.trim().replaceAll(' ', ''))));
    if (await iterator.moveNext().timeout(const Duration(seconds: 6))) {
      final passResp = iterator.current;
      if (!passResp.startsWith('235')) {
        throw Exception('Authentication failed: $passResp. Check your 16-character Google App Password.');
      }
    }

    send('MAIL FROM:<${smtpUser.trim()}>');
    if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      final fromResp = iterator.current;
      if (!fromResp.startsWith('250')) {
        throw Exception('MAIL FROM rejected: $fromResp');
      }
    }

    send('RCPT TO:<${recipientEmail.trim()}>');
    if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      final toResp = iterator.current;
      if (!toResp.startsWith('250')) {
        throw Exception('RCPT TO rejected: $toResp');
      }
    }

    send('DATA');
    if (await iterator.moveNext().timeout(const Duration(seconds: 5))) {
      final dataResp = iterator.current;
      if (!dataResp.startsWith('354')) {
        throw Exception('DATA command rejected: $dataResp');
      }
    }

    final boundary = '----=_Part_${DateTime.now().millisecondsSinceEpoch}';
    final envelope = StringBuffer();
    envelope.writeln('From: CareVoice Medicine Reminder <${smtpUser.trim()}>');
    envelope.writeln('To: <${recipientEmail.trim()}>');
    envelope.writeln('Subject: =?utf-8?B?${base64.encode(utf8.encode(subject))}?=');
    envelope.writeln('MIME-Version: 1.0');
    envelope.writeln('Content-Type: multipart/alternative; boundary="$boundary"');
    envelope.writeln('');
    envelope.writeln('--$boundary');
    envelope.writeln('Content-Type: text/plain; charset=utf-8');
    envelope.writeln('Content-Transfer-Encoding: base64');
    envelope.writeln('');
    envelope.writeln(base64.encode(utf8.encode(textBody)));
    envelope.writeln('');
    envelope.writeln('--$boundary');
    envelope.writeln('Content-Type: text/html; charset=utf-8');
    envelope.writeln('Content-Transfer-Encoding: base64');
    envelope.writeln('');
    envelope.writeln(base64.encode(utf8.encode(htmlBody)));
    envelope.writeln('');
    envelope.writeln('--$boundary--');
    envelope.writeln('.');

    secureSocket.write(envelope.toString());

    if (await iterator.moveNext().timeout(const Duration(seconds: 8))) {
      final finishResp = iterator.current;
      if (!finishResp.startsWith('250')) {
        throw Exception('Dispatch rejected: $finishResp');
      }
    }

    send('QUIT');
    return true;
  } catch (_) {
    return false;
  } finally {
    try {
      secureSocket?.destroy();
      plainSocket?.destroy();
    } catch (_) {}
  }
}
