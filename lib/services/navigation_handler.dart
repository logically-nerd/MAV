import 'dart:async';
import 'package:flutter/material.dart';
import 'tts_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'map_service.dart';

class NavigationHandler {
  static final NavigationHandler instance = NavigationHandler._internal();
  factory NavigationHandler() => instance;

  final TtsService _ttsService = TtsService.instance;
  final stt.SpeechToText _speech = stt.SpeechToText();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Callback for updating destination in map_screen
  Function(LatLng, String)? onDestinationFound;
  Function()? onNavigationStart;
  Function()? onNavigationStop;

  // Property for tracking navigation state
  bool _currentlyNavigating = false;

  NavigationHandler._internal();

  Future<void> preload() async {
    print("[NavigationHandler] Preloading STT...");
    try {
      bool available = await _speech.initialize(
        onError: (error) => print("[NavigationHandler] STT Error: $error"),
        onStatus: (status) => print("[NavigationHandler] STT Status: $status"),
      );
      print("[NavigationHandler] STT Available: $available");
    } catch (e) {
      print("[NavigationHandler] STT initialization failed: $e");
    }
  }

  Future<void> _speak(String message) async {
    print("[NavigationHandler] Speaking: $message");
    Completer<void> completer = Completer<void>();

    _ttsService.speak(
      message,
      TtsPriority.conversation,
      onComplete: () => completer.complete(),
    );

    await completer.future;
  }

  // Register callback functions from map_screen
  void registerCallbacks({
    Function(LatLng, String)? onDestinationFound,
    Function()? onNavigationStart,
    Function()? onNavigationStop,
  }) {
    this.onDestinationFound = onDestinationFound;
    this.onNavigationStart = onNavigationStart;
    this.onNavigationStop = onNavigationStop;
    print("[NavigationHandler] Callbacks registered successfully");
  }

  Future<void> handleNavigationRequest(String destination) async {
    print("[NavigationHandler] Handling navigation request to: $destination");

    try {
      // Ask for confirmation
      final confirmed = await _askForConfirmation(
          "You said navigate to $destination. Should I go ahead?");

      if (confirmed == true) {
        print("[NavigationHandler] User confirmed navigation");

        // Search for the destination
        final currentLocation = await MapService.getCurrentLocation();
        if (currentLocation != null) {
          final suggestions = await MapService.getPlaceSuggestions(
              destination, currentLocation);

          if (suggestions.isNotEmpty) {
            final bestMatch = suggestions.first;
            final location =
                await MapService.getPlaceDetails(bestMatch.placeId);

            if (location != null) {
              await _speak("Starting navigation to $destination");

              // Call the callback to update the map
              if (onDestinationFound != null) {
                onDestinationFound!(location, destination);
              }

              // Wait a moment for the route to load
              await Future.delayed(const Duration(seconds: 2));

              // Start navigation
              if (onNavigationStart != null) {
                onNavigationStart!();
              }
            } else {
              await _speak(
                  "Sorry, I couldn't find the exact location for $destination");
            }
          } else {
            await _speak(
                "Sorry, I couldn't find $destination. Please try a different location.");
          }
        } else {
          await _speak(
              "I can't access your location. Please check location permissions.");
        }
      } else if (confirmed == false) {
        await _speak("Navigation cancelled.");
      } else {
        await _speak("I didn't understand your response. Please try again.");
      }
    } catch (e) {
      print("[NavigationHandler] Error: $e");
      await _speak("Sorry, there was an error. Please try again.");
    }
  }

  Future<void> handleStopNavigation() async {
    print("[NavigationHandler] Handling stop navigation");
    await _speak("Stopping navigation.");

    if (onNavigationStop != null) {
      onNavigationStop!();
    }

    _currentlyNavigating = false;
  }

  Future<void> handleChangeDestination(String newDestination) async {
    print(
        "[NavigationHandler] Handling change destination to: $newDestination");

    // Stop current navigation first
    await handleStopNavigation();

    // Start new navigation
    await handleNavigationRequest(newDestination);
  }

  Future<bool?> _askForConfirmation(String question) async {
    print("[NavigationHandler] Asking: $question");

    Completer<bool?> completer = Completer();
    bool isListening = false;

    try {
      // Speak the question first
      await _speak(question);

      // Small delay before starting to listen
      await Future.delayed(const Duration(milliseconds: 500));

      print("[NavigationHandler] Starting to listen for confirmation...");

      isListening = await _speech.listen(
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 8),
        onResult: (result) {
          print(
              "[NavigationHandler] STT Result: '${result.recognizedWords}' (final: ${result.finalResult})");

          if (result.finalResult && !completer.isCompleted) {
            final transcript = result.recognizedWords.toLowerCase().trim();

            if (_isAffirmative(transcript)) {
              completer.complete(true);
            } else if (_isNegative(transcript)) {
              completer.complete(false);
            } else {
              completer.complete(null);
            }
          }
        },
      );

      if (!isListening) {
        print("[NavigationHandler] Failed to start listening");
        completer.complete(null);
      }

      // Timeout
      Timer(const Duration(seconds: 10), () {
        if (!completer.isCompleted) {
          print("[NavigationHandler] Confirmation timeout");
          _speech.stop();
          completer.complete(null);
        }
      });
    } catch (e) {
      print("[NavigationHandler] Error during confirmation: $e");
      completer.complete(null);
    }

    final result = await completer.future;

    if (isListening) {
      await _speech.stop();
    }

    print("[NavigationHandler] Confirmation result: $result");
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
      "true"
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
      "don't",
      "negative",
      "wrong",
      "incorrect"
    ];
    return negatives.any((word) => input.contains(word));
  }

  void updateNavigationState(bool isNavigating) {
    _currentlyNavigating = isNavigating;
    print("[NavigationHandler] Navigation state updated: $isNavigating");
  }

  bool get isNavigating => _currentlyNavigating;
}
