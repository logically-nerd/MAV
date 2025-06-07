import 'dart:async';
import 'package:MAV/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ConfirmationHandler {
  final stt.SpeechToText _speech = stt.SpeechToText();
  // REMOVED: final FlutterTts _tts = FlutterTts();
  final TtsService _ttsService = TtsService.instance; // ADDED: Use the service

  Future<void> preload() async {
    print("[Confirm] Preloading STT...");
    await _speech.initialize();
    // REMOVED: TTS preload logic is now centralized
  }

  Future<bool?> confirmDestination(String destination) async {
    print("[Confirm] Asking for confirmation: $destination");
    // Use the TtsService with a callback to listen AFTER speaking
    return _askAndListen(
        "You said navigate to $destination. Should I go ahead?");
  }

  Future<bool?> confirmAwareness() async {
    print("[Confirm] Confirming awareness intent");
    // Use the TtsService with a callback to listen AFTER speaking
    return _askAndListen(
        "You asked for surrounding awareness. Is that correct?");
  }

  // NEW: Centralized method to speak and then listen for confirmation
  Future<bool?> _askAndListen(String question) async {
    Completer<bool?> completer = Completer();
    int attempts = 0;

    void ask() {
      if (attempts >= 2) {
        _ttsService.speak(
          "Still didn't catch that. Please double tap to speak again.",
          TtsPriority.conversation,
          onComplete: () => completer.complete(null),
        );
        return;
      }

      attempts++;
      String message =
          (attempts > 1) ? "Sorry, I didn't catch that. $question" : question;

      // Speak, and in the onComplete callback, start listening. This is the key change.
      _ttsService.speak(
        message,
        TtsPriority.conversation,
        onComplete: () async {
          HapticFeedback.heavyImpact();
          final result = await _listenForAffirmation();
          if (result != null) {
            completer.complete(result);
          } else {
            // If listening failed, ask again
            ask();
          }
        },
      );
    }

    ask(); // Start the first attempt
    return completer.future;
  }

  // This method no longer needs to handle TTS retries
  Future<bool?> _listenForAffirmation() async {
    bool available = await _speech.initialize();
    if (!available) return null;

    Completer<bool?> completer = Completer();

    _speech.listen(
      listenMode: stt.ListenMode.confirmation,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(seconds: 10),
      onResult: (result) {
        if (result.finalResult && !completer.isCompleted) {
          final transcript = result.recognizedWords.toLowerCase().trim();
          if (transcript.isEmpty)
            completer.complete(null);
          else if (_isAffirmative(transcript))
            completer.complete(true);
          else if (_isNegative(transcript))
            completer.complete(false);
          else
            completer.complete(null);
        }
      },
    );

    // Timeout for the listening part
    Future.delayed(const Duration(seconds: 6), () {
      if (!completer.isCompleted) {
        _speech.stop();
        completer.complete(null);
      }
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
