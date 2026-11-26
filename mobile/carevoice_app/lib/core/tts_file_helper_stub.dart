import 'dart:typed_data';

/// Stub implementation for non-IO platforms (e.g. Web)
Future<String?> writeTempAudioFile(Uint8List bytes, String fileName) async {
  return null;
}
