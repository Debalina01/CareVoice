import 'dart:io';
import 'dart:typed_data';

/// Native implementation for Android, iOS, Windows, macOS, Linux
Future<String?> writeTempAudioFile(Uint8List bytes, String fileName) async {
  try {
    final tempDir = Directory.systemTemp;
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  } catch (_) {
    return null;
  }
}
