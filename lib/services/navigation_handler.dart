import 'dart:async';
import 'package:flutter/material.dart';
import 'tts_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_service.dart';
import 'conversation_service/confirmation_handler.dart';

class NavigationHandler {
  static final NavigationHandler instance = NavigationHandler._internal();
  factory NavigationHandler() => instance;

  final TtsService _ttsService = TtsService.instance;
  final ConfirmationHandler _confirmationHandler = ConfirmationHandler();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Callbacks for map_screen
  Function(LatLng, String)? onDestinationFound;
  Function()? onNavigationStart;
  Function()? onNavigationStop;

  bool _currentlyNavigating = false;

  NavigationHandler._internal();

  Future<void> preload() async {
    print("[NavigationHandler] Preloading services...");
    await _confirmationHandler.preload();
    print("[NavigationHandler] Services preloaded");
  }

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
      // Use the centralized confirmation handler (already uses confirmation priority)
      final confirmed =
          await _confirmationHandler.confirmDestination(destination);

      if (confirmed == true) {
        print("[NavigationHandler] User confirmed navigation");

        // Search for the destination
        final currentLocation = await MapService.getCurrentLocation();
        if (currentLocation != null) {
          print("[NavigationHandler] Current location: $currentLocation");

          // Get quick suggestions first
          final suggestions = await MapService.getPlaceSuggestions(
              destination, currentLocation);
          print("[NavigationHandler] Got ${suggestions.length} suggestions");

          if (suggestions.isNotEmpty) {
            final bestMatch = suggestions.first;
            print("[NavigationHandler] Selected: ${bestMatch.name}");

            // Get detailed info with distance calculation
            final detailedPlace = await MapService.getPlaceDetailsWithDistance(
                bestMatch.placeId, currentLocation);

            if (detailedPlace != null) {
              // Check if the destination is too far (beyond 10km)
              if (detailedPlace.distanceInMeters > 10000) {
                await _ttsService.speakAndWait(
                  "The destination $destination is ${detailedPlace.distance} away, which is very far. Please choose a closer location within 10 kilometers.",
                  TtsPriority.conversation, // Keep as conversation
                );
                return;
              }

              // Get coordinates for navigation
              final location =
                  await MapService.getPlaceDetails(bestMatch.placeId);

              if (location != null) {
                await _ttsService.speakAndWait(
                  "Starting navigation to $destination, which is ${detailedPlace.distance} away",
                  TtsPriority.conversation, // Keep as conversation
                );

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
                await _ttsService.speakAndWait(
                  "Sorry, I couldn't find the exact location for $destination",
                  TtsPriority.conversation,
                );
              }
            } else {
              await _ttsService.speakAndWait(
                "The destination $destination is too far away. Please choose a location within 10 kilometers.",
                TtsPriority.conversation,
              );
            }
          } else {
            print("[NavigationHandler] No suggestions found!");
            await _ttsService.speakAndWait(
              "Sorry, I couldn't find $destination. Please try a different location.",
              TtsPriority.conversation,
            );
          }
        } else {
          await _ttsService.speakAndWait(
            "I can't access your location. Please check location permissions.",
            TtsPriority.conversation,
          );
        }
      } else if (confirmed == false) {
        await _ttsService.speakAndWait(
            "Navigation cancelled.", TtsPriority.conversation);
      } else {
        await _ttsService.speakAndWait(
          "I didn't understand your response. Please try again.",
          TtsPriority.conversation,
        );
      }
    } catch (e) {
      print("[NavigationHandler] Error: $e");
      await _ttsService.speakAndWait(
        "Sorry, there was an error. Please try again.",
        TtsPriority.conversation,
      );
    }
  }

  Future<void> handleStopNavigation() async {
    print("[NavigationHandler] Handling stop navigation");
    await _ttsService.speakAndWait(
        "Stopping navigation.", TtsPriority.conversation);

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

  void updateNavigationState(bool isNavigating) {
    _currentlyNavigating = isNavigating;
    print("[NavigationHandler] Navigation state updated: $isNavigating");
  }

  bool get isNavigating => _currentlyNavigating;
}
