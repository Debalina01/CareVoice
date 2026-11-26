import 'package:flutter_test/flutter_test.dart';
import 'package:carevoice_app/domain/models.dart';

void main() {
  group('Medicine & Dose Models Tests', () {
    test('MedicineModel deserializes from JSON', () {
      final json = {
        'id': 'med-101',
        'name': 'Atorvastatin 20mg',
        'dosage': '1 Tablet',
        'instructions': 'Take at night',
        'foodRelation': 'WithFood',
      };

      final model = MedicineModel.fromJson(json);

      expect(model.id, equals('med-101'));
      expect(model.name, equals('Atorvastatin 20mg'));
      expect(model.dosage, equals('1 Tablet'));
      expect(model.foodRelation, equals('WithFood'));
    });

    test('DoseSyncModel deserializes from JSON with voice settings', () {
      final json = {
        'scheduleId': 'sched-202',
        'medicineId': 'med-101',
        'medicineName': 'Atorvastatin 20mg',
        'dosage': '1 Tablet',
        'instructions': 'Take at night',
        'foodRelation': 'WithFood',
        'targetMemberId': 'member-303',
        'targetMemberName': 'Grandma Mary',
        'scheduledTimeUtc': '2026-10-24T20:00:00Z',
        'timeOfDay': '20:00',
        'preferredLanguage': 'es',
        'voicePreference': 'es-ES-Standard-A',
      };

      final model = DoseSyncModel.fromJson(json);

      expect(model.scheduleId, equals('sched-202'));
      expect(model.targetMemberName, equals('Grandma Mary'));
      expect(model.timeOfDay, equals('20:00'));
      expect(model.preferredLanguage, equals('es'));
      expect(model.voicePreference, equals('es-ES-Standard-A'));
    });

    test('DoseHistoryModel deserializes from JSON with status', () {
      final json = {
        'logId': 'log-404',
        'clientLogId': 'cl-505',
        'scheduleId': 'sched-202',
        'medicineName': 'Atorvastatin 20mg',
        'dosage': '1 Tablet',
        'targetMemberId': 'member-303',
        'targetMemberName': 'Grandma Mary',
        'scheduledTime': '2026-10-24T20:00:00Z',
        'actionTime': '2026-10-24T20:05:00Z',
        'status': 'Taken',
      };

      final model = DoseHistoryModel.fromJson(json);

      expect(model.status, equals('Taken'));
      expect(model.clientLogId, equals('cl-505'));
    });
  });
}
