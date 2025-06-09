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
        print("[Confirm] ✓ STT initialized successfully");
      } else {
        print("[Confirm] ✗ STT initialization failed");
      }
    } catch (e) {
      print("[Confirm] STT initialization exception: $e");
      _isInitialized = false;
    }
  }

  Future<bool?> confirmDestination(String destination) async {
    print("[Confirm] Starting confirmation for destination: $destination");

    // Use higher priority for confirmation prompts
    await _ttsService.speakAndWait(
      "Do you want to navigate to $destination? Please say yes or no.",
      TtsPriority.confirmation, // Changed from conversation to confirmation
    );

    return await _askAndListen("Do you want to navigate to $destination?");
  }

  Future<bool?> confirmAwareness() async {
    print("[Confirm] Confirming awareness intent");
    return _askAndListen(
        "You asked for surrounding awareness. Is that correct?");
  }

  Future<bool?> _askAndListen(String question) async {
    int attempts = 0;
    const int maxAttempts = 2;

    while (attempts < maxAttempts) {
      attempts++;
      print("[Confirm] Attempt $attempts of $maxAttempts");

      try {
        // Small buffer to ensure everything is ready
        await Future.delayed(const Duration(milliseconds: 300));

        // Start listening for response
        final result = await _listenForAffirmation();

        if (result != null) {
          print("[Confirm] ✅ Got valid result: $result");
          return result;
        } else {
          print("[Confirm] ❌ No valid result, will retry if attempts remain");
          // Only prompt for retry if we have attempts left
          if (attempts < maxAttempts) {
            print(
                "[Confirm] 🔄 Prompting for retry (attempt ${attempts + 1} of $maxAttempts)");
            await _ttsService.speakAndWait(
              "I didn't catch that. Please say yes or no.",
              TtsPriority.confirmation,
            );
          }
        }
      } catch (e) {
        print("[Confirm] ❌ Error in attempt $attempts: $e");
        break;
      }
    }

    // Max attempts reached
    print("[Confirm] ❌ Max attempts reached, giving up");
    await _ttsService.speakAndWait(
      "I didn't catch your response. Please try the command again.",
      TtsPriority.confirmation, // Use confirmation priority
    );
    return null;
  }

  Future<bool?> _listenForAffirmation() async {
    if (!_isInitialized) {
      print("[Confirm] ❌ STT not initialized for listening");
      return null;
    }

    final completer = Completer<bool?>();
    Timer? timeoutTimer;
    bool sttActuallyStarted = false;
    bool listenAttempted = false;

    try {
      print("[Confirm] 🎤 Attempting to start STT...");

      // Set up status listener to detect when STT actually starts
      _speech.statusListener = (status) {
        print("[Confirm] 📡 STT Status: $status");

        if (status == "listening" && !sttActuallyStarted) {
          sttActuallyStarted = true;
          print(
              "[Confirm] ✅ STT actually started listening - NOW starting timeout");

          // Start timeout timer ONLY when STT actually begins listening
          timeoutTimer = Timer(const Duration(seconds: 10), () {
            if (!completer.isCompleted) {
              print("[Confirm] ⏰ STT timeout reached");
              _speech.stop();
              completer.complete(null);
            }
          });
        }

        if (status == "notListening" &&
            sttActuallyStarted &&
            !completer.isCompleted) {
          print("[Confirm] 🔇 STT stopped listening without result");
          // Give a moment for final result to come in
          Timer(Duration(milliseconds: 500), () {
            if (!completer.isCompleted) {
              print("[Confirm] 📭 No final result received");
              completer.complete(null);
            }
          });
        }

        if (status == "done" && !completer.isCompleted) {
          print("[Confirm] 🏁 STT marked as done");
          // Give a moment for final result to come in
          Timer(Duration(milliseconds: 300), () {
            if (!completer.isCompleted) {
              print("[Confirm] 📭 STT done but no result");
              completer.complete(null);
            }
          });
        }
      };

      // Start listening - ignore the return value, rely on status listener
      final listenResult = await _speech.listen(
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 8),
        onResult: (result) {
          print(
              "[Confirm] 📝 STT Result: '${result.recognizedWords}' (final: ${result.finalResult})");

          if (result.finalResult && !completer.isCompleted) {
            final transcript = result.recognizedWords.toLowerCase().trim();
            print("[Confirm] 🔍 Processing final transcript: '$transcript'");

            if (transcript.isEmpty) {
              print("[Confirm] 📭 Empty transcript");
              completer.complete(null);
            } else if (_isAffirmative(transcript)) {
              print("[Confirm] ✅ Affirmative response detected");
              completer.complete(true);
            } else if (_isNegative(transcript)) {
              print("[Confirm] ❌ Negative response detected");
              completer.complete(false);
            } else {
              print("[Confirm] ❓ Unclear response: '$transcript'");
              completer.complete(null);
            }
          }
        },
      );

      listenAttempted = true;
      print(
          "[Confirm] 📞 STT listen() called (returned: $listenResult), waiting for status...");

      // Set up a backup timer in case the status never changes to "listening"
      Timer(const Duration(seconds: 3), () {
        if (!sttActuallyStarted && !completer.isCompleted) {
          print("[Confirm] ⚠ STT didn't start listening after 3 seconds");
          // Check if STT is available
          if (!_speech.isAvailable) {
            print("[Confirm] ❌ STT is not available");
            completer.complete(null);
          } else {
            print(
                "[Confirm] ❌ STT available but didn't start - assuming failure");
            completer.complete(null);
          }
        }
      });
    } catch (e) {
      print("[Confirm] ❌ Exception during STT setup: $e");
      completer.complete(null);
    }

    // Wait for result
    final result = await completer.future;

    // Cleanup
    timeoutTimer?.cancel();
    if (listenAttempted || sttActuallyStarted) {
      try {
        await _speech.stop();
      } catch (e) {
        print("[Confirm] ⚠ Error stopping STT: $e");
      }
    }

    // Reset status listener
    _speech.statusListener = null;

    print("[Confirm] 🏁 Listening session ended with result: $result");
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
