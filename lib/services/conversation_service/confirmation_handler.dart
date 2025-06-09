import 'dart:async';
import 'package:MAV/services/tts_service.dart';
import 'package:flutter/services.dart'; // Required for HapticFeedback if used, but not directly here.
import 'package:speech_to_text/speech_to_text.dart' as stt;

class ConfirmationHandler {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final TtsService _ttsService = TtsService.instance;
  bool _isInitialized = false;
  bool _isListeningForConfirmation = false; // To prevent concurrent listens

  // stt.SpeechToText get speech => _speech; // Not typically needed externally
  bool get isInitialized => _isInitialized;

  Future<void> preload() async {
    print("[Confirm] Preloading STT for confirmations...");
    try {
      _isInitialized = await _speech.initialize(
        onError: (error) => print("[Confirm] STT Error during init: $error"),
        onStatus: (status) =>
            print("[Confirm] STT Status during init: $status"),
      );

      if (_isInitialized) {
        print("[Confirm] ✓ STT for confirmations initialized successfully");
      } else {
        print("[Confirm] ✗ STT for confirmations initialization failed");
        // Optionally, speak an error if critical, but usually handled by calling service
      }
    } catch (e) {
      print("[Confirm] STT initialization exception: $e");
      _isInitialized = false;
    }
  }

  Future<bool?> confirmDestination(String destination) async {
    print("[Confirm] Starting confirmation for destination: $destination");
    // TTS blocking is now handled by the caller (e.g., ConversationService or NavigationHandler)

    // Ensure TTS service stops current speech before asking for confirmation
    _ttsService.stop();
    await Future.delayed(
        const Duration(milliseconds: 100)); // allow stop to propagate

    await _ttsService.speakAndWait(
      "Do you want to navigate to $destination? Please say yes or no.",
      TtsPriority.confirmation,
    );

    return await _askAndListen(); // Removed question parameter as it's spoken above
  }

  Future<bool?> confirmAwareness() async {
    print("[Confirm] Confirming awareness intent");
    // TTS blocking is handled by the caller

    _ttsService.stop();
    await Future.delayed(const Duration(milliseconds: 100));

    await _ttsService.speakAndWait(
        "You asked for surrounding awareness. Is that correct? Please say yes or no.",
        TtsPriority.confirmation);

    // Small pause before listening to ensure TTS is complete and mic is ready
    await Future.delayed(const Duration(milliseconds: 300));

    return await _askAndListen(); // Removed question parameter
  }

  Future<bool?> _askAndListen() async {
    if (_isListeningForConfirmation) {
      print(
          "[Confirm] Already listening for a confirmation. Aborting new request.");
      return null;
    }
    if (!_isInitialized) {
      print("[Confirm] ✗ STT not initialized. Cannot listen for confirmation.");
      await _ttsService.speakAndWait(
          "Speech input is not ready for confirmation.",
          TtsPriority.confirmation);
      return null;
    }

    _isListeningForConfirmation = true;
    int attempts = 0;
    const int maxAttempts = 2;

    try {
      while (attempts < maxAttempts) {
        attempts++;
        print(
            "[Confirm] Listening attempt $attempts of $maxAttempts for yes/no");

        // Small buffer before listening
        await Future.delayed(const Duration(milliseconds: 200));

        final result = await _listenForAffirmation();

        if (result != null) {
          print("[Confirm] ✅ Got valid confirmation result: $result");
          return result;
        } else {
          print(
              "[Confirm] ❌ No valid confirmation result in attempt $attempts");
          if (attempts < maxAttempts) {
            await _ttsService.speakAndWait(
              "I didn't catch that. Please say yes or no.",
              TtsPriority.confirmation,
            );
          }
        }
      }

      // Max attempts reached
      print("[Confirm] ❌ Max attempts reached for confirmation.");
      await _ttsService.speakAndWait(
        "I didn't get a clear response. Please try your command again.",
        TtsPriority.confirmation,
      );
      return null;
    } catch (e) {
      print("[Confirm] ❌ Error during confirmation listening: $e");
      await _ttsService.speakAndWait(
          "An error occurred during confirmation.", TtsPriority.confirmation);
      return null;
    } finally {
      _isListeningForConfirmation = false;
      if (_speech.isListening) {
        _speech.stop();
      }
      print("[Confirm] Finished listening for yes/no.");
    }
  }

  Future<bool?> _listenForAffirmation() async {
    if (!_isInitialized || !_speech.isAvailable) {
      // Check isAvailable too
      print("[Confirm] ❌ STT not initialized or available for listening.");
      return null;
    }

    final completer = Completer<bool?>();
    bool resultHandled = false;

    try {
      print("[Confirm] 🎤 Starting STT for yes/no...");

      _speech.statusListener = (status) async {
        print("[Confirm] 📡 STT Status (Confirmation): $status");
        if (status == "notListening" &&
            !resultHandled &&
            !completer.isCompleted) {
          await Future.delayed(
              const Duration(milliseconds: 300)); // Short delay
          if (!resultHandled && !completer.isCompleted) {
            resultHandled = true;
            print(
                "[Confirm] STT stopped without final result during confirmation.");
            completer.complete(null);
          }
        }
      };

      _speech.errorListener = (errorNotification) {
        print(
            "[Confirm] STT Error (Confirmation): ${errorNotification.errorMsg}");
        if (!resultHandled && !completer.isCompleted) {
          resultHandled = true;
          completer.complete(null);
        }
      };

      await _speech.listen(
        pauseFor: const Duration(seconds: 3), // Shorter pause for yes/no
        listenFor: const Duration(seconds: 7), // Max duration for yes/no
        onResult: (result) {
          print(
              "[Confirm] 📝 STT Result (Confirmation): '${result.recognizedWords}' (final: ${result.finalResult})");

          if (result.finalResult && !resultHandled) {
            resultHandled = true;
            final transcript = result.recognizedWords.toLowerCase().trim();
            print(
                "[Confirm] 🔍 Processing final transcript for confirmation: '$transcript'");

            if (transcript.isEmpty) {
              print("[Confirm] 📭 Empty transcript for confirmation.");
              completer.complete(null);
            } else if (_isAffirmative(transcript)) {
              print("[Confirm] ✅ Affirmative response detected.");
              completer.complete(true);
            } else if (_isNegative(transcript)) {
              print("[Confirm] ❌ Negative response detected.");
              completer.complete(false);
            } else {
              print(
                  "[Confirm] ❓ Unclear response for confirmation: '$transcript'");
              completer.complete(null);
            }
          }
        },
      );

      // Timeout for the completer itself, in case STT hangs or doesn't call onResult/statusListener as expected
      Timer(const Duration(seconds: 8), () {
        if (!resultHandled && !completer.isCompleted) {
          resultHandled = true;
          print("[Confirm] ⏰ Timeout waiting for STT result in confirmation.");
          if (_speech.isListening) _speech.cancel(); // Attempt to cancel STT
          completer.complete(null);
        }
      });

      return await completer.future;
    } catch (e) {
      print("[Confirm] ❌ Exception during STT for confirmation: $e");
      if (!completer.isCompleted) completer.complete(null);
      return null;
    } finally {
      // Ensure STT is stopped if it was listening
      if (_speech.isListening) {
        await _speech.stop();
      }
      // Reset listeners
      _speech.statusListener = null;
      _speech.errorListener = null;
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
    // Changed Future<bool?> to bool
    final negatives = [
      "no",
      "nope",
      "negative",
      "don't",
      "do not",
      "cancel",
      "stop"
    ];
    return negatives.any((word) => input.contains(word));
  }

  Future<String?> listenForRawSpeech(String prompt,
      {TtsPriority priority = TtsPriority.confirmation}) async {
    if (_isListeningForConfirmation) {
      // This flag indicates any STT listening by this handler
      print("[Confirm] Already listening. Aborting new raw speech request.");
      return null;
    }
    if (!_isInitialized) {
      print("[Confirm] ✗ STT not initialized. Cannot listen for raw speech.");
      // Consider speaking an error, or let the caller decide.
      // await _ttsService.speakAndWait("Speech input is not ready.", priority);
      return null;
    }

    _isListeningForConfirmation = true;

    // Speak the prompt
    _ttsService.stop(); // Stop any current TTS
    await Future.delayed(
        const Duration(milliseconds: 100)); // Allow TTS stop to propagate
    await _ttsService.speakAndWait(prompt, priority);
    // Add a small pause after TTS before listening, to ensure mic is ready and TTS fully stopped
    await Future.delayed(const Duration(milliseconds: 300));

    final completer = Completer<String?>();
    bool resultHandled = false;
    Timer? timeoutTimer;

    try {
      print("[Confirm] 🎤 Starting STT for raw speech input...");

      _speech.statusListener = (status) async {
        print("[Confirm] 📡 STT Status (Raw Speech): $status");
        if (status == "notListening" &&
            !resultHandled &&
            !completer.isCompleted) {
          // Delay slightly to catch very short utterances that might still be processing
          await Future.delayed(const Duration(milliseconds: 300));
          if (!resultHandled && !completer.isCompleted) {
            // Re-check
            resultHandled = true;
            print(
                "[Confirm] STT stopped without final result during raw speech listening (e.g., no input).");
            completer.complete(null);
          }
        }
      };

      _speech.errorListener = (errorNotification) {
        print(
            "[Confirm] STT Error (Raw Speech): ${errorNotification.errorMsg}");
        if (!resultHandled && !completer.isCompleted) {
          resultHandled = true;
          completer.complete(null); // Error occurred
        }
      };

      timeoutTimer = Timer(const Duration(seconds: 10), () {
        // Timeout for listening
        if (!resultHandled && !completer.isCompleted) {
          resultHandled = true;
          print(
              "[Confirm] ⏰ Timeout waiting for STT result in raw speech listening.");
          if (_speech.isListening) _speech.cancel(); // Attempt to cancel STT
          completer.complete(null);
        }
      });

      await _speech.listen(
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(
            seconds: 7), // Max time to listen for a single utterance
        onResult: (result) {
          print(
              "[Confirm] 📝 STT Result (Raw Speech): '${result.recognizedWords}' (final: ${result.finalResult})");
          if (result.finalResult && !resultHandled) {
            resultHandled = true;
            final transcript = result.recognizedWords.trim();
            if (transcript.isEmpty) {
              print("[Confirm] Empty transcript received.");
              completer.complete(null);
            } else {
              completer.complete(transcript);
            }
          }
        },
        // partialResults: false, // Depending on your needs
        // cancelOnError: true, // Depending on how you want to handle STT errors
      );

      return await completer.future;
    } catch (e) {
      print("[Confirm] ❌ Exception during STT for raw speech: $e");
      if (!completer.isCompleted) completer.complete(null);
      return null;
    } finally {
      timeoutTimer?.cancel();
      _isListeningForConfirmation = false; // Reset the flag
      if (_speech.isListening) {
        await _speech.stop();
      }
      // Important to clear listeners to prevent them from affecting subsequent STT sessions
      _speech.statusListener = null;
      _speech.errorListener = null;
      print("[Confirm] Finished STT for raw speech input.");
    }
  }
}
