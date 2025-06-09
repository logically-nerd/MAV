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

    // TTS init is likely already called by main or another service, but ensure it's ready.
    // await _ttsService.init(); // Assuming TTS is initialized globally once.
    await _confirmationHandler.preload();
    // NavigationHandler and SOSService preload if they have specific needs.
    // await _navigationHandler.preload();
    // await _sosService.preload();

    print(
        "[Conversation] ✓ ConversationService preloaded (dependent services should be preloaded elsewhere if needed)");
  }

  // This specific feedback function is removed as its logic is integrated into listenAndClassify
  // Future<void> _feedbackStart() async { ... }
  // Future<void> _feedbackStop() async { ... }

  Future<IntentResult?> listenAndClassify() async {
    if (_isListening) {
      print("[Conversation] Already listening. Ignoring.");
      return null;
    }

    _isListening = true;
    // Establish TTS block for the duration of the conversation.
    // Allow SOS, own conversation prompts, and confirmation prompts.
    _ttsService.blockAllExcept(
        [TtsPriority.sos, TtsPriority.conversation, TtsPriority.confirmation]);
    print(
        "[Conversation] TTS block active, allowing: SOS, Conversation, Confirmation");

    try {
      bool available = await _speech.initialize(
          onError: (error) => print("[STT] Error during init: $error"),
          onStatus: (status) => print("[STT] Status during init: $status"));
      print("[Conversation] STT available: $available");

      if (!available) {
        await _ttsService.speakAndWait(
            "Speech recognition not available.", TtsPriority.conversation);
        return null;
      }

      // Haptic feedback and stop any current TTS before speaking "Listening"
      HapticFeedback.heavyImpact();
      _ttsService.stop(); // Clear any ongoing TTS
      await Future.delayed(const Duration(
          milliseconds: 100)); // Short delay for TTS stop to take effect
      await _ttsService.speakAndWait("Listening", TtsPriority.conversation);
      print("[Conversation] ✓ 'Listening' speech completed, starting STT...");

      final completer = Completer<IntentResult?>();
      bool resultHandled = false;

      _speech.statusListener = (status) async {
        print("[STT] Status: $status");
        if (status == "notListening" &&
            !resultHandled &&
            !completer.isCompleted) {
          // Delay to ensure onResult might still fire if speech was very short
          await Future.delayed(const Duration(milliseconds: 300));
          if (!resultHandled && !completer.isCompleted) {
            // Re-check after delay
            resultHandled = true;
            print(
                "[Conversation] STT stopped without final result, assuming no input.");
            await _ttsService.speakAndWait(
                "Didn't catch anything.", TtsPriority.conversation);
            completer.complete(null);
          }
        }
      };

      _speech.errorListener = (errorNotification) {
        print("[STT] Error: ${errorNotification.errorMsg}");
        if (!resultHandled && !completer.isCompleted) {
          resultHandled = true;
          _ttsService.speakAndWait(
              "Speech recognition error.", TtsPriority.conversation);
          completer.complete(null);
        }
      };

      _speech.listen(
        pauseFor: const Duration(seconds: 4), // Slightly shorter pause
        listenFor: const Duration(seconds: 10), // Max listen duration
        onResult: (result) async {
          print(
              "[STT] Got result: ${result.recognizedWords}, final: ${result.finalResult}");
          if (result.finalResult && !resultHandled) {
            resultHandled = true;
            HapticFeedback
                .heavyImpact(); // Haptic feedback for recognized speech

            final transcript = result.recognizedWords.toLowerCase().trim();
            print("[Conversation] Final Transcript: $transcript");

            if (transcript.isEmpty) {
              await _ttsService.speakAndWait(
                  "No input detected.", TtsPriority.conversation);
              completer.complete(null);
              return;
            }
            // Process the intent. TTS unblocking will happen in the finally block.
            await _handleIntent(transcript, completer);
          }
        },
      );

      return await completer.future;
    } catch (e) {
      print("[Conversation] Error in listenAndClassify: $e");
      await _ttsService.speakAndWait(
          "An error occurred. Please try again.", TtsPriority.conversation);
      return null;
    } finally {
      _isListening = false;
      if (_speech.isListening) {
        _speech.stop();
      }
      _ttsService
          .unblockLowPriority(); // Lift the TTS block when conversation flow ends
      print("[Conversation] ✓ listenAndClassify finished, TTS unblocked");
    }
  }

  Future<void> _handleIntent(
      String transcript, Completer<IntentResult?> completer) async {
    // Prioritize SOS commands
    if (_matchesSOS(transcript)) {
      await _ttsService.speakAndWait(
          "Emergency detected. Calling emergency services.", TtsPriority.sos);
      await _sosService.triggerSOS();
      completer.complete(IntentResult(
          intent: IntentType.sos, raw: transcript)); // Return SOS intent
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
          completer.complete(null); // Or intent with null destination
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
          completer.complete(null); // Or intent with null destination
        }
        break;

      case IntentType.awareness:
        // ConfirmationHandler will use TtsPriority.confirmation, which is allowed by our current block.
        final confirmed = await _confirmationHandler.confirmAwareness();
        if (confirmed == true) {
          print("[Conversation] Awareness confirmed by user.");
          // AwarenessHandler.startAwarenessMode will manage its own TTS and specific blocking.
          // The block set by ConversationService will be overridden by AwarenessHandler's block,
          // and then restored (unblocked) when AwarenessHandler stops.
          await AwarenessHandler.instance.startAwarenessMode();
        } else if (confirmed == false) {
          print("[Conversation] Awareness canceled by user.");
          await _ttsService.speakAndWait(
              "Awareness check canceled.", TtsPriority.conversation);
        } else {
          // confirmed is null (no response / timeout in confirmation)
          print("[Conversation] Awareness confirmation unclear or timed out.");
          // ConfirmationHandler should have already provided feedback like "I didn't catch that."
        }
        completer
            .complete(intent); // Complete with the original awareness intent
        break;

      default: // IntentType.unknown
        await _ttsService.speakAndWait(
            "I'm not sure how to help with that. Try saying 'navigate to park' or 'what's around me'.",
            TtsPriority.conversation);
        completer.complete(intent); // Return unknown intent
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
    final patterns = [
      RegExp(
          r"(?:navigate to|go to|head to|take me to|let's go to|i want to go to|move to|get to|directions to|show me the way to|guide me to|i need to get to|walk to|walking directions to)\s+(.+)",
          caseSensitive: false),
      RegExp(r"find\s+(?:me\s+)?(?:a\s+route\s+to\s+|the\s+way\s+to\s+)?(.+)",
          caseSensitive: false),
      RegExp(r"how do i get to\s+(.+)", caseSensitive: false),
    ];

    for (final regex in patterns) {
      final match = regex.firstMatch(sentence);
      if (match != null && match.group(1) != null) {
        final destination = match.group(1)!.trim();
        if (destination.isNotEmpty) {
          print("[Conversation] Extracted destination: $destination");
          return destination;
        }
      }
    }
    print("[Conversation] No destination extracted from: $sentence");
    return null;
  }

  String? _extractChangeDestination(String sentence) {
    final patterns = [
      RegExp(
          r"(?:change destination to|change my destination to|redirect to|switch destination to|change route to|i changed my mind take me to|actually take me to|instead take me to|on second thought take me to|new destination is|new destination)\s+(.+)",
          caseSensitive: false),
      // Simpler patterns if the above are too specific
      RegExp(r"take me to\s+(.+)",
          caseSensitive: false), // Can be part of change
      RegExp(r"go to\s+(.+)", caseSensitive: false), // Can be part of change
    ];

    for (final regex in patterns) {
      final match = regex.firstMatch(sentence);
      if (match != null && match.group(1) != null) {
        final destination = match.group(1)!.trim();
        if (destination.isNotEmpty) {
          print("[Conversation] Extracted change destination: $destination");
          return destination;
        }
      }
    }
    // Fallback to general destination extraction if specific change phrases are not matched but navigation keywords are present
    if (_matchesNavigate(sentence)) {
      return _extractDestination(sentence);
    }
    print("[Conversation] No destination extracted for change from: $sentence");
    return null;
  }
}
