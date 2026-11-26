import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

Future<String?> saveAndOpenFileImpl({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  bool openAfterSave = false,
}) async {
  final blobParts = <JSAny>[bytes.toJS].toJS;
  final blob = web.Blob(blobParts, web.BlobPropertyBag(type: mimeType));
  final blobUrl = web.URL.createObjectURL(blob);

  if (openAfterSave) {
    web.window.open(blobUrl, '_blank');
    Future.delayed(const Duration(seconds: 15), () {
      web.URL.revokeObjectURL(blobUrl);
    });
    return fileName;
  }

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = blobUrl;
  anchor.download = fileName;
  anchor.style.display = 'none';
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();

  Future.delayed(const Duration(seconds: 5), () {
    web.URL.revokeObjectURL(blobUrl);
  });
  return fileName;
}
