import 'dart:async';
import 'package:flutter/material.dart';
import 'tts_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_service.dart';
import 'conversation_service/confirmation_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

        // Add a TTS message to inform user we're searching
        await _ttsService.speakAndWait(
          "Searching for $destination...",
          TtsPriority.conversation,
        );

        // Search for the destination
        final currentLocation = await MapService.getCurrentLocation();
        if (currentLocation != null) {
          print("[NavigationHandler] Current location: $currentLocation");

          // Get 3 suggestions first
          final suggestions = await MapService.getPlaceSuggestions(
              destination, currentLocation);
          print("[NavigationHandler] Got ${suggestions.length} suggestions");

          if (suggestions.isNotEmpty) {
            PlaceSuggestion? selectedPlace;

            // ALWAYS present options to user - even if only 1 result
            if (suggestions.length == 1) {
              // Even with 1 option, let user confirm
              await _ttsService.speakAndWait(
                "I found one option: ${suggestions.first.name} at ${suggestions.first.distance}. Do you want to navigate there?",
                TtsPriority.confirmation,
              );
              // Add proper delay AFTER TTS completes
              print(
                  "[NavigationHandler] ⏱️ Pausing after TTS before confirmation...");
              await Future.delayed(Duration(milliseconds: 1500));
              print(
                  "[NavigationHandler] ⏱️ Pause complete, starting confirmation...");

              final userConfirmed =
                  await _confirmationHandler.confirmAwareness();
              if (userConfirmed == true) {
                selectedPlace = suggestions.first;
                await _ttsService.speakAndWait(
                  "Proceeding with navigation to ${selectedPlace.name}.",
                  TtsPriority.conversation,
                );
              } else {
                await _ttsService.speakAndWait(
                  "Navigation cancelled.",
                  TtsPriority.conversation,
                );
                return;
              }
            } else {
              // Multiple options - let user choose
              selectedPlace = await _presentPlaceOptions(suggestions);
            }

            if (selectedPlace != null) {
              // Check if the selected place is too far (beyond 10km)
              if (selectedPlace.distanceInMeters > 10000) {
                await _ttsService.speakAndWait(
                  "The destination ${selectedPlace.name} is ${selectedPlace.distance} away, which is very far. Please choose a closer location within 10 kilometers.",
                  TtsPriority.conversation,
                );
                return;
              }

              // Get coordinates for navigation
              final location =
                  await MapService.getPlaceDetails(selectedPlace.placeId);

              if (location != null) {
                String confirmationText =
                    "Starting navigation to ${selectedPlace.name}";
                if (selectedPlace.distance.isNotEmpty) {
                  confirmationText +=
                      ", which is ${selectedPlace.distance} away";
                }

                await _ttsService.speakAndWait(
                    confirmationText, TtsPriority.conversation);

                // Call the callback to update the map
                if (onDestinationFound != null) {
                  onDestinationFound!(location, selectedPlace.name);
                }

                // Wait a moment for the route to load
                await Future.delayed(const Duration(seconds: 2));

                // Start navigation
                if (onNavigationStart != null) {
                  onNavigationStart!();
                }
              } else {
                await _ttsService.speakAndWait(
                  "Sorry, I couldn't find the exact location for ${selectedPlace.name}",
                  TtsPriority.conversation,
                );
              }
            } else {
              await _ttsService.speakAndWait(
                "No destination selected. Navigation cancelled.",
                TtsPriority.conversation,
              );
            }
          } else {
            print("[NavigationHandler] No suggestions found!");
            await _ttsService.speakAndWait(
              "Sorry, I couldn't find $destination within 10 kilometers. Please try a different location.",
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
      }
    } catch (e) {
      print("[NavigationHandler] Error: $e");
      await _ttsService.speakAndWait(
        "Sorry, there was an error. Please try again.",
        TtsPriority.conversation,
      );
    }
  }

  /// Present place options to user and get their selection
  Future<PlaceSuggestion?> _presentPlaceOptions(
      List<PlaceSuggestion> suggestions) async {
    try {
      // Build the options announcement - WITHOUT the "Please say the number" part
      String optionsListText = "I found ${suggestions.length} options: ";

      for (int i = 0; i < suggestions.length; i++) {
        optionsListText += "${i + 1}. ${suggestions[i].name}";
        if (suggestions[i].distance.isNotEmpty) {
          optionsListText += " at ${suggestions[i].distance}";
        }

        if (i < suggestions.length - 1) {
          optionsListText += ", ";
        } else {
          optionsListText += "."; // End the list here
        }
      }
      // Announce the options list
      await _ttsService.speakAndWait(optionsListText,
          TtsPriority.conversation); // Use conversation priority for listing

      // Add a pause before asking for choice to ensure TTS is completely finished
      print("[NavigationHandler] ⏱️ Pausing after speaking options list...");
      await Future.delayed(Duration(milliseconds: 500)); // Adjusted pause
      print(
          "[NavigationHandler] ⏱️ Pause complete, proceeding to listen for choice...");

      // Listen for user's choice (this will now handle its own prompt)
      final selectedIndex = await _listenForNumberChoice(suggestions.length);

      if (selectedIndex != null &&
          selectedIndex >= 0 &&
          selectedIndex < suggestions.length) {
        final selectedPlace = suggestions[selectedIndex];

        // Confirmation of selection can be part of starting navigation
        // await _ttsService.speakAndWait(
        //   "You selected ${selectedPlace.name}. Proceeding with navigation.",
        //   TtsPriority.conversation,
        // );

        return selectedPlace;
      } else {
        await _ttsService.speakAndWait(
          "No valid choice made. Using the nearest option: ${suggestions.first.name}.",
          TtsPriority.conversation,
        );
        return suggestions.first; // Default to nearest
      }
    } catch (e) {
      print("[NavigationHandler] Error in place selection: $e");
      await _ttsService.speakAndWait(
        "Error in selection. Using the nearest option: ${suggestions.first.name}.",
        TtsPriority.conversation,
      );
      return suggestions.first; // Default to nearest
    }
  }

  Future<int?> _listenForNumberChoice(int maxOptions) async {
    try {
      print(
          "[NavigationHandler] 🎤 Requesting number choice (max: $maxOptions)");

      String promptForNumberChoice =
          "Please say the number of your choice, from 1 to $maxOptions.";

      // Use ConfirmationHandler to speak the prompt and listen for raw speech
      final spokenText = await _confirmationHandler.listenForRawSpeech(
          promptForNumberChoice,
          priority: TtsPriority.confirmation // This prompt is a direct question
          );

      if (spokenText != null && spokenText.isNotEmpty) {
        print(
            "[NavigationHandler] 🎯 Received raw speech for number choice: '$spokenText'");
        int? choice = _parseSpokenNumber(spokenText, maxOptions);
        print("[NavigationHandler] 🔢 Parsed choice: $choice");
        return choice;
      } else {
        print(
            "[NavigationHandler] 🛑 No speech received or empty for number choice.");
        // TTS feedback for no choice is handled by _presentPlaceOptions or the caller
        return null;
      }
    } catch (e) {
      print("[NavigationHandler] ❌ Error in number choice listening: $e");
      // TTS feedback for error is handled by _presentPlaceOptions or the caller
      return null;
    }
  }

  /// Parse spoken text to extract number choice
  int? _parseSpokenNumber(String spokenText, int maxOptions) {
    if (spokenText.isEmpty) {
      print("[NavigationHandler] ❌ Empty spoken text");
      return null;
    }

    try {
      print(
          "[NavigationHandler] 🔍 Parsing: '$spokenText' (max options: $maxOptions)");

      // Clean up text and convert to lowercase
      String cleanText = spokenText
          .toLowerCase()
          .replaceAll(
              RegExp(
                  r'\b(option|number|choice|select|go|to|the|please|i|want|choose|pick|say|like)\b'),
              '')
          .replaceAll(RegExp(r'[,.?!]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      print("[NavigationHandler] 🧹 Cleaned text: '$cleanText'");

      // First option patterns (index 0)
      if (RegExp(
              r'\b(1|one|first|1st|number one|option one|first option|first choice)\b')
          .hasMatch(cleanText)) {
        print("[NavigationHandler] ✅ Matched first option");
        return 0;
      }

      // Second option patterns (index 1)
      if (maxOptions > 1 &&
          RegExp(r'\b(2|two|second|2nd|number two|option two|second option|second choice)\b')
              .hasMatch(cleanText)) {
        print("[NavigationHandler] ✅ Matched second option");
        return 1;
      }

      // Third option patterns (index 2)
      if (maxOptions > 2 &&
          RegExp(r'\b(3|three|third|3rd|number three|option three|third option|third choice)\b')
              .hasMatch(cleanText)) {
        print("[NavigationHandler] ✅ Matched third option");
        return 2;
      }

      // Additional generic checks for numbers anywhere in the text
      if (cleanText.contains('1') ||
          cleanText.contains(' one ') ||
          cleanText.startsWith('one ') ||
          cleanText.endsWith(' one')) {
        return 0;
      } else if (maxOptions > 1 &&
          (cleanText.contains('2') ||
              cleanText.contains(' two ') ||
              cleanText.startsWith('two ') ||
              cleanText.endsWith(' two'))) {
        return 1;
      } else if (maxOptions > 2 &&
          (cleanText.contains('3') ||
              cleanText.contains(' three ') ||
              cleanText.startsWith('three ') ||
              cleanText.endsWith(' three'))) {
        return 2;
      }

      // Try parsing as integer from individual words
      final words = cleanText.split(' ');
      for (String word in words) {
        final num = int.tryParse(word);
        if (num != null && num >= 1 && num <= maxOptions) {
          return num - 1;
        }
      }

      // Try advanced matching for phrases like "I want the second one"
      if (cleanText.contains('first') || cleanText.contains('1st')) {
        return 0;
      } else if (maxOptions > 1 &&
          (cleanText.contains('second') || cleanText.contains('2nd'))) {
        return 1;
      } else if (maxOptions > 2 &&
          (cleanText.contains('third') || cleanText.contains('3rd'))) {
        return 2;
      }

      print("[NavigationHandler] ❌ No option match found");
      return null;
    } catch (e) {
      print("[NavigationHandler] ❌ Error parsing spoken number: $e");
      return null;
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
