import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'localization.dart';
import 'tts_audio_player.dart';
import 'tts_file_helper.dart';

class TtsService {
  static final FlutterTts _flutterTts = FlutterTts();
  static final AudioPlayer _audioPlayer = AudioPlayer();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyVoiceLanguage = 'carevoice_voice_reminder_language';
  static const String _keyVoiceReminderEnabled = 'carevoice_voice_reminder_enabled';

  static bool _isInitialized = false;
  static String _savedVoiceLanguage = 'auto';
  static bool _isVoiceReminderEnabled = true;

  /// Supported Indian Languages map
  static const Map<String, String> supportedIndianLanguages = {
    'auto': 'Auto (Follows member profile / সিস্টেম)',
    'en': 'English (Indian / International)',
    'bn': 'Bengali / বাংলা',
    'hi': 'Hindi / हिन्दी',
    'ta': 'Tamil / தமிழ்',
    'te': 'Telugu / తెలుగు',
    'kn': 'Kannada / ಕನ್ನಡ',
    'ml': 'Malayalam / മലയാളം',
    'mr': 'Marathi / मराठी',
    'gu': 'Gujarati / ગુજરાતી',
    'pa': 'Punjabi / ਪੰਜਾਬੀ',
    'or': 'Odia / ଓଡ଼ିଆ',
  };

  /// Reactive notifier for global voice reminder ON/OFF state
  static final ValueNotifier<bool> voiceReminderEnabledNotifier = ValueNotifier<bool>(true);

  /// Reactive notifier for widgets listening to voice language changes
  static final ValueNotifier<String> voiceLanguageNotifier = ValueNotifier<String>('auto');

  /// Reactive notifier indicating if any voice alert is currently playing
  static final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);

  static bool get isVoiceReminderEnabled => _isVoiceReminderEnabled;
  static String get voiceLanguage => _savedVoiceLanguage;
  static bool get isPlaying => isPlayingNotifier.value;

  /// Toggles and persists global voice reminders ON/OFF
  static Future<void> setVoiceReminderEnabled(bool enabled) async {
    _isVoiceReminderEnabled = enabled;
    voiceReminderEnabledNotifier.value = enabled;
    try {
      await _storage.write(key: _keyVoiceReminderEnabled, value: enabled ? '1' : '0');
    } catch (_) {}
  }

  static Future<void> init() async {
    if (_isInitialized) return;
    try {
      final stored = await _storage.read(key: _keyVoiceLanguage);
      if (stored != null && (supportedIndianLanguages.containsKey(stored) || stored == 'auto')) {
        _savedVoiceLanguage = stored;
        voiceLanguageNotifier.value = stored;
      }
      if (!kIsWeb) {
        if (defaultTargetPlatform == TargetPlatform.android) {
          try {
            final dynamic engines = await _flutterTts.getEngines;
            if (engines is List && engines.contains('com.google.android.tts')) {
              await _flutterTts.setEngine('com.google.android.tts');
            }
          } catch (_) {}
        }

        await _flutterTts.setSpeechRate(0.48);
        await _flutterTts.setVolume(1.0);
        await _flutterTts.setPitch(1.0);
        await _flutterTts.awaitSpeakCompletion(false);
        await _flutterTts.setQueueMode(0);

        _flutterTts.setStartHandler(() {
          isPlayingNotifier.value = true;
        });
        _flutterTts.setCompletionHandler(() {
          isPlayingNotifier.value = false;
        });
        _flutterTts.setErrorHandler((_) {
          isPlayingNotifier.value = false;
        });
        _flutterTts.setCancelHandler(() {
          isPlayingNotifier.value = false;
        });

        try {
          await _audioPlayer.setAudioContext(
            AudioContext(
              android: AudioContextAndroid(
                isSpeakerphoneOn: true,
                stayAwake: true,
                contentType: AndroidContentType.speech,
                usageType: AndroidUsageType.media,
                audioFocus: AndroidAudioFocus.gainTransient,
              ),
              iOS: AudioContextIOS(
                category: AVAudioSessionCategory.playback,
                options: {
                  AVAudioSessionOptions.duckOthers,
                  AVAudioSessionOptions.defaultToSpeaker,
                },
              ),
            ),
          );
        } catch (_) {}

        _audioPlayer.onPlayerStateChanged.listen((state) {
          isPlayingNotifier.value = (state == PlayerState.playing);
        });
      }
      await _audioPlayer.setVolume(1.0);

      final storedEnabled = await _storage.read(key: _keyVoiceReminderEnabled);
      if (storedEnabled != null) {
        _isVoiceReminderEnabled = storedEnabled == '1';
        voiceReminderEnabledNotifier.value = _isVoiceReminderEnabled;
      }
    } catch (_) {}
    _isInitialized = true;
  }

  /// Sets and persists the user's preferred voice reminder language.
  static Future<void> setVoiceLanguage(String lang) async {
    if (!supportedIndianLanguages.containsKey(lang) && lang != 'auto') return;
    _savedVoiceLanguage = lang;
    voiceLanguageNotifier.value = lang;
    try {
      await _storage.write(key: _keyVoiceLanguage, value: lang);
    } catch (_) {}
  }

  /// Determines the effective language code to use for speech output.
  static String getEffectiveLanguage({String? fallbackLanguage}) {
    if (_savedVoiceLanguage != 'auto') {
      return _savedVoiceLanguage;
    }

    if (fallbackLanguage != null && fallbackLanguage.trim().isNotEmpty) {
      final clean = fallbackLanguage.trim().toLowerCase();
      if (clean.contains('bengali') || clean.contains('bangla') || clean.contains('বাংলা') || clean.startsWith('bn')) {
        return 'bn';
      }
      if (clean.contains('hindi') || clean.contains('हिन्दी') || clean.contains('हिंदी') || clean.startsWith('hi')) {
        return 'hi';
      }
      if (clean.contains('tamil') || clean.contains('தமிழ்') || clean.startsWith('ta')) {
        return 'ta';
      }
      if (clean.contains('telugu') || clean.contains('తెలుగు') || clean.startsWith('te')) {
        return 'te';
      }
      if (clean.contains('kannada') || clean.startsWith('kn')) {
        return 'kn';
      }
      if (clean.contains('malayalam') || clean.startsWith('ml')) {
        return 'ml';
      }
      if (clean.contains('marathi') || clean.startsWith('mr')) {
        return 'mr';
      }
      if (clean.contains('gujarati') || clean.startsWith('gu')) {
        return 'gu';
      }
      if (clean.contains('punjabi') || clean.startsWith('pa')) {
        return 'pa';
      }
      if (clean.contains('odia') || clean.contains('oriya') || clean.startsWith('or')) {
        return 'or';
      }
      if (clean.contains('english') || clean.startsWith('en')) {
        return 'en';
      }
    }

    if (AppLanguage.instance.isBengali) {
      return 'bn';
    }
    return 'en';
  }

  static String getLocaleTag(String langCode) {
    switch (langCode) {
      case 'bn': return 'bn-IN';
      case 'hi': return 'hi-IN';
      case 'ta': return 'ta-IN';
      case 'te': return 'te-IN';
      case 'kn': return 'kn-IN';
      case 'ml': return 'ml-IN';
      case 'mr': return 'mr-IN';
      case 'gu': return 'gu-IN';
      case 'pa': return 'pa-IN';
      case 'or': return 'or-IN';
      case 'en':
      default: return 'en-US';
    }
  }

  static List<String> _getCandidateLocales(String langCode) {
    switch (langCode) {
      case 'bn': return ['bn-IN', 'bn_IN', 'bn-BD', 'bn_BD', 'bn', 'ben-ind'];
      case 'hi': return ['hi-IN', 'hi_IN', 'hi', 'hin-ind'];
      case 'ta': return ['ta-IN', 'ta_IN', 'ta'];
      case 'te': return ['te-IN', 'te_IN', 'te'];
      case 'kn': return ['kn-IN', 'kn_IN', 'kn'];
      case 'ml': return ['ml-IN', 'ml_IN', 'ml'];
      case 'mr': return ['mr-IN', 'mr_IN', 'mr'];
      case 'gu': return ['gu-IN', 'gu_IN', 'gu'];
      case 'pa': return ['pa-IN', 'pa_IN', 'pa'];
      case 'or': return ['or-IN', 'or_IN', 'or'];
      case 'en':
      default: return ['en-IN', 'en-US', 'en-GB', 'en'];
    }
  }

  /// Master voice utterance player with 3-tier resilient audio fallback
  static Future<void> _playUtterance(
    String message,
    String langCode, {
    String? phoneticFallback,
  }) async {
    await stop();

    if (kIsWeb) {
      speakWebSpeech(message, langCode);
      return;
    }

    try {
      isPlayingNotifier.value = true;

      if (langCode == 'en') {
        try {
          await _flutterTts.setLanguage('en-US');
        } catch (_) {}
        await _flutterTts.setSpeechRate(0.48);
        await _flutterTts.setVolume(1.0);
        await _flutterTts.speak(message);
        return;
      }

      final neuralPlayed = await _playNeuralStream(message, langCode);
      if (neuralPlayed) {
        return;
      }

      final nativePlayed = await _playNativeIfInstalled(message, langCode);
      if (nativePlayed) {
        return;
      }

      await _playPhoneticFallback(message, langCode, phoneticFallback);
    } catch (e) {
      try {
        await _flutterTts.setLanguage('en-US');
        await _flutterTts.speak(message);
      } catch (_) {}
    }
  }

  /// Splits long text into manageable sentences to prevent Google TTS URI length limits
  static List<String> _splitIntoChunks(String text, {int maxChars = 120}) {
    if (text.length <= maxChars) return [text];
    final List<String> result = [];
    final sentences = text.split(RegExp(r'(?<=[।\.!\?\,])\s*'));
    var current = StringBuffer();
    for (final s in sentences) {
      final trimmed = s.trim();
      if (trimmed.isEmpty) continue;
      if (current.length + trimmed.length + 1 > maxChars && current.isNotEmpty) {
        result.add(current.toString().trim());
        current = StringBuffer();
      }
      current.write(trimmed);
      current.write(' ');
    }
    if (current.isNotEmpty) {
      result.add(current.toString().trim());
    }
    return result.isEmpty ? [text] : result;
  }

  /// Fetches audio MP3 bytes for a specific text chunk from Google Neural TTS
  static Future<Uint8List?> _fetchGoogleTtsChunk(String chunk, String langCode) async {
    final encoded = Uri.encodeComponent(chunk);
    final urls = [
      'https://translate.google.com/translate_tts?ie=UTF-8&client=gtx&tl=$langCode&q=$encoded',
      'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=$langCode&q=$encoded',
      'https://translate.googleapis.com/translate_tts?ie=UTF-8&client=gtx&tl=$langCode&q=$encoded',
    ];

    final headers = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Referer': 'https://translate.google.com/',
      'Accept': '*/*',
    };

    for (final url in urls) {
      try {
        final response = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200 && response.bodyBytes.length > 300) {
          return response.bodyBytes;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Tier 1: Streams and plays studio-quality Google Neural TTS audio
  static Future<bool> _playNeuralStream(String message, String langCode) async {
    try {
      final chunks = _splitIntoChunks(message, maxChars: 120);
      final builder = BytesBuilder();

      for (final chunk in chunks) {
        final bytes = await _fetchGoogleTtsChunk(chunk, langCode);
        if (bytes == null || bytes.isEmpty) {
          return false;
        }
        builder.add(bytes);
      }

      final allBytes = builder.toBytes();
      if (allBytes.isEmpty) return false;

      final fileName = 'carevoice_${langCode}_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final filePath = await writeTempAudioFile(allBytes, fileName);

      await _audioPlayer.stop();
      if (filePath != null && filePath.isNotEmpty) {
        await _audioPlayer.play(DeviceFileSource(filePath));
      } else {
        await _audioPlayer.play(BytesSource(allBytes));
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Tier 2: Synthesizes via native OS TTS ONLY if the voice data is confirmed downloaded on the device
  static Future<bool> _playNativeIfInstalled(String message, String langCode) async {
    try {
      final candidates = _getCandidateLocales(langCode);
      bool isConfirmedInstalled = false;
      String? targetLocale;
      Map<String, String>? targetVoice;

      if (defaultTargetPlatform == TargetPlatform.android) {
        for (final candidate in candidates) {
          try {
            final dynamic installed = await _flutterTts.isLanguageInstalled(candidate);
            if (installed == true) {
              isConfirmedInstalled = true;
              targetLocale = candidate;
              break;
            }
          } catch (_) {}
        }

        if (!isConfirmedInstalled) {
          try {
            final dynamic rawVoices = await _flutterTts.getVoices;
            if (rawVoices is List) {
              for (final v in rawVoices) {
                if (v is Map) {
                  final loc = (v['locale'] ?? '').toString().toLowerCase();
                  final name = (v['name'] ?? '').toString();
                  final feat = (v['features'] ?? '').toString();
                  if ((loc.startsWith(langCode.toLowerCase()) || loc.contains(langCode.toLowerCase())) &&
                      !feat.contains('notInstalled')) {
                    isConfirmedInstalled = true;
                    targetLocale = v['locale']?.toString();
                    targetVoice = {'name': name, 'locale': targetLocale ?? 'en-US'};
                    break;
                  }
                }
              }
            }
          } catch (_) {}
        }
      } else {
        for (final candidate in candidates) {
          final dynamic avail = await _flutterTts.isLanguageAvailable(candidate);
          if (avail == true || avail == 1) {
            isConfirmedInstalled = true;
            targetLocale = candidate;
            break;
          }
        }
      }

      if (!isConfirmedInstalled || targetLocale == null) {
        return false;
      }

      await _flutterTts.stop();
      if (targetVoice != null) {
        try {
          await _flutterTts.setVoice(targetVoice);
        } catch (_) {}
      } else {
        await _flutterTts.setLanguage(targetLocale);
      }
      await _flutterTts.setSpeechRate(0.48);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      final dynamic res = await _flutterTts.speak(message);
      return res == 1 || res == true || res == 0;
    } catch (e) {
      return false;
    }
  }

  /// Tier 3: Synthesizes transliterated Indian phonetics via English TTS (100% offline guaranteed)
  static Future<void> _playPhoneticFallback(String message, String langCode, String? phoneticFallback) async {
    final textToSpeak = (phoneticFallback != null && phoneticFallback.isNotEmpty)
        ? phoneticFallback
        : _toPhonetic(message, langCode);

    try {
      final dynamic inAvail = await _flutterTts.isLanguageAvailable('en-IN');
      if (inAvail == true || inAvail == 1 || (inAvail is num && inAvail >= 0)) {
        await _flutterTts.setLanguage('en-IN');
      } else {
        await _flutterTts.setLanguage('en-US');
      }
    } catch (_) {
      await _flutterTts.setLanguage('en-US');
    }

    await _flutterTts.stop();
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.speak(textToSpeak);
  }

  /// Speaks a structured medicine reminder alert in the user's preferred Indian voice language.
  static Future<void> speakReminder({
    required String recipientName,
    required String medicineName,
    required String dosage,
    String? instructions,
    String? language,
  }) async {
    await init();
    if (!_isVoiceReminderEnabled) {
      return;
    }

    final effectiveLang = getEffectiveLanguage(fallbackLanguage: language);

    final nativeMessage = _buildReminderText(
      langCode: effectiveLang,
      recipientName: recipientName,
      medicineName: medicineName,
      dosage: dosage,
      instructions: instructions,
    );

    final phoneticFallback = _buildPhoneticReminderText(
      langCode: effectiveLang,
      recipientName: recipientName,
      medicineName: medicineName,
      dosage: dosage,
      instructions: instructions,
    );

    await _playUtterance(nativeMessage, effectiveLang, phoneticFallback: phoneticFallback);
  }

  static String _formatInstructions(String? raw, String langCode) {
    if (raw == null || raw.trim().isEmpty) return '';
    final lower = raw.trim().toLowerCase();
    if (langCode == 'bn') {
      if (lower == 'food' || lower == 'with food' || lower == 'খাবারের সাথে') return 'খাবারের সাথে';
      if (lower == 'before food' || lower == 'before meal' || lower == 'খাবারের আগে') return 'খাবারের আগে';
      if (lower == 'after food' || lower == 'after meal' || lower == 'খাবারের পরে') return 'খাবারের পরে';
      if (lower == 'empty stomach' || lower == 'খালি পেটে') return 'খালি পেটে';
      if (lower == 'water' || lower == 'with water' || lower == 'take with water' || lower == 'পানির সাথে') return 'পানির সাথে';
      return raw;
    } else if (langCode == 'hi') {
      if (lower == 'food' || lower == 'with food') return 'भोजन के साथ';
      if (lower == 'before food' || lower == 'before meal') return 'भोजन से पहले';
      if (lower == 'after food' || lower == 'after meal') return 'भोजन के बाद';
      if (lower == 'empty stomach') return 'खाली पेट';
      if (lower == 'water' || lower == 'with water') return 'पानी के साथ';
      return raw;
    }
    return raw;
  }

  static String _formatDosage(String raw, String langCode) {
    final lower = raw.trim().toLowerCase();
    if (langCode == 'bn') {
      if (lower == '1 tablet') return '১টি ট্যাবলেট';
      if (lower == '2 tablets' || lower == '2 tablet') return '২টি ট্যাবলেট';
      if (lower == '1 capsule') return '১টি ক্যাপসুল';
      if (lower == '2 capsules' || lower == '2 capsule') return '২টি ক্যাপসুল';
      if (lower == '1 spoon') return '১ চামচ';
      if (lower == '2 spoons') return '২ চামচ';
      return raw.replaceAll('1', '১').replaceAll('2', '২').replaceAll('3', '৩').replaceAll('4', '৪');
    } else if (langCode == 'hi') {
      if (lower == '1 tablet') return '1 गोली';
      if (lower == '2 tablets' || lower == '2 tablet') return '2 गोलियां';
      if (lower == '1 capsule') return '1 कैप्सूल';
      if (lower == '1 spoon') return '1 चम्मच';
      return raw;
    }
    return raw;
  }

  static String _formatRecipientGreeting(String recipientName, String langCode) {
    final clean = recipientName.trim();
    final lower = clean.toLowerCase();
    final isGeneric = clean.isEmpty ||
        lower == 'user' ||
        lower == 'member' ||
        lower == 'patient' ||
        lower == 'primary caregiver' ||
        lower == 'caregiver' ||
        lower == 'self' ||
        lower == 'ব্যবহারকারী' ||
        lower == 'রোগী';

    switch (langCode) {
      case 'bn':
        return isGeneric ? 'নমস্কার' : 'নমস্কার $clean';
      case 'hi':
        return isGeneric ? 'नमस्ते' : 'नमस्ते $clean';
      case 'ta':
        return isGeneric ? 'வணக்கம்' : 'வணக்கம் $clean';
      case 'te':
        return isGeneric ? 'నమస్కారం' : 'నమస్కారం $clean';
      case 'kn':
        return isGeneric ? 'ನಮಸ್ಕಾರ' : 'ನಮಸ್ಕಾರ $clean';
      case 'ml':
        return isGeneric ? 'നമസ്കാരം' : 'നമസ്കാരം $clean';
      case 'mr':
        return isGeneric ? 'नमस्कार' : 'नमस्कार $clean';
      case 'gu':
        return isGeneric ? 'નમસ્તે' : 'નમસ્તે $clean';
      case 'pa':
        return isGeneric ? 'ਸਤਿ ਸ੍ਰੀ ਅਕਾਲ' : 'ਸਤਿ ਸ੍ਰੀ ਅਕਾਲ $clean';
      case 'or':
        return isGeneric ? 'ନମସ୍କାର' : 'ନମସ୍କାର $clean';
      case 'en':
      default:
        return isGeneric ? 'Hello' : 'Hello $clean';
    }
  }

  static String _buildReminderText({
    required String langCode,
    required String recipientName,
    required String medicineName,
    required String dosage,
    String? instructions,
  }) {
    final greeting = _formatRecipientGreeting(recipientName, langCode);
    final localizedInstructions = _formatInstructions(instructions, langCode);
    final localizedDosage = _formatDosage(dosage, langCode);
    final hasInstructions = localizedInstructions.isNotEmpty;

    switch (langCode) {
      case 'bn':
        return '$greeting, আপনার ওষুধ খাওয়ার সময় হয়েছে: $medicineName, মাত্রা $localizedDosage।${hasInstructions ? " নির্দেশনা: $localizedInstructions।" : ""}';
      case 'hi':
        return '$greeting, आपकी दवा लेने का समय हो गया है: $medicineName, खुराक $localizedDosage।${hasInstructions ? " निर्देश: $localizedInstructions।" : ""}';
      case 'ta':
        return '$greeting, உங்கள் மருந்து உட்கொள்ளும் நேரம் வந்துவிட்டது: $medicineName, அளவு $dosage.${hasInstructions ? " குறிப்பு: $instructions." : ""}';
      case 'te':
        return '$greeting, మీ మందు తీసుకునే సమయం అయింది: $medicineName, మోతాదు $dosage.${hasInstructions ? " సూచన: $instructions." : ""}';
      case 'kn':
        return '$greeting, ನಿಮ್ಮ ಔಷಧಿ ತೆಗೆದುಕೊಳ್ಳುವ ಸಮಯ: $medicineName, ಪ್ರಮಾಣ $dosage.${hasInstructions ? " ಸೂಚನೆ: $instructions." : ""}';
      case 'ml':
        return '$greeting, നിങ്ങളുടെ മരുന്ന് കഴിക്കാനുള്ള সময়: $medicineName, അളവ് $dosage.${hasInstructions ? " നിർദ്ദേശം: $instructions." : ""}';
      case 'mr':
        return '$greeting, तुमची औषध घेण्याची वेळ झाली आहे: $medicineName, डोस $dosage.${hasInstructions ? " सूचना: $instructions." : ""}';
      case 'gu':
        return '$greeting, તમારી દવા લેવાનો સમય થઈ ગયો છે: $medicineName, માત્રા $dosage.${hasInstructions ? " સૂચના: $instructions." : ""}';
      case 'pa':
        return '$greeting, ਤੁਹਾਡੀ ਦਵਾਈ ਲੈਣ ਦਾ ਸਮਾਂ ਹੋ ਗਿਆ ਹੈ: $medicineName, ਖੁਰਾਕ $dosage.${hasInstructions ? " ਹਦਾਇਤ: $instructions." : ""}';
      case 'or':
        return '$greeting, ଆପଣଙ୍କ ଔଷଧ ଖାଇବାର ସମୟ ହୋଇଛି: $medicineName, ମାତ୍ରା $dosage.${hasInstructions ? " ସୂଚନା: $instructions." : ""}';
      case 'en':
      default:
        return '$greeting, it is time to take your medicine: $medicineName, dosage $dosage.${instructions != null && instructions.trim().isNotEmpty ? " Instructions: $instructions." : ""}';
    }
  }

  static String _buildPhoneticReminderText({
    required String langCode,
    required String recipientName,
    required String medicineName,
    required String dosage,
    String? instructions,
  }) {
    final note = instructions != null && instructions.trim().isNotEmpty ? instructions.trim() : null;
    final trimmedName = recipientName.trim();
    final lower = trimmedName.toLowerCase();
    final isGeneric = trimmedName.isEmpty ||
        lower == 'user' ||
        lower == 'member' ||
        lower == 'patient' ||
        lower == 'primary caregiver' ||
        lower == 'caregiver' ||
        lower == 'self' ||
        lower == 'ব্যবহারকারী';

    switch (langCode) {
      case 'bn':
        final greeting = isGeneric ? 'Nomoshkar' : 'Nomoshkar $trimmedName';
        return '$greeting! Apnar oshudh khawar shomoy hoyeche: $medicineName, matra $dosage.${note != null ? " Nirdeshona: $note." : ""}';
      case 'hi':
        final greeting = isGeneric ? 'Namaste' : 'Namaste $trimmedName';
        return '$greeting! Aapki dawa lene ka samay ho gaya hai: $medicineName, khurak $dosage.${note != null ? " Nirdesh: $note." : ""}';
      case 'ta':
        final greeting = isGeneric ? 'Vanakkam' : 'Vanakkam $trimmedName';
        return '$greeting! Ungal marundhu saapida vendiya neram: $medicineName, alavu $dosage.${note != null ? " Kurippu: $note." : ""}';
      case 'te':
        final greeting = isGeneric ? 'Namaskaram' : 'Namaskaram $trimmedName';
        return '$greeting! Mee mandhu theesukune samayam ayindi: $medicineName, mothaadu $dosage.${note != null ? " Soochana: $note." : ""}';
      case 'kn':
        final greeting = isGeneric ? 'Namaskara' : 'Namaskara $trimmedName';
        return '$greeting! Nimma aushadhi thegedukolluva samaya: $medicineName, pramaana $dosage.';
      case 'ml':
        final greeting = isGeneric ? 'Namaskaram' : 'Namaskaram $trimmedName';
        return '$greeting! Ningalude marunnu kazhikkuvaanulla samayam: $medicineName, alavu $dosage.';
      case 'mr':
        final greeting = isGeneric ? 'Namaskar' : 'Namaskar $trimmedName';
        return '$greeting! Tumchi aushadh ghenyachi vel zhaali aahe: $medicineName, dose $dosage.';
      case 'gu':
        final greeting = isGeneric ? 'Namaste' : 'Namaste $trimmedName';
        return '$greeting! Tamaari davaa levano samay thai gayo chhe: $medicineName, maatra $dosage.';
      case 'pa':
        final greeting = isGeneric ? 'Sat Sri Akaal' : 'Sat Sri Akaal $trimmedName';
        return '$greeting! Tuhadi dawai lain da vela ho gaya hai: $medicineName, khuraak $dosage.';
      case 'or':
        final greeting = isGeneric ? 'Namaskar' : 'Namaskar $trimmedName';
        return '$greeting! Aapananka aushadha khaaibara samaya heichi: $medicineName, maatra $dosage.';
      case 'en':
      default:
        final greeting = isGeneric ? 'Hello' : 'Hello $trimmedName';
        return '$greeting, it is time to take your medicine: $medicineName, dosage $dosage.${note != null ? " Instructions: $note." : ""}';
    }
  }

  /// Speaks arbitrary text using the preferred or specified voice language.
  static Future<void> speak(String text, {String? language}) async {
    await init();
    if (!_isVoiceReminderEnabled) {
      return;
    }
    final effectiveLang = getEffectiveLanguage(fallbackLanguage: language);
    final phonetic = _toPhonetic(text, effectiveLang);
    await _playUtterance(text, effectiveLang, phoneticFallback: phonetic);
  }

  static String _toPhonetic(String text, String langCode) {
    if (langCode == 'en') return text;
    var res = text;
    if (langCode == 'bn') {
      res = res.replaceAll('ওষুধ সফলভাবে নেওয়া হয়েছে', 'oshudh shofolbhabe newa hoyeche');
      res = res.replaceAll('ওষুধ নেওয়া হয়নি হিসেবে চিহ্নিত', 'oshudh newa hoyni hishebe chihnito');
      res = res.replaceAll('নমস্কার', 'Nomoshkar');
      res = res.replaceAll('ওষুধ', 'oshudh');
      res = res.replaceAll('সময়সূচি সফলভাবে সংরক্ষিত', 'shomoyshuchi shofolbhabe shongrokkito');
      res = res.replaceAll('সক্রিয়', 'shokriyo');
    } else if (langCode == 'hi') {
      res = res.replaceAll('दवा सफलतापूर्वक ली गई', 'dawa safaltaapoorvak li gayi');
      res = res.replaceAll('दवा नहीं ली गई', 'dawa nahi li gayi');
      res = res.replaceAll('नमस्ते', 'Namaste');
      res = res.replaceAll('दवा', 'dawa');
    }
    return res;
  }

  /// Plays a preview sample in the specified language to test audio output.
  static Future<void> playSample(String langCode) async {
    await init();
    final effectiveLang = langCode == 'auto' ? getEffectiveLanguage() : langCode;

    String sampleNative;
    String samplePhonetic;
    switch (effectiveLang) {
      case 'bn':
        sampleNative = "নমস্কার, এটি কেয়ারভয়েস ওষুধ অনুস্মারকের ভয়েস টেস্ট। আপনার বাংলা ভয়েস অ্যালার্ট সক্রিয় রয়েছে।";
        samplePhonetic = "Nomoshkar! Eti CareVoice oshudh onusmaroker voice test. Apnar Bangla voice alert shokriyo royeche.";
        break;
      case 'hi':
        sampleNative = "नमस्ते, यह केयरवॉयस दवा अनुस्मारक का वॉयस टेस्ट है। आपका हिंदी वॉयस अलर्ट सक्रिय है।";
        samplePhonetic = "Namaste! Yeh CareVoice dawa anusmarak ka voice test hai. Aapka Hindi voice alert sakriya hai.";
        break;
      case 'ta':
        sampleNative = "வணக்கம், இது கேர்வாய்ஸ் மருந்து நினைவூட்டல் குரல் சோதனை. உங்கள் தமிழ் குரல் எச்சரிக்கை செயலில் உள்ளது.";
        samplePhonetic = "Vanakkam! Idhu CareVoice marundhu ninaivuttal kural sodhanai. Ungal Tamil kural echarikkai seyalil ulladhu.";
        break;
      case 'te':
        sampleNative = "నమస్కారం, ఇది కేర్‌వాయిస్ మందుల రిమైండర్ వాయిస్ టెస్ట్. మీ తెలుగు వాయిస్ అలర్ట్ యాక్టివ్‌గా ఉంది.";
        samplePhonetic = "Namaskaram! Idhi CareVoice mandhula reminder voice test. Mee Telugu voice alert active gaa undhi.";
        break;
      case 'kn':
        sampleNative = "ನಮಸ್ಕಾರ, ಇದು ಕೇರ್‌ವಾಯ್ಸ್ ಔಷಧಿ ಜ್ಞಾಪನೆಯ ಧ್ವನಿ ಪರೀಕ್ಷೆ. ನಿಮ್ಮ ಕನ್ನಡ ಧ್ವನಿ ಎಚ್ಚರಿಕೆ ಸಕ್ರಿಯವಾಗಿದೆ.";
        samplePhonetic = "Namaskara! Idu CareVoice aushadhi jnapane dhvani parikshe. Nimma Kannada dhvani eccharike sakriyavaagide.";
        break;
      case 'ml':
        sampleNative = "നമസ്കാരം, ഇത് കെയർവോയ്സ് മരുന്ന് ഓർമ്മപ്പെടുത്തൽ വോയ്‌സ് ടെസ്റ്റാണ്. നിങ്ങളുടെ മലയാളം വോയ്‌സ് അലേർട്ട് സജീവമാണ്.";
        samplePhonetic = "Namaskaram! Ithu CareVoice marunnu ormmappeduthal voice test aanu. Ningalude Malayalam voice alert sajeevamaanu.";
        break;
      case 'mr':
        sampleNative = "नमस्कार, ही केअरव्हॉइस औषध स्मरणपत्राची व्हॉइस चाचणी आहे. तुमचा मराठी व्हॉइस अलर्ट सक्रिय आहे.";
        samplePhonetic = "Namaskar! Hee CareVoice aushadh smaranpatrachi voice chaachani aahe. Tumcha Marathi voice alert sakriya aahe.";
        break;
      case 'gu':
        sampleNative = "નમસ્તે, આ કેરવોઈસ દવા રીમાઇન્ડરનો અવાજ ટેસ્ટ છે. તમારું ગુજરાતી વોઇસ એલર્ટ સક્રિય છે.";
        samplePhonetic = "Namaste! Aa CareVoice dava reminder no awaaz test chhe. Tamaru Gujarati voice alert sakriya chhe.";
        break;
      case 'pa':
        sampleNative = "ਸਤਿ ਸ੍ਰੀ ਅਕਾਲ, ਇਹ ਕੇਅਰਵੌਇਸ ਦਵਾਈ ਰੀਮਾਈਂਡਰ ਦੀ ਆਵਾਜ਼ ਟੈਸਟ ਹੈ। ਤੁਹਾਡੀ ਪੰਜਾਬੀ ਆਵਾਜ਼ ਚੇਤਾਵਨੀ ਸਰਗਰਮ ਹੈ।";
        samplePhonetic = "Sat Sri Akaal! Eh CareVoice dawai reminder di awaaz test hai. Tuhadi Punjabi awaaz chetavni sargarm hai.";
        break;
      case 'or':
        sampleNative = "ନମସ୍କାର, ଏହା କେୟାରଭଏସ ଔଷଧ ସ୍ମାରକର ଭଏସ ପରୀକ୍ଷା। ଆପଣଙ୍କ ଓଡ଼ିଆ ଭଏସ ଆଲର୍ଟ ସକ୍ରିୟ ଅଛି।";
        samplePhonetic = "Namaskar! Eha CareVoice aushadha smaraka ra voice parikshya. Aapananka Odia voice alert sakriya achhi.";
        break;
      case 'en':
      default:
        sampleNative = "Hello, this is a test of your CareVoice medicine reminder. Your English voice alert is active.";
        samplePhonetic = "Hello, this is a test of your CareVoice medicine reminder. Your English voice alert is active.";
        break;
    }

    await _playUtterance(sampleNative, effectiveLang, phoneticFallback: samplePhonetic);
  }

  static Future<void> stop() async {
    isPlayingNotifier.value = false;
    if (kIsWeb) {
      stopWebAudio();
    }
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }
}
