import 'dart:async';
import 'package:MAV/services/tts_service.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ConfirmationHandler {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TtsService _ttsService = TtsService.instance;
  bool _isInitialized = false;

  stt.SpeechToText get speech => _speech;
  bool get isInitialized => _isInitialized;

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
    await _ttsService.speakAndWait(
        "You asked for surrounding awareness. Is that correct? Please say yes or no.",
        TtsPriority.confirmation);

    // Small pause before listening to ensure TTS is complete
    await Future.delayed(const Duration(milliseconds: 300));

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

  // Replace the _listenForAffirmation method in ConfirmationHandler:

  Future<bool?> _listenForAffirmation() async {
    if (!_isInitialized) {
      print("[Confirm] ❌ STT not initialized for listening");
      return null;
    }

    final completer = Completer<bool?>();
    bool resultHandled = false;

    try {
      print("[Confirm] 🎤 Starting STT...");

      // Use a simpler status listener like ConversationService
      _speech.statusListener = (status) async {
        print("[Confirm] 📡 STT Status: $status");

        if (status == "notListening" &&
            !resultHandled &&
            !completer.isCompleted) {
          await Future.delayed(Duration(milliseconds: 500));
          if (!resultHandled && !completer.isCompleted) {
            resultHandled = true;
            completer.complete(null);
          }
        }
      };

      // Use the same parameters as ConversationService (known to work)
      await _speech.listen(
        pauseFor: const Duration(seconds: 5),
        listenFor: const Duration(seconds: 12),
        // Remove listenMode parameter to use default like ConversationService
        onResult: (result) {
          print(
              "[Confirm] 📝 STT Result: '${result.recognizedWords}' (final: ${result.finalResult})");

          if (result.finalResult && !resultHandled) {
            resultHandled = true;
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

      // Use a simple timeout like ConversationService
      Timer(Duration(seconds: 15), () {
        if (!completer.isCompleted) {
          resultHandled = true;
          print("[Confirm] ⏰ Timeout reached");
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e) {
      print("[Confirm] ❌ Exception during STT: $e");
      return null;
    } finally {
      // Cleanup
      try {
        if (_speech.isListening) {
          await _speech.stop();
        }
      } catch (e) {
        print("[Confirm] ⚠ Error stopping STT: $e");
      }

      // Reset status listener
      _speech.statusListener = null;
    }
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
