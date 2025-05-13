import 'dart:async';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SOSService {
  static final SOSService instance = SOSService._internal();
  factory SOSService() => instance;

  final FlutterTts _tts = FlutterTts();
  final emergencyNumber = "112"; // Emergency number

  SOSService._internal();

  Future<void> preload() async {
    print("[SOS] Preloading TTS...");
    await _tts.awaitSpeakCompletion(true);
    _tts.setCompletionHandler(() => print("[TTS] Done speaking"));
  }

  Future<void> triggerSOS() async {
    // Speak out the emergency message
    await _tts.speak("Emergency detected. Calling $emergencyNumber now.");

    // Launch the emergency call directly
    bool? callMade = await FlutterPhoneDirectCaller.callNumber(emergencyNumber);
    if (callMade == true) {
      _tts.speak("Emergency call initiated.");
    } else {
      _tts.speak("Failed to initiate emergency call.");
    }
  }
}
