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
  Function()? onNavigationStop; // New callback for stopping navigation

  // Property for tracking navigation state
  bool _currentlyNavigating = false;

  NavigationHandler._internal();

  Future<void> preload() async {
    print("[NavigationHandler] Preloading services...");

    bool available = await _speech.initialize();
    print("[NavigationHandler] STT available: $available");
  }

  Future<void> _speak(String message) async {
    print("[NavigationHandler] Speaking: $message");

    // Create a completer to wait for speech completion
    final completer = Completer<void>();

    _ttsService.speak(
        message,
        TtsPriority
            .conversation, // Use conversation priority for navigation instructions
        onComplete: () {
      completer.complete();
    });

    // Wait for speech to complete
    await completer.future;
  }

  // Register callback functions from map_screen
  void registerCallbacks({
    required Function(LatLng, String) onDestinationFound,
    required Function() onNavigationStart,
    required Function() onNavigationStop, // Add this parameter
  }) {
    print("[NavigationHandler] Registering callbacks");
    this.onDestinationFound = onDestinationFound;
    this.onNavigationStart = onNavigationStart;
    this.onNavigationStop = onNavigationStop;
  }

  // To check if callbacks are registered
  bool areCallbacksRegistered() {
    return onDestinationFound != null &&
        onNavigationStart != null &&
        onNavigationStop != null;
  }

  // Method for MapScreen to update navigation state
  void updateNavigationState(bool isNavigating) {
    _currentlyNavigating = isNavigating;
  }

  // Helper method to check if currently navigating
  bool _isCurrentlyNavigating() {
    return _currentlyNavigating;
  }

  // New method to stop navigation
  Future<bool> handleStopNavigation() async {
    print("[NavigationHandler] Processing request to stop navigation");

    if (!areCallbacksRegistered()) {
      print(
          "[NavigationHandler] No callbacks registered. Unable to stop navigation.");
      await _speak(
          "I'm not ready to handle navigation commands yet. Please try again in a moment.");
      return false;
    }

    // Call the navigation stop callback
    if (onNavigationStop != null) {
      print("[NavigationHandler] Stopping navigation");
      onNavigationStop!();
      await _speak("Navigation stopped");
      return true;
    }

    return false;
  }

  // New method to change destination
  Future<bool> handleChangeDestination(String newDestination) async {
    print(
        "[NavigationHandler] Processing request to change destination to: $newDestination");

    if (!areCallbacksRegistered()) {
      print(
          "[NavigationHandler] No callbacks registered. Unable to change destination.");
      await _speak(
          "I'm not ready to handle navigation commands yet. Please try again in a moment.");
      return false;
    }

    // Ask for confirmation
    await _speak("Do you want to change your destination to $newDestination?");
    final confirmed = await _listenForConfirmation();

    if (!confirmed) {
      print("[NavigationHandler] User declined to change destination");
      await _speak("Continuing with the current destination");
      return false;
    }

    // Stop current navigation
    if (onNavigationStop != null) {
      print(
          "[NavigationHandler] Stopping current navigation to change destination");
      onNavigationStop!();

      // Brief pause to allow the stop to complete
      await Future.delayed(Duration(milliseconds: 800));
    }

    // Start new navigation to the new destination
    return await handleNavigationRequest(newDestination);
  }

  // Main entry point for handling navigation requests
  Future<bool> handleNavigationRequest(String destination) async {
    print("[NavigationHandler] Processing navigation request to: $destination");

    // Check if callbacks are registered before proceeding
    if (!areCallbacksRegistered()) {
      print(
          "[NavigationHandler] No callbacks registered. Unable to proceed with navigation.");
      await _speak(
          "I'm not ready to navigate yet. Please try again in a moment.");
      return false;
    }

    // Check if already navigating and ask if we should change destination
    if (_isCurrentlyNavigating()) {
      print(
          "[NavigationHandler] Already navigating. Asking to change destination");
      await _speak(
          "You're already navigating. Do you want to change your destination to $destination instead?");
      final changeConfirmed = await _listenForConfirmation();

      if (!changeConfirmed) {
        print("[NavigationHandler] User declined to change destination");
        await _speak("Continuing with the current destination");
        return false;
      }

      // Stop the current navigation
      if (onNavigationStop != null) {
        print(
            "[NavigationHandler] Stopping current navigation to change destination");
        onNavigationStop!();

        // Brief pause to allow the stop to complete
        await Future.delayed(Duration(milliseconds: 800));
      }
    }

    await _speak("Looking for $destination");

    try {
      // Get current location
      final currentPosition = await MapService.getCurrentLocation();
      if (currentPosition == null) {
        print("[NavigationHandler] Failed to get current location");
        await _speak(
            "I couldn't determine your current location. Please try again by double tapping.");
        return false;
      }

      // Search for the destination
      final suggestions =
          await _searchDestination(destination, currentPosition);
      if (suggestions.isEmpty) {
        print("[NavigationHandler] No destinations found");
        await _speak(
            "I couldn't find $destination. Please try again with a different location by double tapping.");
        return false;
      }

      // Present top 3 options to user
      final selectedSuggestion = await _presentLocationOptions(suggestions);
      if (selectedSuggestion == null) {
        print("[NavigationHandler] User didn't select a destination");
        await _speak(
            "No destination selected. Please double tap to try again.");
        return false;
      }

      // Get details for the selected suggestion
      final destinationLocation =
          await _getDestinationLocation(selectedSuggestion.placeId);
      if (destinationLocation == null) {
        print("[NavigationHandler] Failed to get location details");
        await _speak(
            "I found $destination but couldn't get its location. Please double tap to try again.");
        return false;
      }

      // Calculate route
      final routeInfo =
          await _calculateRouteInfo(currentPosition, destinationLocation);
      if (routeInfo == null) {
        print("[NavigationHandler] Failed to calculate route");
        await _speak(
            "I couldn't calculate a route to $destination. Please double tap to try again.");
        return false;
      }

      // Check if destination is too far for walking
      if (routeInfo.distanceMeters > 20000) {
        print(
            "[NavigationHandler] Destination too far for walking: ${routeInfo.distanceMeters} meters");
        await _speak(
            "$destination is ${routeInfo.distance} away, which is too far to walk. Please choose a closer destination by double tapping.");
        return false;
      }

      // Ask user for confirmation
      final confirmed = await _confirmNavigation(
          selectedSuggestion.description
              .split('-')[0]
              .trim(), // Use just the name part
          routeInfo.distance,
          routeInfo.duration);

      if (!confirmed) {
        print("[NavigationHandler] Navigation canceled by user");
        await _speak("Navigation canceled. You can double tap to try again.");
        return false;
      }

      // Set the destination in the map screen
      if (onDestinationFound != null) {
        print("[NavigationHandler] Setting destination in map screen");
        onDestinationFound!(destinationLocation,
            selectedSuggestion.description.split('-')[0].trim());

        // Brief pause to allow map to update
        await Future.delayed(Duration(milliseconds: 800));

        // Start navigation
        if (onNavigationStart != null) {
          print("[NavigationHandler] Starting navigation");
          onNavigationStart!();
          updateNavigationState(true); // Update navigation state
          await _speak("Starting navigation to " +
              selectedSuggestion.description.split('-')[0].trim());
          return true;
        } else {
          print("[NavigationHandler] Navigation start callback is null");
        }
      } else {
        print(
            "[NavigationHandler] No callback registered for setting destination");
      }

      await _speak(
          "There was a problem starting navigation. Please double tap to try again.");
      return false;
    } catch (e) {
      print("[NavigationHandler] Error: $e");
      await _speak(
          "There was an error setting up navigation. Please double tap to try again.");
      return false;
    }
  }

  // Present multiple location options and let user choose
  Future<PlaceSuggestion?> _presentLocationOptions(
      List<PlaceSuggestion> suggestions) async {
    print(
        "[NavigationHandler] Presenting ${suggestions.length} location options");

    if (suggestions.isEmpty) {
      return null;
    }

    // If only one suggestion, ask if user wants to use it
    if (suggestions.length == 1) {
      final name = suggestions[0].description.split('-')[0].trim();
      await _speak(
          "I found one location: $name. Would you like to navigate there?");
      final confirmed = await _listenForConfirmation();
      return confirmed == true ? suggestions[0] : null;
    }

    // Limit to top 3 suggestions
    final topSuggestions = suggestions.take(3).toList();

    // Present options
    String optionsText = "I found multiple locations. ";
    for (int i = 0; i < topSuggestions.length; i++) {
      final name = topSuggestions[i].description.split('-')[0].trim();
      final distance = topSuggestions[i].distance;
      optionsText += "Option ${i + 1}: $name, $distance. ";
    }
    optionsText += "Which one would you like? Say the option number.";

    await _speak(optionsText);

    // Listen for user response
    return _listenForOptionSelection(topSuggestions);
  }

  // Listen for option selection (1, 2, or 3)
  Future<PlaceSuggestion?> _listenForOptionSelection(
      List<PlaceSuggestion> options) async {
    print("[NavigationHandler] Listening for option selection");

    try {
      bool available = await _speech.initialize();
      if (!available) {
        print("[NavigationHandler] Speech recognition not available");
        await _speak(
            "I couldn't access the microphone. Please double tap to try again.");
        return null;
      }

      Completer<PlaceSuggestion?> completer = Completer();
      bool hasResponse = false;

      _speech.listen(
        listenFor: Duration(seconds: 10),
        pauseFor: Duration(seconds: 5),
        onResult: (result) {
          if (result.finalResult && !hasResponse) {
            hasResponse = true;
            final text = result.recognizedWords.toLowerCase();
            print("[NavigationHandler] User said: $text");

            // Try to extract a number
            PlaceSuggestion? selected;

            if (text.contains("first") ||
                text.contains("one") ||
                text.contains("1")) {
              selected = options.isNotEmpty ? options[0] : null;
            } else if (text.contains("second") ||
                text.contains("two") ||
                text.contains("2")) {
              selected = options.length > 1 ? options[1] : null;
            } else if (text.contains("third") ||
                text.contains("three") ||
                text.contains("3")) {
              selected = options.length > 2 ? options[2] : null;
            }

            if (selected != null) {
              print(
                  "[NavigationHandler] Selected option: ${selected.description}");
              final name = selected.description.split('-')[0].trim();
              _speak("You selected $name.");
              completer.complete(selected);
            } else {
              print("[NavigationHandler] Couldn't determine selected option");
              _speak(
                  "I didn't understand which option you wanted. Please double tap to try again.");
              completer.complete(null);
            }
          }
        },
      );

      // Set timeout
      Future.delayed(Duration(seconds: 12), () {
        if (!hasResponse && !completer.isCompleted) {
          hasResponse = true;
          print("[NavigationHandler] Option selection timed out");
          _speak(
              "I didn't hear your selection. Please double tap to try again.");
          completer.complete(null);
        }
      });

      return completer.future;
    } catch (e) {
      print("[NavigationHandler] Error during option selection: $e");
      await _speak("There was an error. Please double tap to try again.");
      return null;
    }
  }

  // Search for destination using MapService
  Future<List<PlaceSuggestion>> _searchDestination(
      String query, LatLng currentLocation) async {
    print("[NavigationHandler] Searching for '$query'");
    try {
      final suggestions =
          await MapService.getPlaceSuggestions(query, currentLocation);
      print("[NavigationHandler] Found ${suggestions.length} suggestions");
      return suggestions;
    } catch (e) {
      print("[NavigationHandler] Error searching for destination: $e");
      return [];
    }
  }

  // Get location details for a place
  Future<LatLng?> _getDestinationLocation(String placeId) async {
    print("[NavigationHandler] Getting location for place ID: $placeId");
    try {
      return await MapService.getPlaceDetails(placeId);
    } catch (e) {
      print("[NavigationHandler] Error getting place details: $e");
      return null;
    }
  }

  // Calculate route information
  Future<_RouteInfo?> _calculateRouteInfo(
      LatLng origin, LatLng destination) async {
    print("[NavigationHandler] Calculating route from $origin to $destination");
    try {
      // Get route steps
      final steps = await MapService.getNavigationSteps(
          origin: origin, destination: destination);

      if (steps.isEmpty) {
        print("[NavigationHandler] No steps returned for route");
        return null;
      }

      // Calculate total distance and duration
      int totalDistance = 0;
      int totalDuration = 0;

      for (var step in steps) {
        totalDistance += step.distanceValue;
        totalDuration +=
            step.durationValue ?? 0; // Use durationValue if available
      }

      // If duration data is missing, calculate based on average walking speed
      if (totalDuration == 0) {
        // Average walking speed ~ 5 km/h = 1.38 m/s
        totalDuration = (totalDistance / 1.38).round();
      }

      // Format distance
      final distance = MapService.formatDistance(totalDistance.toDouble());

      // Format duration properly
      final String duration = _formatDuration(totalDuration);

      print(
          "[NavigationHandler] Route calculated: $distance, $duration (${totalDuration}s)");
      return _RouteInfo(
        distance: distance,
        duration: duration,
        steps: steps.length,
        distanceMeters: totalDistance.toDouble(),
        durationSeconds: totalDuration,
      );
    } catch (e) {
      print("[NavigationHandler] Error calculating route: $e");
      return null;
    }
  }

  // Format duration in seconds to human-readable format
  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return "less than a minute";
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).round();
      return "$minutes ${minutes == 1 ? 'minute' : 'minutes'}";
    } else {
      final hours = (seconds / 3600).floor();
      final minutes = ((seconds % 3600) / 60).round();

      if (minutes == 0) {
        return "$hours ${hours == 1 ? 'hour' : 'hours'}";
      } else {
        return "$hours ${hours == 1 ? 'hour' : 'hours'} $minutes ${minutes == 1 ? 'minute' : 'minutes'}";
      }
    }
  }

  // Confirm navigation with user
  Future<bool> _confirmNavigation(
      String destination, String distance, String duration) async {
    print("[NavigationHandler] Asking for navigation confirmation");
    await _speak(
        "I found $destination. It's about $distance away and will take approximately $duration to walk there. Should I start navigation?");

    return _listenForConfirmation();
  }

  // Listen for user confirmation
  Future<bool> _listenForConfirmation() async {
    print("[NavigationHandler] Listening for confirmation");
    int attempts = 0;

    while (attempts < 2) {
      attempts++;

      try {
        bool available = await _speech.initialize();
        if (!available) {
          print("[NavigationHandler] Speech recognition not available");
          if (attempts < 2) {
            await _speak("I couldn't hear you. Please say yes or no.");
          } else {
            await _speak(
                "I'm still having trouble hearing you. Please double tap to try again.");
          }
          continue;
        }

        Completer<bool?> completer = Completer();
        bool hasResponse = false;

        _speech.listen(
          listenFor: Duration(seconds: 8),
          pauseFor: Duration(seconds: 4),
          onResult: (result) {
            if (result.finalResult && !hasResponse) {
              hasResponse = true;
              final text = result.recognizedWords.toLowerCase();
              print("[NavigationHandler] User said: $text");

              if (_isAffirmative(text)) {
                print("[NavigationHandler] User confirmed");
                completer.complete(true);
              } else if (_isNegative(text)) {
                print("[NavigationHandler] User declined");
                completer.complete(false);
              } else {
                print("[NavigationHandler] Unclear response");
                completer.complete(null);
              }
            }
          },
        );

        // Set timeout
        Future.delayed(Duration(seconds: 10), () {
          if (!hasResponse && !completer.isCompleted) {
            hasResponse = true;
            print("[NavigationHandler] Confirmation timed out");
            completer.complete(null);
          }
        });

        final result = await completer.future;

        if (result != null) {
          return result;
        } else if (attempts < 2) {
          await _speak("I didn't catch that. Please say yes or no.");
        } else {
          await _speak(
              "I still didn't understand. Please double tap to try again when you're ready.");
          return false;
        }
      } catch (e) {
        print("[NavigationHandler] Error during confirmation: $e");
        if (attempts < 2) {
          await _speak("There was an error. Please try again.");
        } else {
          await _speak(
              "I'm having trouble with speech recognition. Please double tap to try again.");
          return false;
        }
      }
    }

    return false;
  }

  bool _isAffirmative(String input) => [
        "yes",
        "yeah",
        "sure",
        "okay",
        "ok",
        "go ahead",
        "start",
        "navigate",
        "proceed",
        "correct",
        "right",
        "please",
        "do it",
        "absolutely",
        "confirm",
        "affirmative",
        "let's go"
      ].any((w) => input.contains(w));

  bool _isNegative(String input) => [
        "no",
        "nope",
        "nah",
        "don't",
        "stop",
        "cancel",
        "incorrect",
        "wrong",
        "not now",
        "later",
        "wait",
        "negative",
        "decline"
      ].any((w) => input.contains(w));
}

// Helper class for route information
class _RouteInfo {
  final String distance;
  final String duration;
  final int steps;
  final double distanceMeters;
  final int durationSeconds;

  _RouteInfo({
    required this.distance,
    required this.duration,
    required this.steps,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}
