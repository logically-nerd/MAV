// intent_listener_widget.dart
import 'package:flutter/material.dart';
import './speech_intent_service.dart';
import './confirmation_handler.dart';

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
    return ElevatedButton(
      onPressed: _startListening,
      child: const Text("Start Voice Command"),
    );
  }
}
