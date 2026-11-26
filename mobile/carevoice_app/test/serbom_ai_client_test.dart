import 'package:flutter_test/flutter_test.dart';
import 'package:carevoice_app/data/serbom_ai_client.dart';

void main() {
  group('SerbomAiClient Local Engine Unit Tests', () {
    test('Detects Bengali text correctly', () {
      expect(SerbomAiClient.containsBengaliCharacters('প্যারাসিটামল ৫০০ মিলিগ্রাম'), isTrue);
      expect(SerbomAiClient.containsBengaliCharacters('Paracetamol 500mg'), isFalse);
    });

    test('Converts Bengali digits to ASCII correctly', () {
      expect(SerbomAiClient.convertBengaliDigitsToAscii('৫০০ মিলিগ্রাম'), '500 মিলিগ্রাম');
      expect(SerbomAiClient.convertBengaliDigitsToAscii('সকাল ৮টা'), 'সকাল 8টা');
      expect(SerbomAiClient.convertBengaliDigitsToAscii('১২৭'), '127');
    });

    test('Detects delete/cancel intents in English and Bengali', () {
      expect(SerbomAiClient.isDeleteIntent('Please delete the schedule for Napa'), isTrue);
      expect(SerbomAiClient.isDeleteIntent('বাতিল করুন নাপা ওষুধের সময়সূচি'), isTrue);
      expect(SerbomAiClient.isDeleteIntent('নাপা মুছে ফেলুন'), isTrue);
      expect(SerbomAiClient.isDeleteIntent('Add Napa 500mg at 8am'), isFalse);
    });

    test('Detects query schedule intents in English and Bengali', () {
      expect(SerbomAiClient.isQueryIntent('What medicines do I have today?'), isTrue);
      expect(SerbomAiClient.isQueryIntent('আজকে আমার কি ওষুধ আছে?'), isTrue);
      expect(SerbomAiClient.isQueryIntent('show schedule'), isTrue);
      expect(SerbomAiClient.isQueryIntent('তালিকা দেখাও'), isTrue);
    });

    test('Identifies food relation text accurately', () {
      expect(SerbomAiClient.getFoodRelationText('BeforeFood', false), 'Before Food');
      expect(SerbomAiClient.getFoodRelationText('BeforeFood', true), 'খাওয়ার আগে');
      expect(SerbomAiClient.getFoodRelationText('AfterFood', false), 'After Food');
      expect(SerbomAiClient.getFoodRelationText('AfterFood', true), 'খাওয়ার পরে');
      expect(SerbomAiClient.getFoodRelationText('WithFood', false), 'With Food');
      expect(SerbomAiClient.getFoodRelationText('WithFood', true), 'খাবারের সাথে');
    });

    test('Detects family relations and stop words correctly', () {
      expect(SerbomAiClient.isFamilyRelationWord('Papa'), isTrue);
      expect(SerbomAiClient.isFamilyRelationWord('বাবা'), isTrue);
      expect(SerbomAiClient.isFamilyRelationWord('মা'), isTrue);
      expect(SerbomAiClient.isFamilyRelationWord('Metformin'), isFalse);

      expect(SerbomAiClient.isStopWord('medicine'), isTrue);
      expect(SerbomAiClient.isStopWord('ওষুধ'), isTrue);
      expect(SerbomAiClient.isStopWord('Napa'), isFalse);
    });
  });
}
