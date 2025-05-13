// speech_intent_service.dart
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

enum IntentType { navigate, awareness, unknown }

class IntentResult {
  final IntentType intent;
  final String? destination;
  final String raw;

  IntentResult({required this.intent, this.destination, required this.raw});
}

class SpeechIntentService {
  static final SpeechIntentService instance = SpeechIntentService._internal();
  factory SpeechIntentService() => instance;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _isListening = false;

  SpeechIntentService._internal();

  Future<void> preload() async {
    print("[Intent] Preloading speech...");
    bool available = await _speech.initialize();
    print("[Intent] Speech available: $available");

    _tts.setCompletionHandler(() => print("[TTS] Done speaking"));
    await _tts.awaitSpeakCompletion(true);
    print("[TTS] TTS initialized");
  }

  Future<void> _speak(String message) async {
    print("[TTS] Speaking: $message");
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(message);
  }

  Future<void> _feedbackStart() async {
    HapticFeedback.mediumImpact();
    await _speak("Listening");
  }

  Future<void> _feedbackStop() async {
    HapticFeedback.vibrate();
  }

  Future<IntentResult?> listenAndClassify() async {
    if (_isListening) {
      print("[Intent] Already listening. Ignoring.");
      return null;
    }

    _isListening = true;

    bool available = await _speech.initialize();
    print("[Intent] STT available: $available");

    if (!available) {
      await _speak("Speech recognition not available.");
      _isListening = false;
      return null;
    }

    await _feedbackStart();
    await Future.delayed(const Duration(milliseconds: 100));

    Completer<IntentResult?> completer = Completer();
    bool resultHandled = false;

    _speech.statusListener = (status) async {
      print("[STT] Status: $status");

      if (status == "notListening" &&
          !resultHandled &&
          !completer.isCompleted) {
        // Wait briefly to see if result comes in late
        await Future.delayed(Duration(milliseconds: 500));
        if (!resultHandled && !completer.isCompleted) {
          resultHandled = true;
          await _speak("Didn't catch anything.");
          completer.complete(null);
          _isListening = false;
        }
      }
    };

    _speech.listen(
      listenMode: stt.ListenMode.dictation,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(seconds: 12),
      onResult: (result) async {
        print("[STT] Got result: ${result.recognizedWords}");
        if (result.finalResult && !resultHandled) {
          resultHandled = true;
          await _feedbackStop();

          final transcript = result.recognizedWords.toLowerCase().trim();
          print("[Intent] Final Transcript: $transcript");

          if (transcript.isEmpty) {
            await _speak("No input detected.");
            completer.complete(null);
            _isListening = false;
            return;
          }

          final intent = _classifyIntent(transcript);
          final isMissingDestination = intent.intent == IntentType.navigate &&
              (intent.destination == null || intent.destination!.isEmpty);

          if (intent.intent == IntentType.unknown || isMissingDestination) {
            await _speak(
                "Try saying 'navigate to park' or 'what's around me'.");
            completer.complete(null);
          } else {
            completer.complete(intent);
          }

          _isListening = false;
        }
      },
    );

    return completer.future;
  }

  IntentResult _classifyIntent(String sentence) {
    print("[Intent] Classifying: $sentence");
    if (_matchesAwareness(sentence)) {
      return IntentResult(intent: IntentType.awareness, raw: sentence);
    } else if (_matchesNavigate(sentence)) {
      final destination = _extractDestination(sentence);
      return IntentResult(
        intent: IntentType.navigate,
        destination: destination,
        raw: sentence,
      );
    } else {
      return IntentResult(intent: IntentType.unknown, raw: sentence);
    }
  }

  bool _matchesAwareness(String sentence) {
    const patterns = [
      "surrounding",
      "what's around",
      "near me",
      "environment",
      "area info",
      "where am i",
      "get surrounding",
      "what can you see"
    ];
    return patterns.any((p) => sentence.contains(p));
  }

  bool _matchesNavigate(String sentence) {
    const keywords = [
      "navigate to",
      "go to",
      "head to",
      "take me to",
      "let's go to",
      "i want to go to",
      "move to",
      "get to"
    ];
    return keywords.any((k) => sentence.contains(k));
  }

  String? _extractDestination(String sentence) {
    final regex = RegExp(
      r"(navigate to|go to|head to|take me to|let's go to|i want to go to|move to|get to)\s+(.*)",
    );
    final match = regex.firstMatch(sentence);
    print("[Intent] Extracted destination: ${match?.group(2)?.trim()}");
    return match?.group(2)?.trim();
  }
}
