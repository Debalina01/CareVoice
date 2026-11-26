import 'package:flutter_test/flutter_test.dart';
import 'package:carevoice_app/domain/models.dart';

void main() {
  group('MedicalDocumentModel Tests', () {
    test('MedicalDocumentModel deserializes and formats file metadata', () {
      final json = {
        'id': 'doc-1',
        'ownerMemberId': 'member-1',
        'ownerMemberName': 'Papa',
        'uploadedByUserId': 'user-1',
        'uploadedByName': 'Primary Caregiver',
        'title': 'Blood Pressure Prescription',
        'category': 'Prescription',
        'notes': 'After breakfast',
        'originalFileName': 'bp_rx.pdf',
        'contentType': 'application/pdf',
        'fileSizeBytes': 204800,
        'createdAt': '2026-11-26T10:00:00Z',
      };

      final doc = MedicalDocumentModel.fromJson(json);

      expect(doc.id, equals('doc-1'));
      expect(doc.ownerMemberName, equals('Papa'));
      expect(doc.title, equals('Blood Pressure Prescription'));
      expect(doc.category, equals('Prescription'));
      expect(doc.isPdf, isTrue);
      expect(doc.isImage, isFalse);
      expect(doc.formattedSize, equals('200.0 KB'));
    });

    test('MedicalDocumentModel detects image MIME types accurately', () {
      final doc = MedicalDocumentModel.fromJson({
        'id': 'doc-2',
        'ownerMemberId': 'member-1',
        'ownerMemberName': 'Self',
        'uploadedByUserId': 'user-1',
        'uploadedByName': 'Primary Caregiver',
        'title': 'Lab Report',
        'category': 'Lab Report',
        'originalFileName': 'lab.png',
        'contentType': 'image/png',
        'fileSizeBytes': 1572864,
        'createdAt': '2026-11-26T10:00:00Z',
      });

      expect(doc.isImage, isTrue);
      expect(doc.isPdf, isFalse);
      expect(doc.formattedSize, equals('1.50 MB'));
    });
  });
}
