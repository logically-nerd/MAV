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

  Future<void> _startListening() async {
    print("[UI] Starting voice command...");
    final result = await _intentService.listenAndClassify();
    if (result == null) {
      print("[UI] No intent detected.");
      return;
    }

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
            }
          };
        }),
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: ElevatedButton(
          onPressed: _startListening,
          child: const Text("Start Voice Command"),
        ),
      ),
    );
  }
}
