import 'dart:async';
import 'package:MAV/services/surrounding_awareness/awareness_handler.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../tts_service.dart';
import 'confirmation_handler.dart';
import '../navigation_handler.dart';
import '../sos_service.dart';
 // Import the awareness handler

enum IntentType {
  navigate,
  awareness,
  sos,
  stopNavigation,
  changeDestination,
  unknown
}

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
  final TtsService _ttsService = TtsService.instance;
  final SOSService _sosService = SOSService.instance;
  final NavigationHandler _navigationHandler = NavigationHandler.instance;
  final ConfirmationHandler _confirmationHandler = ConfirmationHandler();

  bool _isListening = false;
  ConversationService._internal();

  Future<void> preload() async {
    print("[Conversation] Preloading speech services...");
    bool available = await _speech.initialize();
    print("[Conversation] Speech available: $available");

    await _ttsService.init();
    await _confirmationHandler.preload();
    await _navigationHandler.preload();
    await _sosService.preload();

    print("[Conversation] ✓ All services initialized");
  }

  Future<void> _feedbackStart() async {
    HapticFeedback.heavyImpact();
    // Block lower priority TTS before starting
    _ttsService.stop();
    // Small delay to ensure TTS cleanup
    await Future.delayed(Duration(milliseconds: 200));

    _ttsService.blockLowPriority();

    // Wait for any current speech to complete before STT
    // while (_ttsService.isSpeaking) {
    //   print("[Conversation] Waiting for TTS to complete before STT...");
    //   await Future.delayed(Duration(milliseconds: 100));
    // }
    // Use speakAndWait to ensure "Listening" completes before STT starts
    await _ttsService.speakAndWait("Listening", TtsPriority.conversation);
    print("[Conversation] ✓ 'Listening' speech completed");
  }

  Future<void> _feedbackStop() async {
    HapticFeedback.heavyImpact();
    _ttsService.unblockLowPriority();
    print("[Conversation] ✓ Feedback ended, TTS unblocked");
  }

  Future<IntentResult?> listenAndClassify() async {
    if (_isListening) {
      print("[Conversation] Already listening. Ignoring.");
      return null;
    }

    _isListening = true;

    try {
      bool available = await _speech.initialize();
      print("[Conversation] STT available: $available");

      if (!available) {
        await _ttsService.speakAndWait(
            "Speech recognition not available.", TtsPriority.conversation);
        return null;
      }

      // Speak "Listening" and wait for completion
      await _feedbackStart();
      print("[Conversation] ✓ Feedback completed, starting STT...");

      final completer = Completer<IntentResult?>();
      bool resultHandled = false;

      _speech.statusListener = (status) async {
        print("[STT] Status: $status");

        if (status == "notListening" &&
            !resultHandled &&
            !completer.isCompleted) {
          await Future.delayed(Duration(milliseconds: 500));
          if (!resultHandled && !completer.isCompleted) {
            resultHandled = true;
            await _ttsService.speakAndWait(
                "Didn't catch anything.", TtsPriority.conversation);
            completer.complete(null);
          }
        }
      };

      _speech.listen(
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
              await _ttsService.speakAndWait(
                  "No input detected.", TtsPriority.conversation);
              completer.complete(null);
              return;
            }

            // Handle different intents
            await _handleIntent(transcript, completer);
          }
        },
      );

      return await completer.future;
    } finally {
      _isListening = false;
    }
  }

  Future<void> _handleIntent(
      String transcript, Completer<IntentResult?> completer) async {
    // Prioritize SOS commands
    if (_matchesSOS(transcript)) {
      await _ttsService.speakAndWait(
          "Emergency detected. Calling emergency services.", TtsPriority.sos);
      await _sosService.triggerSOS();
      completer.complete(null);
      return;
    }

    final intent = _classifyIntent(transcript);

    switch (intent.intent) {
      case IntentType.stopNavigation:
        print("[Conversation] Stop navigation intent detected");
        await _navigationHandler.handleStopNavigation();
        completer.complete(intent);
        break;

      case IntentType.changeDestination:
        if (intent.destination != null) {
          print(
              "[Conversation] Change destination intent detected: ${intent.destination}");
          await _navigationHandler.handleChangeDestination(intent.destination!);
          completer.complete(intent);
        } else {
          await _ttsService.speakAndWait(
              "Where would you like to go instead?", TtsPriority.conversation);
          completer.complete(null);
        }
        break;

      case IntentType.navigate:
        if (intent.destination != null) {
          print(
              "[Conversation] Navigation intent detected with destination: ${intent.destination}");
          await _navigationHandler.handleNavigationRequest(intent.destination!);
          completer.complete(intent);
        } else {
          await _ttsService.speakAndWait(
              "Where would you like to navigate to?", TtsPriority.conversation);
          completer.complete(null);
        }
        break;

      case IntentType.awareness:
        final confirmed = await _confirmationHandler.confirmAwareness();
        if (confirmed == true) {
          print("[Conversation] Awareness confirmed");
          // await _ttsService.speakAndWait(
          //     "Starting awareness mode", TtsPriority.conversation);
          await AwarenessHandler.instance.startAwarenessMode();
        } else {
          print("[Conversation] Awareness canceled by user");
          await _ttsService.speakAndWait(
              "Awareness check canceled.", TtsPriority.conversation);
        }
        completer.complete(intent);
        break;

      default:
        await _ttsService.speakAndWait(
            "Try saying 'navigate to park' or 'what's around me'.",
            TtsPriority.conversation);
        completer.complete(null);
    }
  }

  IntentResult _classifyIntent(String sentence) {
    print("[Conversation] Classifying: $sentence");

    if (_matchesStopNavigation(sentence)) {
      return IntentResult(intent: IntentType.stopNavigation, raw: sentence);
    } else if (_matchesChangeDestination(sentence)) {
      final destination = _extractChangeDestination(sentence);
      return IntentResult(
        intent: IntentType.changeDestination,
        destination: destination,
        raw: sentence,
      );
    } else if (_matchesAwareness(sentence)) {
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
      "get to",
      "directions to",
      "show me the way to",
      "find",
      "find me",
      "how do i get to",
      "guide me to",
      "i need to get to",
      "walk to",
      "walking directions to",
      "help me find",
    ];
    return keywords.any((k) => sentence.contains(k));
  }

  bool _matchesStopNavigation(String sentence) {
    const patterns = [
      "stop navigation",
      "stop navigating",
      "cancel navigation",
      "end navigation",
      "stop directions",
      "cancel directions",
      "stop route",
      "cancel route",
      "exit navigation",
      "quit navigation",
      "terminate navigation"
    ];
    return patterns.any((p) => sentence.contains(p));
  }

  bool _matchesChangeDestination(String sentence) {
    const patterns = [
      "change destination",
      "change my destination",
      "navigate to a different",
      "go to a different",
      "switch destination",
      "redirect to",
      "take me somewhere else",
      "take me to a different",
      "i want to go somewhere else",
      "navigate elsewhere",
      "change route to",
      "i changed my mind take me to",
      "i want to go to another place",
      "change to",
      "go somewhere else",
      "let's go somewhere else",
      "actually take me to",
      "actually i want to go to",
      "instead take me to",
      "on second thought take me to",
      "new destination",
    ];
    return patterns.any((p) => sentence.contains(p));
  }

  String? _extractDestination(String sentence) {
    final regex = RegExp(
      r"(navigate to|go to|head to|take me to|let's go to|i want to go to|move to|get to)\s+(.*)",
    );
    final match = regex.firstMatch(sentence);
    print("[Conversation] Extracted destination: ${match?.group(2)?.trim()}");
    return match?.group(2)?.trim();
  }

  String? _extractChangeDestination(String sentence) {
    final regex = RegExp(
      r"(change destination to|change my destination to|redirect to|switch destination to|change route to|take me to|i changed my mind take me to|actually take me to|instead take me to|on second thought take me to|new destination)\s+(.*)",
    );
    final match = regex.firstMatch(sentence);
    if (match != null) {
      return match.group(2)?.trim();
    }
    return _extractDestination(sentence);
  }
}
