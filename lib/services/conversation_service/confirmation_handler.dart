import 'dart:async';
import 'package:MAV/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ConfirmationHandler {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TtsService _ttsService = TtsService.instance;
  bool _isInitialized = false;

  Future<void> preload() async {
    print("[Confirm] Preloading STT...");
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) => print("[Confirm] STT Error during init: $error"),
        onStatus: (status) => print("[Confirm] STT Status: $status"),
      );

      if (_isInitialized) {
        print("[Confirm] STT initialized successfully");
      } else {
        print("[Confirm] STT initialization failed");
      }
    } catch (e) {
      print("[Confirm] STT initialization exception: $e");
      _isInitialized = false;
    }
  }

  Future<bool?> confirmDestination(String destination) async {
    print("[Confirm] Asking for confirmation: $destination");
    return _askAndListen(
        "You said navigate to $destination. Should I go ahead?");
  }

  Future<bool?> confirmAwareness() async {
    print("[Confirm] Confirming awareness intent");
    return _askAndListen(
        "You asked for surrounding awareness. Is that correct?");
  }

  // Centralized method to speak and then listen for confirmation
  Future<bool?> _askAndListen(String question) async {
    if (!_isInitialized) {
      print("[Confirm] STT not initialized, attempting to initialize...");
      await preload();
      if (!_isInitialized) {
        print("[Confirm] Failed to initialize STT");
        return null;
      }
    }

    Completer<bool?> completer = Completer();
    int attempts = 0;
    const maxAttempts = 2;

    void ask() {
      if (attempts >= maxAttempts) {
        print("[Confirm] Max attempts reached, giving up");
        _ttsService.speak(
          "Still didn't catch that. Please double tap to speak again.",
          TtsPriority.conversation,
          onComplete: () {
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          },
        );
        return;
      }

      attempts++;
      String message =
          (attempts > 1) ? "Sorry, I didn't catch that. $question" : question;

      print("[Confirm] Attempt $attempts: $message");

      // Speak, and in the onComplete callback, start listening
      _ttsService.speak(
        message,
        TtsPriority.conversation,
        onComplete: () async {
          print("[Confirm] TTS completed, starting STT...");
          HapticFeedback.heavyImpact();

          // Small delay to ensure TTS is fully completed
          await Future.delayed(const Duration(milliseconds: 300));

          final result = await _listenForAffirmation();

          if (!completer.isCompleted) {
            if (result != null) {
              print("[Confirm] Got result: $result");
              completer.complete(result);
            } else {
              print("[Confirm] No result, trying again...");
              // If listening failed, ask again
              ask();
            }
          }
        },
      );
    }

    ask(); // Start the first attempt

    // Overall timeout for the entire confirmation process
    Timer(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        print("[Confirm] Overall timeout reached");
        completer.complete(null);
      }
    });

    return completer.future;
  }

  Future<bool?> _listenForAffirmation() async {
    if (!_isInitialized) {
      print("[Confirm] STT not initialized for listening");
      return null;
    }

    Completer<bool?> completer = Completer();
    bool isListening = false;

    try {
      print("[Confirm] Starting to listen...");

      isListening = await _speech.listen(
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 8),
        onResult: (result) {
          print(
              "[Confirm] STT Result: '${result.recognizedWords}' (final: ${result.finalResult})");

          if (result.finalResult && !completer.isCompleted) {
            final transcript = result.recognizedWords.toLowerCase().trim();
            print("[Confirm] Processing transcript: '$transcript'");

            if (transcript.isEmpty) {
              print("[Confirm] Empty transcript");
              completer.complete(null);
            } else if (_isAffirmative(transcript)) {
              print("[Confirm] Affirmative response detected");
              completer.complete(true);
            } else if (_isNegative(transcript)) {
              print("[Confirm] Negative response detected");
              completer.complete(false);
            } else {
              print("[Confirm] Unclear response: '$transcript'");
              completer.complete(null);
            }
          }
        },
        onSoundLevelChange: (level) {
          // Optional: log sound levels for debugging
          // print("[Confirm] Sound level: $level");
        },
      );

      if (!isListening) {
        print("[Confirm] Failed to start listening");
        completer.complete(null);
      } else {
        print("[Confirm] Successfully started listening");
      }
    } catch (e) {
      print("[Confirm] Exception during listening: $e");
      completer.complete(null);
    }

    // Timeout for the listening part
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) {
        print("[Confirm] Listening timeout reached");
        _speech.stop();
        completer.complete(null);
      }
    });

    final result = await completer.future;

    // Ensure we stop listening
    if (isListening) {
      await _speech.stop();
    }

    return result;
  }

  bool _isAffirmative(String input) {
    final affirmatives = [
      "yes",
      "yeah",
      "yep",
      "sure",
      "okay",
      "ok",
      "affirmative",
      "go ahead",
      "do it",
      "proceed",
      "correct",
      "right",
      "true",
      "absolutely",
      "definitely",
      "confirm",
      "confirmed"
    ];

    return affirmatives.any((word) => input.contains(word));
  }

  bool _isNegative(String input) {
    final negatives = [
      "no",
      "nope",
      "nah",
      "not now",
      "cancel",
      "stop",
      "leave it",
      "don't",
      "negative",
      "wrong",
      "incorrect",
      "false",
      "never",
      "abort"
    ];

    return negatives.any((word) => input.contains(word));
  }
}
