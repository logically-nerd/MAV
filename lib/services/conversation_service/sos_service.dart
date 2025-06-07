import 'dart:async';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import '../tts_service.dart';

class SOSService {
  static final SOSService instance = SOSService._internal();
  factory SOSService() => instance;

  final TtsService _ttsService = TtsService.instance;
  final emergencyNumber = "112"; // Emergency number

  SOSService._internal();

  Future<void> preload() async {
    print("[SOS] Preloading services...");
  }

  Future<void> triggerSOS() async {
    // Speak out the emergency message with highest priority
    final completer = Completer<void>();

    _ttsService.speak(
        "Emergency detected. Calling $emergencyNumber now.", TtsPriority.sos,
        onComplete: () {
      completer.complete();
    });

    // Wait for the initial message to complete
    await completer.future;

    // Launch the emergency call directly
    bool? callMade = await FlutterPhoneDirectCaller.callNumber(emergencyNumber);

    if (callMade == true) {
      _ttsService.speak("Emergency call initiated.", TtsPriority.sos);
    } else {
      _ttsService.speak("Failed to initiate emergency call.", TtsPriority.sos);
    }
  }
}
