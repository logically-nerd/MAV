import 'dart:async';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'confirmation_handler.dart';
import 'navigation_handler.dart';
import 'sos_service.dart';

enum IntentType { navigate, awareness, sos, unknown }

class IntentResult {
  final IntentType intent;
  final String? destination;
  final String raw;

  IntentResult({required this.intent, this.destination, required this.raw});
}

class ConversationService {
  static final ConversationService instance = ConversationService._internal();
  factory ConversationService() => instance;

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final SOSService _sosService = SOSService.instance;
  final NavigationHandler _navigationHandler = NavigationHandler.instance;
  final ConfirmationHandler _confirmationHandler = ConfirmationHandler();

  bool _isListening = false;

  ConversationService._internal();

  Future<void> preload() async {
    print("[Conversation] Preloading speech services...");
    bool available = await _speech.initialize();
    print("[Conversation] Speech available: $available");

    _tts.setCompletionHandler(() => print("[TTS] Done speaking"));
    await _tts.awaitSpeakCompletion(true);

    // Preload other handlers
    await _confirmationHandler.preload();
    await _navigationHandler.preload();
    await _sosService.preload();

    print("[Conversation] All services initialized");
  }

  Future<void> _speak(String message) async {
    await _tts.stop();
    print("[TTS] Speaking: $message");
    await _tts.awaitSpeakCompletion(true);
    await _tts.speak(message);
    // Wait for TTS to complete with a proper delay
    try {
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print("[TTS] Error waiting for completion: $e");
    }
  }

  Future<void> _feedbackStart() async {
    HapticFeedback.heavyImpact();
    await _speak("Listening");
  }

  Future<void> _feedbackStop() async {
    HapticFeedback.heavyImpact();
  }

  Future<IntentResult?> listenAndClassify() async {
    if (_isListening) {
      print("[Conversation] Already listening. Ignoring.");
      return null;
    }

    _isListening = true;

    bool available = await _speech.initialize();
    print("[Conversation] STT available: $available");

    if (!available) {
      await _speak("Speech recognition not available.");
      _isListening = false;
      return null;
    }

    await _feedbackStart();
    await Future.delayed(const Duration(milliseconds: 300));

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
      // listenMode: stt.ListenMode.dictation,
      pauseFor: const Duration(seconds: 5),
      listenFor: const Duration(seconds: 12),
      onResult: (result) async {
        print("[STT] Got result: ${result.recognizedWords}");
        if (result.finalResult && !resultHandled) {
          resultHandled = true;
          await _feedbackStop();

          final transcript = result.recognizedWords.toLowerCase().trim();
          print("[Conversation] Final Transcript: $transcript");

          if (transcript.isEmpty) {
            await _speak("No input detected.");
            completer.complete(null);
            _isListening = false;
            return;
          }

          // Prioritize SOS commands
          if (_matchesSOS(transcript)) {
            await _sosService.triggerSOS();
            completer.complete(null);
            _isListening = false;
            return;
          }

          final intent = _classifyIntent(transcript);

          if (intent.intent == IntentType.navigate &&
              intent.destination != null) {
            // Handle navigation intent
            print(
                "[Conversation] Navigation intent detected with destination: ${intent.destination}");
            await _navigationHandler
                .handleNavigationRequest(intent.destination!);
            // Note: NavigationHandler will handle all navigation UI updates through callbacks

            completer.complete(intent);
            _isListening = false;
            return;
          } else if (intent.intent == IntentType.awareness) {
            // Handle awareness intent
            final confirmed = await _confirmationHandler.confirmAwareness();

            if (confirmed == true) {
              print("[Conversation] Awareness confirmed");
              await _speak("Getting surroundings information.");
              // Here you would call awareness service (not implemented yet)
            } else {
              print("[Conversation] Awareness canceled by user");
              await _speak("Awareness check canceled.");
            }

            completer.complete(intent);
            _isListening = false;
            return;
          }

          // If we got here, the intent is unknown or invalid
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
    print("[Conversation] Classifying: $sentence");
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

  bool _matchesSOS(String sentence) {
    const emergencyKeywords = [
      "help",
      "danger",
      "need help",
      "i need help",
      "help me",
      "i'm in danger",
      "emergency",
      "call 112",
      "emergency services",
      "urgent",
      "someone rescue me",
      "rescue me",
      "someone help me",
      "i'm lost",
      "i'm in trouble",
      "i need assistance",
      "save me"
    ];
    return emergencyKeywords.any((p) => sentence.contains(p));
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
    print("[Conversation] Extracted destination: ${match?.group(2)?.trim()}");
    return match?.group(2)?.trim();
  }
}
