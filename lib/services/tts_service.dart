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
  final List<_TtsRequest> _queue = [];
  bool _isSpeaking = false;
  Function? _currentRequestCompletion;
  bool _blockLowPriority = false;

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

  /// Speak text with priority and completion callback
  void speak(String text, TtsPriority priority, {Function? onComplete}) {
    print("[TTS Service] Adding to queue: $text (Priority: $priority)");

    final request = _TtsRequest(
      text: text,
      priority: priority,
      onComplete: onComplete ?? () {},
    );

    // Check if we should block low priority requests
    if (_blockLowPriority && _shouldBlock(priority)) {
      print("[TTS Service] Blocking low priority request: $text");
      onComplete?.call(); // Call completion immediately for blocked requests
      return;
    }

    _addToQueue(request);
    if (!_isSpeaking) {
      _speakNext();
    }
  }

  bool _shouldBlock(TtsPriority priority) {
    // Block everything except SOS and conversation during STT
    return priority != TtsPriority.sos && priority != TtsPriority.conversation;
  }

  void _addToQueue(_TtsRequest request) {
    // Insert based on priority (lower index = higher priority)
    int insertIndex = _queue.length;
    for (int i = 0; i < _queue.length; i++) {
      if (request.priority.index < _queue[i].priority.index) {
        insertIndex = i;
        break;
      }
    }
    _queue.insert(insertIndex, request);
    print("[TTS Service] Queue size: ${_queue.length}");
  }

  Future<void> _speakNext() async {
    if (_isSpeaking || _queue.isEmpty) return;

    final request = _queue.removeAt(0);
    _currentRequestCompletion = request.onComplete;
    _isSpeaking = true;

    print("[TTS Service] Speaking: ${request.text}");

    try {
      await _flutterTts.speak(request.text);
    } catch (e) {
      print('[TTS Service] Error speaking: $e');
      _isSpeaking = false;
      if (_currentRequestCompletion != null) {
        _currentRequestCompletion!();
        _currentRequestCompletion = null;
      }
      _speakNext();
    }
  }

  /// Block low priority TTS during STT
  void blockLowPriority() {
    print("[TTS Service] Blocking low priority requests");
    _blockLowPriority = true;
  }

  /// Unblock low priority TTS after STT
  void unblockLowPriority() {
    print("[TTS Service] Unblocking low priority requests");
    _blockLowPriority = false;
  }

  /// Stop current speech and clear queue
  void stop() {
    print("[TTS Service] Stopping all speech");
    _flutterTts.stop();
    _queue.clear();
    _isSpeaking = false;
    _currentRequestCompletion = null;
  }

  /// Check if currently speaking
  bool get isSpeaking => _isSpeaking;
}
