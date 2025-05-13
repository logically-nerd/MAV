// confirmation_handler.dart
import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/services.dart';

class ConfirmationHandler {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  Future<void> preload() async {
    print("[Confirm] Preloading STT...");
    bool available = await _speech.initialize();
    print("[Confirm] STT available: $available");

    _tts.setCompletionHandler(() => print("[TTS] Done speaking"));
    await _tts.awaitSpeakCompletion(true);
  }

  Future<bool?> confirmDestination(String destination) async {
    print("[Confirm] Asking for confirmation: $destination");
    await _tts.speak("You said navigate to $destination. Should I go ahead?");
    await Future.delayed(const Duration(milliseconds: 300));
    return _handleConfirmation();
  }

  Future<bool?> confirmAwareness() async {
    print("[Confirm] Confirming awareness intent");
    await _tts.speak("You asked for surrounding awareness. Is that correct?");
    await Future.delayed(const Duration(milliseconds: 300));
    return _handleConfirmation();
  }

  Future<bool?> _handleConfirmation() async {
    int attempts = 0;

    while (attempts < 2) {
      HapticFeedback.heavyImpact();
      print("[Confirm] Listening attempt: $attempts");

      bool available = await _speech.initialize();
      print("[Confirm] STT ready: $available");
      if (!available) return null;

      final result = await _listenForAffirmation();
      print("[Confirm] Result: $result");

      if (result != null) return result;

      attempts++;
      if (attempts < 2) {
        await _tts.speak("Sorry, I didn't catch that. Please say it again.");
      }
    }

    await _tts
        .speak("Still didn't catch that. Please double tap to speak again.");
    return null;
  }

  Future<bool?> _listenForAffirmation() async {
    Completer<bool?> completer = Completer();

    _speech.listen(
      listenMode: stt.ListenMode.confirmation,
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(seconds: 5),
      onResult: (result) {
        final transcript = result.recognizedWords.toLowerCase().trim();
        print("[Confirm] Heard: $transcript");

        if (result.finalResult) {
          if (transcript.isEmpty) {
            completer.complete(null);
          } else if (_isAffirmative(transcript)) {
            completer.complete(true);
          } else if (_isNegative(transcript)) {
            completer.complete(false);
          } else {
            completer.complete(null);
          }
        }
      },
    );

    Future.delayed(const Duration(seconds: 6), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    return completer.future;
  }

  bool _isAffirmative(String input) => [
        "yes",
        "yeah",
        "sure",
        "okay",
        "ok",
        "affirmative",
        "go ahead",
        "do it"
      ].any((w) => input.contains(w));

  bool _isNegative(String input) => [
        "no",
        "nope",
        "nah",
        "not now",
        "cancel",
        "stop",
        "leave it",
        "don't"
      ].any((w) => input.contains(w));
}
