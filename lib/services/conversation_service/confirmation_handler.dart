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

  // Improved method with proper TTS/STT sequencing
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

    // Overall timeout for the entire confirmation process
    Timer? overallTimer = Timer(const Duration(seconds: 45), () {
      if (!completer.isCompleted) {
        print("[Confirm] Overall timeout reached");
        completer.complete(null);
      }
    });

    Future<void> ask() async {
      if (attempts >= maxAttempts) {
        print("[Confirm] Max attempts reached, giving up");

        // Wait for TTS to complete before finishing
        await _speakAndWait(
          "Still didn't catch that. Please double tap to speak again.",
          TtsPriority.conversation,
        );

        if (!completer.isCompleted) {
          completer.complete(null);
        }
        return;
      }

      attempts++;
      String message =
          (attempts > 1) ? "Sorry, I didn't catch that. $question" : question;

      print("[Confirm] Attempt $attempts: $message");

      try {
        // 1. Speak and wait for completion
        await _speakAndWait(message, TtsPriority.conversation);

        // 2. Add haptic feedback
        HapticFeedback.heavyImpact();

        // 3. Ensure TTS is completely finished with additional buffer
        await Future.delayed(const Duration(milliseconds: 500));

        // 4. Start listening (timeout starts here)
        final result = await _listenForAffirmation();

        if (!completer.isCompleted) {
          if (result != null) {
            print("[Confirm] Got result: $result");
            completer.complete(result);
          } else {
            print("[Confirm] No result, trying again...");
            // If listening failed, ask again
            await ask();
          }
        }
      } catch (e) {
        print("[Confirm] Error in ask attempt: $e");
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    }

    await ask(); // Start the first attempt

    final result = await completer.future;
    overallTimer?.cancel();
    return result;
  }

  // Helper method to speak and wait for completion
  Future<void> _speakAndWait(String text, TtsPriority priority) async {
    Completer<void> ttsCompleter = Completer();

    _ttsService.speak(
      text,
      priority,
      onComplete: () {
        print("[Confirm] TTS completed for: $text");
        if (!ttsCompleter.isCompleted) {
          ttsCompleter.complete();
        }
      },
    );

    // Wait for TTS to complete with timeout
    await ttsCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print("[Confirm] TTS timeout for: $text");
      },
    );
  }

  Future<bool?> _listenForAffirmation() async {
    if (!_isInitialized) {
      print("[Confirm] STT not initialized for listening");
      return null;
    }

    Completer<bool?> completer = Completer();
    bool isListening = false;
    Timer? listeningTimer;

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

        // Start timeout ONLY after listening actually begins
        listeningTimer = Timer(const Duration(seconds: 10), () {
          if (!completer.isCompleted) {
            print("[Confirm] Listening timeout reached");
            _speech.stop();
            completer.complete(null);
          }
        });
      }
    } catch (e) {
      print("[Confirm] Exception during listening: $e");
      completer.complete(null);
    }

    final result = await completer.future;

    // Cleanup
    listeningTimer?.cancel();
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
