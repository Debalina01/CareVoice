import 'dart:io';
import 'dart:typed_data';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<String?> saveAndOpenFileImpl({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  bool openAfterSave = false,
}) async {
  final safeName = p.basename(fileName).replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  Directory? targetDir;

  if (!openAfterSave && Platform.isAndroid) {
    try {
      final downloads = Directory('/storage/emulated/0/Download');
      if (await downloads.exists()) {
        targetDir = downloads;
      }
    } catch (_) {}
  }

  targetDir ??= openAfterSave
      ? await getTemporaryDirectory()
      : await getApplicationDocumentsDirectory();

  final filePath = p.join(targetDir.path, safeName);
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);

  if (openAfterSave) {
    await OpenFilex.open(filePath, type: mimeType);
  }
  return filePath;
}
