import '../core/firebase_service.dart';
import '../core/notification_service.dart';
import '../domain/models.dart';
import 'local_db.dart';

class SerbomAiClient {
  static final SerbomAiClient instance = SerbomAiClient._();
  SerbomAiClient._();

  static final List<String> _knownMedicines = [
    'Paracetamol', 'Aspirin', 'Metformin', 'Amoxicillin', 'Pantoprazole',
    'Omeprazole', 'Atorvastatin', 'Losartan', 'Azithromycin', 'Ciprofloxacin',
    'Cetirizine', 'Ibuprofen', 'Vitamin C', 'Vitamin D', 'Insulin', 'Lisinopril',
    'Dolo', 'Napa', 'Calpol', 'Augmentin', 'Thyronorm', 'Ecosprin', 'Gliclazide',
    'Telmisartan', 'Monas', 'Seclo', 'Maxpro', 'Finix', 'Lipitor', 'Crocin',
    'প্যারাসিটামল', 'মেটফর্মিন', 'অ্যাসপিরিন', 'এমোক্সিসিলিন', 'প্যান্টোপ্রাজল',
    'ওমেপ্রাজল', 'এটোরভাস্ট্যাটিন', 'লোসার্টান', 'সিপ্রোফ্লক্সাসিন', 'সেটিরিজিন', 'আইবুপ্রোফেন',
    'নাপা', 'ডলো', 'মোনাস', 'সেক্লো', 'ম্যাক্সপ্রো'
  ];

  static bool containsBengaliCharacters(String text) {
    return RegExp(r'[\u0980-\u09FF]').hasMatch(text);
  }

  static String convertBengaliDigitsToAscii(String input) {
    const bnDigits = '০১২৩৪৫৬৭৮৯';
    const enDigits = '0123456789';
    var result = input;
    for (int i = 0; i < bnDigits.length; i++) {
      result = result.replaceAll(bnDigits[i], enDigits[i]);
    }
    return result;
  }

  static bool isDeleteIntent(String text) {
    final lower = text.toLowerCase();
    return lower.contains('delete') || lower.contains('remove') || lower.contains('cancel')
        || lower.contains('মুছে') || lower.contains('ডিলিট') || lower.contains('বাতিল') || lower.contains('বন্ধ');
  }

  static bool isQueryIntent(String text) {
    final lower = text.toLowerCase();
    return (lower.contains('what') && (lower.contains('medicine') || lower.contains('schedule') || lower.contains('dose')))
        || lower.contains('show schedule') || lower.contains('list medicine') || lower.contains('list reminder')
        || (lower.contains('ওষুধ') && (lower.contains('কী') || lower.contains('কি') || lower.contains('কখন') || lower.contains('আছে')))
        || lower.contains('সময়সূচি') || lower.contains('সময়সূচি') || lower.contains('তালিকা');
  }

  static bool isFamilyRelationWord(String word) {
    final lower = word.toLowerCase();
    const relations = [
      'papa', 'father', 'dad', 'daddy', 'mom', 'mother', 'mommy', 'parent', 'parents',
      'brother', 'sister', 'bhai', 'bon', 'son', 'daughter', 'child', 'kid',
      'husband', 'wife', 'spouse', 'grandpa', 'grandma', 'baba', 'maa', 'ma',
      'বাবা', 'মা', 'ভাই', 'বোন', 'ছেলে', 'মেয়ে', 'স্বামী', 'স্ত্রী', 'দাদু', 'দিদা'
    ];
    return relations.contains(lower);
  }

  static bool isStopWord(String word) {
    final lower = word.toLowerCase();
    const stops = [
      'medicine', 'pill', 'pills', 'tablet', 'tablets', 'daily', 'twice', 'once',
      'after', 'before', 'meal', 'meals', 'food', 'papa', 'father', 'mom', 'mother',
      'for', 'the', 'give', 'take', 'set', 'reminder', 'reminders', 'schedule', 'please',
      'yes', 'no', 'ok', 'okay', 'জন্য', 'ওষুধ', 'খাবার', 'সকালে', 'রাতে', 'বাবা', 'মা'
    ];
    return stops.contains(lower);
  }

  static String getFoodRelationText(String relation, bool isBengali) {
    switch (relation) {
      case 'BeforeFood':
        return isBengali ? 'খাওয়ার আগে' : 'Before Food';
      case 'AfterFood':
        return isBengali ? 'খাওয়ার পরে' : 'After Food';
      case 'WithFood':
        return isBengali ? 'খাবারের সাথে' : 'With Food';
      default:
        return isBengali ? 'খাবারের কোনো বাধ্যবাধকতা নেই' : 'No Food Relation';
    }
  }

  Future<SerbomAiResponseModel> processCommand({
    required String message,
    String language = 'en',
    String? targetMemberId,
    ExtractedScheduleModel? accumulatedSchedule,
  }) async {
    final rawText = message.trim();
    final isBengali = language.toLowerCase() == 'bn' || containsBengaliCharacters(rawText);

    if (rawText.isEmpty) {
      return SerbomAiResponseModel(
        intent: 'GeneralChat',
        status: 'Incomplete',
        replyMessage: 'Hello! I am Serbom AI, your smart medicine scheduling assistant. How can I help you today?',
        replyMessageBn: 'নমস্কার! আমি সারবম এআই, আপনার স্মার্ট ওষুধ সময়সূচি সহায়ক। আজ আপনাকে কীভাবে সাহায্য করতে পারি?',
        missingFields: [],
      );
    }

    final members = await LocalDatabase.getCachedMembers();
    final primaryMember = members.firstWhere((m) => m.isSelf, orElse: () => members.first);

    if (isDeleteIntent(rawText)) {
      return await _handleDeleteIntent(rawText, isBengali);
    }

    if (isQueryIntent(rawText)) {
      return await _handleQueryIntent(isBengali);
    }

    final extracted = _extractScheduleDetails(
      rawText,
      members,
      targetMemberId,
      primaryMember,
      accumulatedSchedule,
    );

    final missing = <String>[];
    if (extracted.medicineName.trim().isEmpty) missing.add('medicineName');
    if (extracted.dosage.trim().isEmpty) missing.add('dosage');
    if (extracted.timesOfDay.isEmpty) missing.add('timeOfDay');

    if (missing.contains('medicineName')) {
      final isSelf = (extracted.targetMemberId == primaryMember.id) || (extracted.targetMemberName == 'Primary Caregiver');
      final targetDesc = (extracted.targetMemberName != null && !isSelf) ? ' for ${extracted.targetMemberName}' : '';
      final targetDescBn = (extracted.targetMemberName != null && !isSelf) ? ' (${extracted.targetMemberName}-এর জন্য)' : '';

      return SerbomAiResponseModel(
        intent: 'ClarificationNeeded',
        status: 'Incomplete',
        extractedSchedule: extracted,
        missingFields: missing,
        replyMessage: 'I would be happy to schedule medicine$targetDesc. Could you please specify the name of the medicine?',
        replyMessageBn: 'আমি ওষুধের সময়সূচি তৈরি করতে প্রস্তুত$targetDescBn। অনুগ্রহ করে ওষুধের নাম বলুন?',
        followUpQuestion: 'What is the medicine name?',
        followUpQuestionBn: 'ওষুধের নাম কী?',
      );
    }

    if (missing.contains('dosage')) {
      final isSelf = (extracted.targetMemberId == primaryMember.id) || (extracted.targetMemberName == 'Primary Caregiver');
      final targetDesc = (extracted.targetMemberName != null && !isSelf) ? ' for ${extracted.targetMemberName}' : '';
      final targetDescBn = (extracted.targetMemberName != null && !isSelf) ? ' (${extracted.targetMemberName}-এর জন্য)' : '';

      return SerbomAiResponseModel(
        intent: 'ClarificationNeeded',
        status: 'Incomplete',
        extractedSchedule: extracted,
        missingFields: missing,
        replyMessage: "I noted the medicine '${extracted.medicineName}'$targetDesc. What is the prescribed dosage (e.g. 500mg, 1 tablet)?",
        replyMessageBn: "আমি '${extracted.medicineName}' ওষুধটি চিহ্নিত করেছি$targetDescBn। এর নির্ধারিত মাত্রা (dosage) কত? (যেমন: ৫০০ মিলিগ্রাম বা ১টি ট্যাবলেট)",
        followUpQuestion: 'What is the dosage for ${extracted.medicineName}?',
        followUpQuestionBn: '${extracted.medicineName}-এর মাত্রা কত?',
      );
    }

    if (missing.contains('timeOfDay')) {
      final isSelf = (extracted.targetMemberId == primaryMember.id) || (extracted.targetMemberName == 'Primary Caregiver');
      final targetDesc = (extracted.targetMemberName != null && !isSelf) ? ' for ${extracted.targetMemberName}' : '';
      final targetDescBn = (extracted.targetMemberName != null && !isSelf) ? ' (${extracted.targetMemberName}-এর জন্য)' : '';

      return SerbomAiResponseModel(
        intent: 'ClarificationNeeded',
        status: 'Incomplete',
        extractedSchedule: extracted,
        missingFields: missing,
        replyMessage: "At what time(s) should '${extracted.medicineName}' be taken$targetDesc? (e.g. 08:00 AM, twice daily, or morning and night)",
        replyMessageBn: "${extracted.medicineName} কোন সময়ে গ্রহণ করতে হবে$targetDescBn? (যেমন: সকাল ৮টা, দিনে ২ বার, বা সকালে ও রাতে)",
        followUpQuestion: 'What time should ${extracted.medicineName} be taken?',
        followUpQuestionBn: '${extracted.medicineName} কোন সময় নিতে হবে?',
      );
    }

    final targetName = extracted.targetMemberName ?? 'You';
    final foodNote = getFoodRelationText(extracted.foodRelation, isBengali);
    final timesStr = extracted.timesOfDay.join(', ');

    final englishReply = 'I have prepared the medicine schedule for ${extracted.medicineName} (${extracted.dosage}) for $targetName at $timesStr ($foodNote). Please review and confirm before saving.';
    final bengaliReply = '$targetName-এর জন্য ${extracted.medicineName} (${extracted.dosage}) সময়সূচি প্রস্তুত করা হয়েছে: সময় $timesStr ($foodNote)। সংরক্ষণের আগে অনুগ্রহ করে নিশ্চিত করুন।';

    return SerbomAiResponseModel(
      intent: 'CreateSchedule',
      status: 'ReadyForConfirmation',
      replyMessage: englishReply,
      replyMessageBn: bengaliReply,
      extractedSchedule: extracted,
      missingFields: [],
    );
  }

  Future<SerbomAiResponseModel> _handleDeleteIntent(String text, bool isBengali) async {
    final clean = text.replaceAll(RegExp(r'\b(delete|remove|cancel|schedule|for|the|medicine|মুছে|ফেলুন|ডিলিট|করুন|বাতিল|ওষুধ)\b', caseSensitive: false), ' ').trim();
    final medName = clean.isEmpty ? 'medicine' : clean;

    final schedules = await LocalDatabase.getCachedSchedules();
    final matching = schedules.where((s) => s.medicineName.toLowerCase().contains(medName.toLowerCase())).toList();

    for (var s in matching) {
      await LocalDatabase.deleteCachedSchedule(s.id);
      NotificationService.instance.cancelSchedule(s.id.hashCode.abs() % 1000000);
    }

    if (matching.isNotEmpty) {
      return SerbomAiResponseModel(
        intent: 'DeleteSchedule',
        status: 'Executed',
        replyMessage: "Successfully deleted the schedule for '$medName'.",
        replyMessageBn: "'$medName'-এর সময়সূচি সফলভাবে মুছে ফেলা হয়েছে।",
        missingFields: [],
      );
    }

    return SerbomAiResponseModel(
      intent: 'DeleteSchedule',
      status: 'Error',
      replyMessage: "Could not find any active schedule for '$medName' to delete.",
      replyMessageBn: "মুছে ফেলার জন্য '$medName'-এর কোনো সক্রিয় সময়সূচি পাওয়া যায়নি।",
      missingFields: [],
    );
  }

  Future<SerbomAiResponseModel> _handleQueryIntent(bool isBengali) async {
    final schedules = await LocalDatabase.getCachedSchedules();
    if (schedules.isEmpty) {
      return SerbomAiResponseModel(
        intent: 'QuerySchedule',
        status: 'Executed',
        replyMessage: 'There are currently no active medicine schedules.',
        replyMessageBn: 'বর্তমানে কোনো সক্রিয় ওষুধের সময়সূচি নেই।',
        missingFields: [],
      );
    }

    final lines = schedules.map((s) => '- ${s.medicineName} (${s.dosage}) at ${s.timeOfDay}').join('\n');
    return SerbomAiResponseModel(
      intent: 'QuerySchedule',
      status: 'Executed',
      replyMessage: 'Here are your active schedules:\n$lines',
      replyMessageBn: 'আপনার সক্রিয় সময়সূচিসমূহ:\n$lines',
      missingFields: [],
    );
  }

  ExtractedScheduleModel _extractScheduleDetails(
    String text,
    List<FamilyMemberModel> members,
    String? explicitTargetMemberId,
    FamilyMemberModel primaryMember,
    ExtractedScheduleModel? accumulated,
  ) {
    final result = ExtractedScheduleModel(
      medicineName: accumulated?.medicineName ?? '',
      dosage: accumulated?.dosage ?? '',
      foodRelation: accumulated?.foodRelation ?? 'NoRelation',
      instructions: accumulated?.instructions,
      timesOfDay: accumulated?.timesOfDay != null ? List<String>.from(accumulated!.timesOfDay) : [],
      daysOfWeekMask: accumulated?.daysOfWeekMask ?? 127,
      durationDays: accumulated?.durationDays ?? 30,
      targetMemberId: accumulated?.targetMemberId,
      targetMemberName: accumulated?.targetMemberName,
    );

    final textLower = text.toLowerCase();
    final isBengali = containsBengaliCharacters(text);

    FamilyMemberModel? matchedMember;
    for (var member in members) {
      final name = member.fullName.toLowerCase();
      final rel = member.relation.toLowerCase();

      if (RegExp('\\b${RegExp.escape(name)}\\b').hasMatch(textLower)) {
        matchedMember = member;
        break;
      }
      if (rel == 'parent' && RegExp(r'\b(papa|father|dad|baba|বাবা|ma|maa|mom|mother|মা)\b').hasMatch(textLower)) {
        matchedMember = member;
        break;
      }
      if (rel == 'spouse' && RegExp(r'\b(husband|wife|spouse|বউ|স্ত্রী|স্বামী)\b').hasMatch(textLower)) {
        matchedMember = member;
        break;
      }
      if (rel == 'child' && RegExp(r'\b(son|daughter|child|kid|ছেলে|মেয়ে|সন্তান)\b').hasMatch(textLower)) {
        matchedMember = member;
        break;
      }
      if (rel == 'sibling' && RegExp(r'\b(brother|sister|bhai|bon|ভাই|বোন)\b').hasMatch(textLower)) {
        matchedMember = member;
        break;
      }
      if (member.isSelf && RegExp(r'\b(for me|myself|i need|my medicine|আমার জন্য|আমাকে)\b').hasMatch(textLower)) {
        matchedMember = member;
        break;
      }
    }

    if (matchedMember == null && accumulated?.targetMemberId != null) {
      matchedMember = members.firstWhere((m) => m.id == accumulated!.targetMemberId, orElse: () => primaryMember);
    }
    if (matchedMember == null && explicitTargetMemberId != null) {
      matchedMember = members.firstWhere((m) => m.id == explicitTargetMemberId, orElse: () => primaryMember);
    }
    matchedMember ??= primaryMember;

    result.targetMemberId = matchedMember.id;
    result.targetMemberName = matchedMember.fullName;

    final doseMatchEn = RegExp(r'\b(\d+(?:\.\d+)?\s*(?:mg|ml|g|mcg|tablets?|pills?|capsules?|drops?|puffs?))\b', caseSensitive: false).firstMatch(text);
    final doseMatchBn = RegExp(r'([\d০-৯]+(?:\.[\d০-৯]+)?\s*(?:মিলিগ্রাম|মিলি|গ্রাম|ট্যাবলেট|ক্যাপসুল|চামচ|ড্রপ))').firstMatch(text);

    if (doseMatchEn != null) {
      result.dosage = doseMatchEn.group(1)!.trim();
    } else if (doseMatchBn != null) {
      result.dosage = convertBengaliDigitsToAscii(doseMatchBn.group(1)!.trim());
    } else if (accumulated?.dosage.isNotEmpty ?? false) {
      result.dosage = accumulated!.dosage;
    }

    if (textLower.contains('before food') || textLower.contains('before meal') || textLower.contains('before breakfast')
        || textLower.contains('empty stomach') || textLower.contains('খাওয়ার আগে') || textLower.contains('খাবার আগে')
        || textLower.contains('খালি পেটে')) {
      result.foodRelation = 'BeforeFood';
      result.instructions = isBengali ? 'খাওয়ার আগে গ্রহণ করুন' : 'Take before meal';
    } else if (textLower.contains('after food') || textLower.contains('after meal') || textLower.contains('after meals')
        || textLower.contains('খাওয়ার পর') || textLower.contains('খাওয়ার পরে') || textLower.contains('খাবার পর')
        || textLower.contains('খাবার পরে')) {
      result.foodRelation = 'AfterFood';
      result.instructions = isBengali ? 'খাওয়ার পরে গ্রহণ করুন' : 'Take after meal';
    } else if (textLower.contains('with food') || textLower.contains('with meal') || textLower.contains('খাবারের সাথে')) {
      result.foodRelation = 'WithFood';
      result.instructions = isBengali ? 'খাবারের সাথে গ্রহণ করুন' : 'Take with food';
    } else if (accumulated != null && accumulated.foodRelation != 'NoRelation') {
      result.foodRelation = accumulated.foodRelation;
      result.instructions = accumulated.instructions;
    } else {
      result.foodRelation = 'NoRelation';
      result.instructions = isBengali ? 'পানির সাথে গ্রহণ করুন' : 'Take with water';
    }

    final extractedTimes = <String>[];

    final timeMatches = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false).allMatches(text);
    for (final tm in timeMatches) {
      var h = int.parse(tm.group(1)!);
      final m = tm.group(2) != null ? int.parse(tm.group(2)!) : 0;
      final ampm = tm.group(3)!.toLowerCase();
      if (ampm == 'pm' && h < 12) h += 12;
      if (ampm == 'am' && h == 12) h = 0;
      extractedTimes.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
    }

    final time24Matches = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').allMatches(text);
    for (final tm in time24Matches) {
      final t = '${int.parse(tm.group(1)!).toString().padLeft(2, '0')}:${int.parse(tm.group(2)!).toString().padLeft(2, '0')}';
      if (!extractedTimes.contains(t)) extractedTimes.add(t);
    }

    final bnTimeMatches = RegExp(r'(সকাল|দুপুর|সন্ধ্যা|রাত)\s*([\d০-৯]+)(?::([\d০-৯]+))?\s*টা').allMatches(text);
    for (final btm in bnTimeMatches) {
      final period = btm.group(1)!;
      var h = int.parse(convertBengaliDigitsToAscii(btm.group(2)!));
      final m = btm.group(3) != null ? int.parse(convertBengaliDigitsToAscii(btm.group(3)!)) : 0;
      if ((period == 'রাত' || period == 'সন্ধ্যা') && h < 12) h += 12;
      if (period == 'দুপুর' && h < 12 && h >= 1) h += 12;
      extractedTimes.add('${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}');
    }

    if (extractedTimes.isEmpty) {
      if (textLower.contains('twice') || textLower.contains('২ বার') || textLower.contains('দুবার') || textLower.contains('সকালে ও রাতে')) {
        extractedTimes.addAll(['08:00', '20:00']);
      } else if (textLower.contains('thrice') || textLower.contains('৩ বার') || textLower.contains('তিনবার')) {
        extractedTimes.addAll(['08:00', '14:00', '20:00']);
      } else if (textLower.contains('morning') || textLower.contains('সকালে')) {
        extractedTimes.add('08:00');
      } else if (textLower.contains('night') || textLower.contains('রাতে')) {
        extractedTimes.add('21:00');
      } else if (textLower.contains('once') || textLower.contains('১ বার') || textLower.contains('একবার')) {
        extractedTimes.add('09:00');
      }
    }

    if (extractedTimes.isNotEmpty) {
      result.timesOfDay = extractedTimes.toSet().toList()..sort();
    } else if (accumulated?.timesOfDay.isNotEmpty ?? false) {
      result.timesOfDay = List<String>.from(accumulated!.timesOfDay);
    }

    final durMatchEn = RegExp(r'\b(?:for\s+)?(\d+)\s*(days?|weeks?|months?)\b', caseSensitive: false).firstMatch(text);
    final durMatchBn = RegExp(r'([\d০-৯]+)\s*(?:দিনের?|সপ্তাহের?|মাসের?)\s*(?:জন্য)?').firstMatch(text);

    int durationDays = 30;
    if (durMatchEn != null) {
      final count = int.parse(durMatchEn.group(1)!);
      final unit = durMatchEn.group(2)!.toLowerCase();
      durationDays = unit.startsWith('week') ? count * 7 : unit.startsWith('month') ? count * 30 : count;
      result.durationDays = durationDays;
    } else if (durMatchBn != null) {
      final count = int.parse(convertBengaliDigitsToAscii(durMatchBn.group(1)!));
      durationDays = durMatchBn.group(0)!.contains('সপ্তাহ') ? count * 7 : durMatchBn.group(0)!.contains('মাস') ? count * 30 : count;
      result.durationDays = durationDays;
    } else if (accumulated?.durationDays != null) {
      result.durationDays = accumulated!.durationDays;
      durationDays = accumulated.durationDays!;
    } else {
      result.durationDays = 30;
    }

    result.startDate = DateTime.now();
    result.endDate = DateTime.now().add(Duration(days: durationDays));

    final extractedMed = _extractMedicineName(text, result.dosage, accumulated?.medicineName);
    if (extractedMed.isNotEmpty) {
      result.medicineName = extractedMed;
    } else if (accumulated?.medicineName.isNotEmpty ?? false) {
      result.medicineName = accumulated!.medicineName;
    }

    return result;
  }

  static String _extractMedicineName(String text, String knownDosage, String? existingMedicineName) {
    for (var med in _knownMedicines) {
      if (RegExp('\\b${RegExp.escape(med)}\\b', caseSensitive: false).hasMatch(text)) {
        return med;
      }
    }

    if (knownDosage.isNotEmpty) {
      final matchBefore = RegExp('([A-Za-z\u0980-\u09FF]{3,25})\\s+${RegExp.escape(knownDosage)}', caseSensitive: false).firstMatch(text);
      if (matchBefore != null) {
        final candidate = matchBefore.group(1)!.trim();
        if (!isStopWord(candidate) && !isFamilyRelationWord(candidate)) return candidate;
      }
    }

    final actionMatch = RegExp(r'\b(?:take|add|schedule|prescribe|give|ওষুধ|নিন|দিন)\s+([A-Za-z\u0980-\u09FF]{3,25})', caseSensitive: false).firstMatch(text);
    if (actionMatch != null) {
      final candidate = actionMatch.group(1)!.trim();
      if (!isStopWord(candidate) && !isFamilyRelationWord(candidate)) return candidate;
    }

    final suffixMatch = RegExp(r'\b([A-Za-z]{3,20}(?:cillin|mycin|statin|olol|pril|sartan|zole|pam|pine|ide|ine|tin|one|fen|vir|mab))\b', caseSensitive: false).firstMatch(text);
    if (suffixMatch != null) {
      final candidate = suffixMatch.group(1)!.trim();
      if (!isStopWord(candidate) && !isFamilyRelationWord(candidate)) return candidate;
    }

    if (existingMedicineName != null && existingMedicineName.isNotEmpty) {
      return existingMedicineName;
    }

    final cleaned = text.replaceAll(RegExp(r"\b(the medicine is|its|it's|medicine|named|called|ওষুধের নাম|হলো|নাম|হল)\b", caseSensitive: false), ' ').trim();
    final words = cleaned.split(RegExp(r'[\s,.]')).where((w) => w.isNotEmpty).toList();
    if (words.isNotEmpty && words.length <= 3) {
      final candidate = words.join(' ');
      if (!RegExp(r'\d').hasMatch(candidate)
          && !RegExp(r'(mg|ml|mcg|tablet|pill|capsule|drop|am|pm|morning|night|daily|twice|once|food|meal|breakfast|lunch|dinner|after|before|with|সকাল|রাত|খাবার|নাস্তা)', caseSensitive: false).hasMatch(candidate)
          && !isStopWord(candidate)
          && !isFamilyRelationWord(candidate)
          && candidate.length >= 3) {
        return candidate;
      }
    }

    return '';
  }

  Future<Map<String, dynamic>> confirmSchedule(ExtractedScheduleModel schedule) async {
    final medId = 'med_${DateTime.now().millisecondsSinceEpoch}';
    final targetId = schedule.targetMemberId ?? '910d7db8-e77d-4fa8-8e04-6c52b243d792';
    final targetName = schedule.targetMemberName ?? 'Primary Caregiver';

    final medicine = MedicineModel(
      id: medId,
      name: schedule.medicineName,
      dosage: schedule.dosage,
      instructions: schedule.instructions,
      foodRelation: schedule.foodRelation,
      ownerMemberId: targetId,
      ownerMemberName: targetName,
      startDate: schedule.startDate ?? DateTime.now(),
      endDate: schedule.endDate,
    );
    await LocalDatabase.addCachedMedicine(medicine);

    final scheduleIds = <String>[];
    final times = schedule.timesOfDay.isNotEmpty ? schedule.timesOfDay : ['08:00'];

    for (int i = 0; i < times.length; i++) {
      final timeStr = times[i].length == 5 ? '${times[i]}:00' : times[i];
      final schedId = 'sched_${DateTime.now().millisecondsSinceEpoch}_$i';

      final sched = MedicineScheduleModel(
        id: schedId,
        medicineId: medId,
        medicineName: schedule.medicineName,
        dosage: schedule.dosage,
        targetMemberId: targetId,
        timeOfDay: timeStr,
        daysOfWeekMask: schedule.daysOfWeekMask > 0 ? schedule.daysOfWeekMask : 127,
      );

      await LocalDatabase.addCachedSchedule(sched);
      scheduleIds.add(schedId);

      final timeParts = timeStr.split(':');
      final hour = int.tryParse(timeParts[0]) ?? 8;
      final minute = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
      final isBn = containsBengaliCharacters(schedule.medicineName);

      NotificationService.instance.scheduleMedicineAlarm(
        id: schedId.hashCode.abs() % 1000000,
        title: isBn
            ? '💊 ওষুধ স্মরণসূচী: ${schedule.medicineName} (${schedule.dosage})'
            : '💊 Medicine Reminder: ${schedule.medicineName} (${schedule.dosage})',
        body: isBn
            ? '$targetName-এর জন্য ${schedule.medicineName} খাওয়ার সময় হয়েছে। গ্রহণের পর Taken এ চাপুন।'
            : 'Time for $targetName to take ${schedule.medicineName}. Tap Taken or Not Taken.',
        scheduleId: schedId,
        hour: hour,
        minute: minute,
        medicineName: schedule.medicineName,
        dosage: schedule.dosage,
        targetMemberName: targetName,
        preferredLanguage: isBn ? 'bn' : 'en',
      );

      try {
        await FirebaseService.instance.syncScheduleToFirestore(
          familyId: targetId,
          scheduleId: schedId,
          medicineId: medId,
          medicineName: schedule.medicineName,
          dosage: schedule.dosage,
          timeOfDay: timeStr,
          targetMemberName: targetName,
          instructions: schedule.instructions,
          foodRelation: schedule.foodRelation,
        );
      } catch (_) {}
    }

    return {
      'medicineId': medId,
      'scheduleIds': scheduleIds,
      'message': 'Schedule for ${schedule.medicineName} confirmed and activated with ${scheduleIds.length} reminder(s).',
      'messageBn': '${schedule.medicineName}-এর সময়সূচি নিশ্চিত করা হয়েছে এবং ${scheduleIds.length}টি রিমাইন্ডার সক্রিয় হয়েছে।',
    };
  }
}
