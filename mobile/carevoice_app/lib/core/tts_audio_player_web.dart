// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

html.AudioElement? _activeAudioElement;

/// Plays voice directly in the web browser using Web Speech API (window.speechSynthesis)
void speakWebSpeech(String message, String langCode) {
  try {
    final synth = html.window.speechSynthesis;
    if (synth != null) {
      synth.cancel();

      final utterance = html.SpeechSynthesisUtterance(message);

      String localeTag;
      switch (langCode) {
        case 'bn': localeTag = 'bn-IN'; break;
        case 'hi': localeTag = 'hi-IN'; break;
        case 'ta': localeTag = 'ta-IN'; break;
        case 'te': localeTag = 'te-IN'; break;
        case 'kn': localeTag = 'kn-IN'; break;
        case 'ml': localeTag = 'ml-IN'; break;
        case 'mr': localeTag = 'mr-IN'; break;
        case 'gu': localeTag = 'gu-IN'; break;
        case 'pa': localeTag = 'pa-IN'; break;
        case 'or': localeTag = 'or-IN'; break;
        case 'en': default: localeTag = 'en-US'; break;
      }

      utterance.lang = localeTag;
      utterance.rate = 0.95;
      utterance.pitch = 1.0;
      utterance.volume = 1.0;

      final voices = synth.getVoices();
      if (voices.isNotEmpty) {
        for (final v in voices) {
          final vLang = (v.lang ?? '').toLowerCase().replaceAll('_', '-');
          if (vLang.startsWith(langCode.toLowerCase()) || vLang.startsWith(localeTag.toLowerCase())) {
            utterance.voice = v;
            break;
          }
        }
      }

      synth.speak(utterance);
      return;
    }
  } catch (e) {
    html.window.console.warn('Web SpeechSynthesis error: $e');
  }
}

/// Plays audio directly in the web browser using an HTML5 AudioElement
void playWebAudio(String url) {
  try {
    if (_activeAudioElement != null) {
      _activeAudioElement!.pause();
      _activeAudioElement!.src = '';
      _activeAudioElement!.remove();
      _activeAudioElement = null;
    }

    final audio = html.AudioElement();
    audio.setAttribute('referrerpolicy', 'no-referrer');
    audio.src = url;
    _activeAudioElement = audio;
    audio.autoplay = true;
    audio.volume = 1.0;

    html.document.body?.append(audio);

    audio.onEnded.listen((_) {
      audio.remove();
      if (_activeAudioElement == audio) {
        _activeAudioElement = null;
      }
    });

    audio.onError.listen((e) {
      html.window.console.warn('Audio playback error: $e');
      audio.remove();
      if (_activeAudioElement == audio) {
        _activeAudioElement = null;
      }
    });

    audio.play().catchError((err) {
      html.window.console.warn('Audio play error: $err');
    });
  } catch (e) {
    html.window.console.warn('playWebAudio error: $e');
  }
}

/// Stops any actively playing audio element
void stopWebAudio() {
  try {
    if (_activeAudioElement != null) {
      _activeAudioElement!.pause();
      _activeAudioElement!.src = '';
      _activeAudioElement!.remove();
      _activeAudioElement = null;
    }
  } catch (_) {}
}
