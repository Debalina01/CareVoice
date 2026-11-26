import 'package:flutter_test/flutter_test.dart';
import 'package:carevoice_app/domain/models.dart';

void main() {
  group('Family Models Serialization Tests', () {
    test('FamilyMemberModel deserializes from JSON with permissions', () {
      final json = {
        'id': 'fm-123',
        'fullName': 'Grandma Mary',
        'relation': 'Grandmother',
        'preferredLanguage': 'en',
        'voicePreference': 'en-US-Standard-B',
        'isSelf': false,
        'canSetReminders': true,
        'canViewLogs': true,
      };

      final model = FamilyMemberModel.fromJson(json);

      expect(model.id, equals('fm-123'));
      expect(model.fullName, equals('Grandma Mary'));
      expect(model.relation, equals('Grandmother'));
      expect(model.isSelf, isFalse);
      expect(model.canSetReminders, isTrue);
      expect(model.canViewLogs, isTrue);
      expect(model.hasLoginCredentials, isFalse);
      expect(model.username, isNull);
    });

    test('FamilyMemberModel deserializes with member login credentials and username', () {
      final json = {
        'id': 'fm-papa',
        'fullName': 'Papa John',
        'relation': 'Parent',
        'preferredLanguage': 'bn',
        'voicePreference': 'bn-IN-Standard-A',
        'isSelf': false,
        'canSetReminders': true,
        'canViewLogs': true,
        'username': 'papa2026',
        'hasLoginCredentials': true,
      };

      final model = FamilyMemberModel.fromJson(json);

      expect(model.id, equals('fm-papa'));
      expect(model.fullName, equals('Papa John'));
      expect(model.relation, equals('Parent'));
      expect(model.preferredLanguage, equals('bn'));
      expect(model.voicePreference, equals('bn-IN-Standard-A'));
      expect(model.hasLoginCredentials, isTrue);
      expect(model.username, equals('papa2026'));
    });

    test('InviteModel deserializes from JSON', () {
      final json = {
        'id': 'inv-456',
        'inviterMemberId': 'fm-self',
        'inviterName': 'Caregiver Jane',
        'invitedEmail': 'recipient@carevoice.app',
        'inviteToken': 'a1b2c3d4e5f6',
        'status': 'Pending',
        'expiresAt': '2026-11-01T00:00:00Z',
      };

      final model = InviteModel.fromJson(json);

      expect(model.id, equals('inv-456'));
      expect(model.inviterName, equals('Caregiver Jane'));
      expect(model.invitedEmail, equals('recipient@carevoice.app'));
      expect(model.inviteToken, equals('a1b2c3d4e5f6'));
      expect(model.status, equals('Pending'));
    });
  });
}
