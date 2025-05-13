import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import './speech_intent_service.dart';
import './confirmation_handler.dart';
import './sos_service.dart'; // Import SOS service

class IntentListenerWidget extends StatefulWidget {
  const IntentListenerWidget({Key? key}) : super(key: key);

  @override
  State<IntentListenerWidget> createState() => _IntentListenerWidgetState();
}

class _IntentListenerWidgetState extends State<IntentListenerWidget> {
  final _intentService = SpeechIntentService.instance;
  final _confirmationHandler = ConfirmationHandler();
  bool _isListening = false; // Track listening state
  double _circleSize = 100.0; // Default circle size
  Color buttonColor = Colors.green; // Default button color
  String buttonText = "Start Voice Command"; // Default button text

  // This will be triggered only if it's not already listening
  Future<void> _startListening() async {
    if (_isListening) return; // Prevent starting listening if already listening

    setState(() {
      _isListening = true;
      buttonColor = Colors.blue; // Change to blue while listening
      buttonText = "Listening..."; // Change text to "Listening..."
      _circleSize = 150.0; // Increase circle size when listening
    });

    print("[UI] Starting voice command...");
    final result = await _intentService.listenAndClassify();
    if (result == null) {
      print("[UI] No intent detected.");
    } else {
      print("[UI] Detected intent: ${result.intent}, Sentence: ${result.raw}");

      if (result.intent == IntentType.navigate && result.destination != null) {
        final confirm =
            await _confirmationHandler.confirmDestination(result.destination!);
        print("[UI] Confirmed navigation: $confirm");
      } else if (result.intent == IntentType.awareness) {
        final confirm = await _confirmationHandler.confirmAwareness();
        print("[UI] Confirmed awareness: $confirm");
      }
    }

    // Reset state after listening
    setState(() {
      _isListening = false;
      buttonColor = Colors.green; // Reset to original color
      buttonText = "Start Voice Command"; // Reset to original text
      _circleSize = 100.0; // Reset to original size
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        SerialTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<SerialTapGestureRecognizer>(
                SerialTapGestureRecognizer.new,
                (SerialTapGestureRecognizer instance) {
          instance.onSerialTapDown = (SerialTapDownDetails details) {
            if (details.count == 3) {
              print('[UI] Triple tap detected. Triggering SOS.');
              SOSService.instance.triggerSOS();
            } else if (details.count == 2) {
              print('[UI] Double tap detected. Starting voice command.');
              _startListening();
            }
          };
        }),
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {
            print('[UI] Tap detected. Starting voice command.');
            _startListening();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300), // Animation duration
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: buttonColor, // Change color while listening
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              "$buttonText",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
