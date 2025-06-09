import 'dart:async';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'tts_service.dart';

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
    // Speak out the emergency message with highest priority and wait for completion
    await _ttsService.speakAndWait(
      "Emergency detected. Calling emergency services.",
      TtsPriority.sos,
    );

    // Launch the emergency call directly
    bool? callMade = await FlutterPhoneDirectCaller.callNumber(emergencyNumber);

    if (callMade == true) {
      print("[SOS] Emergency call initiated successfully");
    } else {
      print("[SOS] Failed to initiate emergency call");
    }
  }
}
