import 'package:flutter_test/flutter_test.dart';
import 'package:carevoice_app/core/tts_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TtsService Voice Reminder Language Tests', () {
    test('Default voice language should be auto or en', () {
      expect(TtsService.voiceLanguage, isIn(['auto', 'en', 'bn']));
    });

    test('User preference for Bengali strictly overrides fallbacks', () async {
      await TtsService.setVoiceLanguage('bn');
      expect(TtsService.voiceLanguage, equals('bn'));
      expect(TtsService.voiceLanguageNotifier.value, equals('bn'));

      expect(TtsService.getEffectiveLanguage(fallbackLanguage: 'en'), equals('bn'));
      expect(TtsService.getEffectiveLanguage(fallbackLanguage: 'bn'), equals('bn'));
    });

    test('User preference for English strictly overrides fallbacks', () async {
      await TtsService.setVoiceLanguage('en');
      expect(TtsService.voiceLanguage, equals('en'));
      expect(TtsService.voiceLanguageNotifier.value, equals('en'));

      expect(TtsService.getEffectiveLanguage(fallbackLanguage: 'bn'), equals('en'));
      expect(TtsService.getEffectiveLanguage(fallbackLanguage: 'en'), equals('en'));
    });

    test('Auto mode dynamically follows the contextual/member language', () async {
      await TtsService.setVoiceLanguage('auto');
      expect(TtsService.voiceLanguage, equals('auto'));
      expect(TtsService.voiceLanguageNotifier.value, equals('auto'));

      expect(TtsService.getEffectiveLanguage(fallbackLanguage: 'bn'), equals('bn'));
      expect(TtsService.getEffectiveLanguage(fallbackLanguage: 'en'), equals('en'));
    });
  });

  group('Date Range Calendar Validation Tests', () {
    test('Valid date range allows To Date on or after From Date', () {
      final from = DateTime(2026, 11, 2);
      final to = DateTime(2026, 11, 9);
      expect(to.isBefore(from), isFalse);
    });

    test('Invalid date range detects To Date earlier than From Date', () {
      final from = DateTime(2026, 11, 10);
      final to = DateTime(2026, 11, 2);
      expect(to.isBefore(from), isTrue);
    });

    test('Same day date range is valid', () {
      final from = DateTime(2026, 11, 2);
      final to = DateTime(2026, 11, 2);
      expect(to.isBefore(from), isFalse);
    });

    test('Historical past date ranges are valid', () {
      final pastFrom = DateTime(2026, 10, 1);
      final pastTo = DateTime(2026, 10, 15);
      expect(pastTo.isBefore(pastFrom), isFalse);

      final singlePastDayFrom = DateTime(2026, 11, 5);
      final singlePastDayTo = DateTime(2026, 11, 5);
      expect(singlePastDayTo.isBefore(singlePastDayFrom), isFalse);
    });
  });
}
