import 'dart:async';
import 'dart:collection';
import 'package:flutter_tts/flutter_tts.dart';

// Defines the priority of speech requests. Lower index = higher priority.
enum TtsPriority {
  sos, // Highest priority for emergencies
  conversation, // Regular conversational feedback
  orientation, // For orientation-related instructions
  map, // Navigational instructions
  model, // For model-related instructions
}

class _TtsRequest {
  final String text;
  final TtsPriority priority;
  final Function onComplete;

  _TtsRequest(
      {required this.text, required this.priority, required this.onComplete});
}

class TtsService {
  static final TtsService instance = TtsService._internal();
  factory TtsService() => instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  // Using a list instead of PriorityQueue for more control
  final List<_TtsRequest> _queue = [];
  bool _isSpeaking = false;
  Function? _currentRequestCompletion;

  // Initialize the service, setting up the crucial completion handler.
  Future<void> init() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setCompletionHandler(() {
      print("[TTS Service] Speech completed");
      _isSpeaking = false;
      // Execute the callback for the completed request
      if (_currentRequestCompletion != null) {
        _currentRequestCompletion!();
        _currentRequestCompletion = null; // Clear after execution
      }
      // Speak the next item in the queue
      _speakNext();
    });

    _flutterTts.setErrorHandler((message) {
      print("[TTS Service] Error: $message");
      _isSpeaking = false;
      if (_currentRequestCompletion != null) {
        _currentRequestCompletion!();
        _currentRequestCompletion = null;
      }
      _speakNext(); // Try to speak the next item even on error
    });

    _flutterTts.setStartHandler(() {
      print("[TTS Service] Started speaking");
    });

    _flutterTts.setCancelHandler(() {
      print("[TTS Service] Speech cancelled");
      _isSpeaking = false;
      if (_currentRequestCompletion != null) {
        _currentRequestCompletion!();
        _currentRequestCompletion = null;
      }
      _speakNext();
    });
  }

  bool _blockLowPriority = false;

  void blockLowPriority() {
    _blockLowPriority = true;
    // Only stop ongoing speech, don't clear high-priority queue items
    if (_isSpeaking) {
      _flutterTts.stop();
    }
  }

  void unblockLowPriority() {
    _blockLowPriority = false;
  }

  // Add a speech request to the queue.
  void speak(String text, TtsPriority priority, {Function? onComplete}) {
    if (_blockLowPriority &&
        (priority == TtsPriority.map || priority == TtsPriority.model || priority == TtsPriority.orientation)) {
      print("[TTS Service] Low priority request blocked during STT.");
      return;
    }
    print(
        "[TTS Service] Adding to queue: '$text' with priority ${priority.name}");

    // If onComplete is not provided, use a no-op function
    final Function actualOnComplete = onComplete ?? () {};

    // For SOS, immediately stop current speech and prioritize it.
    if (priority == TtsPriority.sos) {
      _queue.clear(); // Clear all lower priority requests
      _flutterTts.stop(); // Stop what's currently speaking
      _isSpeaking = false; // Reset speaking flag

      // Reset the current completion callback to prevent it from firing
      // when we cancel the current speech
      if (_currentRequestCompletion != null) {
        // Execute the callback of the interrupted speech to prevent hanging UI
        _currentRequestCompletion!();
        _currentRequestCompletion = null;
      }

      // Directly add and speak the SOS request
      final request = _TtsRequest(
          text: text, priority: priority, onComplete: actualOnComplete);
      _queue.add(request);

      // Speak immediately without delay
      _speakNext();
      return;
    }

    // For other priorities, remove existing requests of the same or lower priority
    _queue.removeWhere((req) => req.priority.index >= priority.index);

    final request = _TtsRequest(
        text: text, priority: priority, onComplete: actualOnComplete);
    _queue.add(request);

    // Sort the queue by priority (lowest index first)
    _queue.sort((a, b) => a.priority.index.compareTo(b.priority.index));

    if (!_isSpeaking) {
      _speakNext();
    }
  }

  void _speakNext() {
    if (_queue.isNotEmpty && !_isSpeaking) {
      _isSpeaking = true;
      final request = _queue.removeAt(0);
      _currentRequestCompletion = request.onComplete;
      print(
          "[TTS Service] Speaking: '${request.text}' with priority ${request.priority.name}");
      _flutterTts.speak(request.text);
    }
  }

  // Stop all speech and clear the queue.
  void stopAll() {
    _flutterTts.stop();
    _queue.clear();
    _isSpeaking = false;
    _currentRequestCompletion = null;
    print("[TTS Service] All speech stopped and queue cleared.");
  }

  // Dispose of the TTS engine when no longer needed
  void dispose() {
    _flutterTts.stop();
    // Instead of setting null, use empty functions
    _flutterTts.setCompletionHandler(() {});
    _flutterTts.setErrorHandler((msg) {});
    _flutterTts.setStartHandler(() {});
    _flutterTts.setCancelHandler(() {});
    print("[TTS Service] Disposed.");
  }
}
