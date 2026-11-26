import 'dart:typed_data';
import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart';

class FileSaver {
  static Future<String?> saveAndOpenFile({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    bool openAfterSave = false,
  }) {
    return saveAndOpenFileImpl(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
      openAfterSave: openAfterSave,
    );
  }
}
