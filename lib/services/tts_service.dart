import 'dart:async';
import 'dart:collection';
import 'package:flutter_tts/flutter_tts.dart';

// Defines the priority of speech requests. Lower index = higher priority.
enum TtsPriority {
  sos, // Highest priority for emergencies
  conversation, // Regular conversational feedback
  confirmation, // For confirmation prompts - higher than regular conversation
  awareness, // For awareness-related instructions
  orientation, // For orientation-related instructions
  map, // Navigational instructions
  model, // For model-related instructions
}

class _TtsRequest {
  final String text;
  final TtsPriority priority;
  final Function onComplete;
  final Completer<void>? completer;
  final DateTime createdAt;

  _TtsRequest({
    required this.text,
    required this.priority,
    required this.onComplete,
    this.completer,
  }) : createdAt = DateTime.now();
}

class TtsService {
  static final TtsService instance = TtsService._internal();
  factory TtsService() => instance;
  TtsService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  final List<_TtsRequest> _queue = [];
  bool _isSpeaking = false;
  Function? _currentRequestCompletion;
  Completer<void>? _currentCompleter;
  bool _blockLowPriority = false;
  Timer? _fallbackTimer;
  DateTime? _speechStartTime;

  // Track current request priority
  TtsPriority? _currentRequestPriority;

  List<TtsPriority> _allowedPriorities = TtsPriority.values.toList();

  void blockAllExcept(List<TtsPriority> priorities) {
    print("[TTS Service] 🚫 Blocking all priorities except: $priorities");
    _blockLowPriority = true;
    _allowedPriorities = priorities;
  }

  // Then modify _shouldBlock:
  bool _shouldBlock(TtsPriority priority) {
    return _blockLowPriority && !_allowedPriorities.contains(priority);
  }

  Future<void> init() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setCompletionHandler(() {
      print(
          "[TTS Service] ✓ Completion handler called for priority: $_currentRequestPriority");
      _handleCompletion();
    });

    _flutterTts.setErrorHandler((message) {
      print("[TTS Service] ✗ Error handler called: $message");
      _handleCompletion();
    });

    _flutterTts.setStartHandler(() {
      _speechStartTime = DateTime.now();
      print(
          "[TTS Service] ▶ Start handler called at ${_speechStartTime} for priority: $_currentRequestPriority");
    });

    _flutterTts.setCancelHandler(() {
      print("[TTS Service] ⏹ Cancel handler called");
      _handleCompletion();
    });

    print("[TTS Service] ✓ TTS service initialized");
  }

  void _handleCompletion() {
    print("[TTS Service] _handleCompletion called");

    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    _isSpeaking = false;
    _currentRequestPriority = null;

    if (_speechStartTime != null) {
      final duration = DateTime.now().difference(_speechStartTime!);
      print("[TTS Service] Speech completed in: ${duration.inMilliseconds}ms");
      _speechStartTime = null;
    }

    // Complete the Future if one exists
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      print("[TTS Service] ✓ Completing Future");
      _currentCompleter!.complete();
      _currentCompleter = null;
    }

    // Execute the callback for the completed request
    if (_currentRequestCompletion != null) {
      print("[TTS Service] ✓ Calling completion callback");
      _currentRequestCompletion!();
      _currentRequestCompletion = null;
    }

    // Small delay before processing next to ensure cleanup
    Future.delayed(Duration(milliseconds: 50), () {
      _speakNext();
    });
  }

  /// Speak text with priority and completion callback
  void speak(String text, TtsPriority priority, {Function? onComplete}) {
    print("[TTS Service] Adding to queue: '$text' (Priority: $priority)");

    final request = _TtsRequest(
      text: text,
      priority: priority,
      onComplete: onComplete ?? () {},
    );

    if (_blockLowPriority && _shouldBlock(priority)) {
      print("[TTS Service] 🚫 Blocking low priority request: $text");
      onComplete?.call();
      return;
    }

    // If high priority request and something is speaking, interrupt
    if (_isSpeaking && _shouldInterrupt(priority)) {
      print(
          "[TTS Service] ⚡ Interrupting current speech for higher priority: $priority");
      _interruptAndQueue(request);
      return;
    }

    _addToQueue(request);
    if (!_isSpeaking) {
      _speakNext();
    }
  }

  /// Speak text and return Future that completes when speech finishes
  Future<void> speakAndWait(String text, TtsPriority priority) async {
    print(
        "[TTS Service] 🎯 speakAndWait called: '$text' (Priority: $priority)");

    final completer = Completer<void>();
    final request = _TtsRequest(
      text: text,
      priority: priority,
      onComplete: () {
        print("[TTS Service] ✓ onComplete callback for speakAndWait: '$text'");
      },
      completer: completer,
    );

    if (_blockLowPriority && _shouldBlock(priority)) {
      print("[TTS Service] 🚫 Blocking low priority speakAndWait: $text");
      completer.complete();
      return completer.future;
    }

    // If high priority request and something is speaking, interrupt
    if (_isSpeaking && _shouldInterrupt(priority)) {
      print(
          "[TTS Service] ⚡ Interrupting current speech for higher priority speakAndWait: $priority");
      _interruptAndQueue(request);
    } else {
      _addToQueue(request);
      if (!_isSpeaking) {
        _speakNext();
      }
    }

    print("[TTS Service] ⏳ Waiting for speech completion...");
    await completer.future;
    print("[TTS Service] ✅ speakAndWait completed for: '$text'");
  }

  // bool _shouldBlock(TtsPriority priority) {
  //   // Only allow SOS, conversation, and confirmation when blocked
  //   return priority != TtsPriority.sos &&
  //       priority != TtsPriority.conversation &&
  //       priority != TtsPriority.confirmation;
  // }

  bool _shouldInterrupt(TtsPriority newPriority) {
    if (_currentRequestPriority == null) return false;

    // SOS always interrupts
    if (newPriority == TtsPriority.sos) return true;

    // Confirmation interrupts everything except SOS
    if (newPriority == TtsPriority.confirmation &&
        _currentRequestPriority != TtsPriority.sos) {
      return true;
    }

    // Conversation interrupts lower priorities
    if (newPriority == TtsPriority.conversation &&
        _currentRequestPriority!.index > TtsPriority.conversation.index) {
      return true;
    }

    return false;
  }

  void _interruptAndQueue(_TtsRequest request) {
    // Stop current speech
    _flutterTts.stop();

    // Add the high priority request to front of queue
    _queue.insert(0, request);

    // Handle completion will trigger next speech
  }

  void _addToQueue(_TtsRequest request) {
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
    if (_isSpeaking || _queue.isEmpty) {
      print(
          "[TTS Service] _speakNext: isSpeaking=$_isSpeaking, queueEmpty=${_queue.isEmpty}");
      return;
    }

    final request = _queue.removeAt(0);
    _currentRequestCompletion = request.onComplete;
    _currentCompleter = request.completer;
    _currentRequestPriority = request.priority;
    _isSpeaking = true;

    print(
        "[TTS Service] 🔊 Starting speech: '${request.text}' (Priority: ${request.priority})");

    // Set up fallback timer based on text length
    final estimatedDuration = _estimateSpeechDuration(request.text);
    _fallbackTimer = Timer(estimatedDuration, () {
      print("[TTS Service] ⚠ Fallback timer triggered for: '${request.text}'");
      if (_isSpeaking) {
        print("[TTS Service] 🔧 Using fallback completion");
        _handleCompletion();
      }
    });

    try {
      await _flutterTts.speak(request.text);
      print("[TTS Service] ✓ speak() method returned for: '${request.text}'");
    } catch (e) {
      print('[TTS Service] ✗ Error in speak(): $e');
      _handleCompletion();
    }
  }

  Duration _estimateSpeechDuration(String text) {
    final wordCount = text.split(' ').length;
    final wordsPerMinute = 150;
    final estimatedMinutes = wordCount / wordsPerMinute;
    final estimatedMs = (estimatedMinutes * 60 * 1000).round();

    final bufferMs = 2000;
    final totalMs = estimatedMs + bufferMs;

    print("[TTS Service] Estimated duration for '$text': ${totalMs}ms");
    return Duration(milliseconds: totalMs);
  }

  /// Block low priority TTS during STT
  void blockLowPriority() {
    print("[TTS Service] 🚫 Blocking low priority requests");
    _blockLowPriority = true;
    _allowedPriorities = [
      TtsPriority.sos,
      TtsPriority.awareness,
      TtsPriority.conversation,
      TtsPriority.confirmation
    ];
  }

  /// Unblock low priority TTS after STT
  void unblockLowPriority() {
    print("[TTS Service] ✅ Unblocking low priority requests");
    _blockLowPriority = false;
    _allowedPriorities = TtsPriority.values.toList();
  }

  /// Stop current speech and clear queue
  void stop() {
    print("[TTS Service] 🛑 Immediate stop requested");

    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    // Stop TTS immediately
    _flutterTts.stop();

    // Complete any pending futures immediately
    if (_currentCompleter != null && !_currentCompleter!.isCompleted) {
      _currentCompleter!.complete();
      _currentCompleter = null;
    }

    // Clear queue and reset state
    _queue.clear();
    _isSpeaking = false;
    _currentRequestCompletion = null;
    _currentRequestPriority = null;

    print("[TTS Service] ✓ Immediate stop completed");
  }

  /// Check if currently speaking
  bool get isSpeaking => _isSpeaking;

  /// Check if a specific priority is blocked
  bool isPriorityBlocked(TtsPriority priority) {
    return _blockLowPriority && !_allowedPriorities.contains(priority);
  }
}
