import 'dart:async'; // Add this for Timer
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/conversation_service/speech_intent_service.dart';
import '../services/conversation_service/confirmation_handler.dart';
import '../services/conversation_service/sos_service.dart';

class IntentListenerWidget extends StatefulWidget {
  const IntentListenerWidget({Key? key}) : super(key: key);

  @override
  State<IntentListenerWidget> createState() => _IntentListenerWidgetState();
}

class _IntentListenerWidgetState extends State<IntentListenerWidget> {
  final _intentService = SpeechIntentService.instance;
  final _confirmationHandler = ConfirmationHandler();
  bool _isListening = false;
  double _circleSize = 100.0;
  Color buttonColor = Colors.green;
  String buttonText = "Start Voice Command";

  Timer? _tapTimer; // Timer to resolve tap conflicts
  int _tapCount = 0;

  Future<void> _startListening() async {
    if (_isListening) return;

    setState(() {
      _isListening = true;
      buttonColor = Colors.blue;
      buttonText = "Listening...";
      _circleSize = 150.0;
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

    setState(() {
      _isListening = false;
      buttonColor = Colors.green;
      buttonText = "Start Voice Command";
      _circleSize = 100.0;
    });
  }

  void _handleTapCount(int count) {
    if (count == 3) {
      print('[UI] Triple tap detected. Triggering SOS.');
      SOSService.instance.triggerSOS();
    } else if (count == 2) {
      print('[UI] Double tap detected. Starting voice command.');
      _startListening();
    } else if (count == 1) {
      print('[UI] Single tap detected. Starting voice command.');
      _startListening();
    }
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
            _tapCount = details.count;

            _tapTimer?.cancel(); // Cancel existing timer
            _tapTimer = Timer(const Duration(milliseconds: 300), () {
              _handleTapCount(_tapCount);
              _tapCount = 0;
            });
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
            duration: const Duration(milliseconds: 300),
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: buttonColor,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              "$buttonText",
              textAlign: TextAlign.center,
              style: const TextStyle(
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

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }
}
