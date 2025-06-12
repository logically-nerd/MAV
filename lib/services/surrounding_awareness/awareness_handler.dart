import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:MAV/services/sos_service.dart';
import 'package:MAV/services/tts_service.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:path_provider/path_provider.dart';

enum AwarenessGesture {
  singleTap,
  doubleTap,
  tripleTap,
}

class AwarenessHandler {
  static final AwarenessHandler instance = AwarenessHandler._internal();
  factory AwarenessHandler() => instance;

  final TtsService _ttsService = TtsService.instance;
  final SOSService _sosService = SOSService.instance;

  bool _isInitialized = false;
  bool _isAwarenessActive = false;

  // Stream controller to notify UI about awareness mode changes
  final StreamController<bool> _awarenessStateController =
      StreamController<bool>.broadcast();
  Stream<bool> get awarenessStateStream => _awarenessStateController.stream;

  // WebSocket connection to YOLO server
  WebSocketChannel? _channel;
  late String _wsUrl;

  // Initialize the WebSocket URL from environment variables
  Future<void> _initializeWsUrl() async {
    try {
      final envVars = await rootBundle.loadString('assets/.env');
      final Map<String, String> env = {};
      
      for (var line in envVars.split('\n')) {
        line = line.trim();
        if (line.isNotEmpty && !line.startsWith('#')) {
          final parts = line.split('=');
          if (parts.length == 2) {
            env[parts[0]] = parts[1];
          }
        }
      }
      
      final ipAddress = env['IP_ADDRESS'] ?? '127.0.0.1';
      final port = env['PORT'] ?? '8765';
      _wsUrl = 'ws://$ipAddress:$port';
      print("[Awareness] WebSocket URL initialized: $_wsUrl");
    } catch (e) {
      print("[Awareness] Failed to load environment variables: $e");
      // Fallback to default values
      _wsUrl = 'ws://127.0.0.1:8765';
    }
  }

  // Camera control
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  // Tap detection
  Timer? _tapTimer;
  int _tapCount = 0;

  late Stream<dynamic> _channelStream;

  // Add this variable to your AwarenessHandler class
  bool _isProcessing = false;

  AwarenessHandler._internal() {
    // Block all TTS requests except SOS and awareness from initialization
    _initializeWsUrl();
  }

  bool get isAwarenessActive => _isAwarenessActive;

  Future<void> preload() async {
    if (_isInitialized) return;

    try {
      print("[Awareness] Initializing awareness services...");

      // Initialize camera
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        print("[Awareness] No cameras found!");
        return;
      }

      // Find rear camera
      CameraDescription? rearCamera;
      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.back) {
          rearCamera = camera;
          break;
        }
      }

      if (rearCamera == null) {
        print("[Awareness] No rear camera found!");
        return;
      }

      // Test WebSocket connection
      try {
        final testChannel = IOWebSocketChannel.connect(Uri.parse(_wsUrl));
        await testChannel.sink.close();
        print("[Awareness] WebSocket connection test successful");
      } catch (e) {
        print("[Awareness] WebSocket connection test failed: $e");
        // Continue initialization, as server might be available later
      }

      _isInitialized = true;
      print("[Awareness] ✓ Awareness handler initialized");
    } catch (e) {
      print("[Awareness] Error initializing awareness services: $e");
    }
  }

  Future<void> _initializeCamera() async {
    if (_cameras == null || _cameras!.isEmpty) {
      _cameras = await availableCameras();
    }

    // Find rear camera
    CameraDescription? rearCamera;
    for (var camera in _cameras!) {
      if (camera.lensDirection == CameraLensDirection.back) {
        rearCamera = camera;
        break;
      }
    }

    if (rearCamera == null) {
      throw Exception("No rear camera available");
    }

    // Initialize camera controller
    _cameraController = CameraController(
      rearCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();
    print("[Awareness] Camera initialized");
  }

  // Update the _connectToYoloServer method to provide better error handling
  Future<void> _connectToYoloServer() async {
    try {
      print("[Awareness] Attempting to connect to YOLO server at $_wsUrl");
      var rawChannel = IOWebSocketChannel.connect(Uri.parse(_wsUrl));
      _channel = rawChannel;
      _channelStream = _channel!.stream.asBroadcastStream();
      // Try to ping the server to verify connection
      final pingData = {'type': 'ping'};
      _channel!.sink.add(jsonEncode(pingData));

      // Wait for response with timeout
      final responseCompleter = Completer<bool>();
      late StreamSubscription subscription;

      subscription = _channelStream.listen(
        (message) {
          try {
            final response = jsonDecode(message);
            if (response['status'] == 'success' &&
                response['message'] == 'Server is running') {
              if (!responseCompleter.isCompleted) {
                responseCompleter.complete(true);
              }
            }
          } catch (e) {
            print("[Awareness] Error parsing ping response: $e");
            if (!responseCompleter.isCompleted) {
              responseCompleter.complete(false);
            }
          }
          subscription.cancel();
        },
        onError: (error) {
          print("[Awareness] WebSocket error during ping: $error");
          if (!responseCompleter.isCompleted) {
            responseCompleter.completeError(error);
          }
          subscription.cancel();
        },
        onDone: () {
          if (!responseCompleter.isCompleted) {
            responseCompleter.completeError("Connection closed during ping");
          }
          subscription.cancel();
        },
      );

      // Set timeout for ping
      bool connected = false;
      try {
        connected = await responseCompleter.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            subscription.cancel();
            throw TimeoutException("Server ping timeout");
          },
        );
      } catch (e) {
        // Timeout or other error
        print("[Awareness] Server ping failed: $e");
        throw Exception(
            "Failed to verify connection to object detection server");
      }

      if (connected) {
        print("[Awareness] Successfully connected to YOLO WebSocket server");
      } else {
        throw Exception("Failed to verify server connection");
      }
    } catch (e) {
      print("[Awareness] Failed to connect to YOLO server: $e");
      _channel?.sink.close();
      _channel = null;
      throw Exception(
          "Failed to connect to object detection server. Please ensure the server is running at $_wsUrl");
    }
  }

  // Add a new method to check connection and reconnect if needed
  Future<bool> _ensureConnected() async {
    try {
      if (_channel == null) {
        print("[Awareness] No connection exists, attempting to connect...");
        await _connectToYoloServer();
        return true;
      }

      // Test if connection is still alive with a ping
      try {
        final pingData = {'type': 'ping'};
        _channel!.sink.add(jsonEncode(pingData));

        // Wait for ping response with timeout
        bool pingSuccess = false;
        try {
          await _channelStream.firstWhere((msg) {
            try {
              final data = jsonDecode(msg);
              if (data['status'] == 'success' &&
                  data['message'] == 'Server is running') {
                pingSuccess = true;
                return true;
              }
              return false;
            } catch (_) {
              return false;
            }
          }).timeout(const Duration(seconds: 2));

          if (pingSuccess) {
            print("[Awareness] Connection is alive");
            return true;
          }
        } catch (timeoutError) {
          // Timeout or error means connection is dead
          print("[Awareness] Connection test failed: $timeoutError");
        }

        // If we get here, connection is dead - close and reconnect
        print("[Awareness] Connection appears dead, reconnecting...");
        _channel?.sink.close();
        _channel = null;
        await _connectToYoloServer();
        return true;
      } catch (e) {
        print("[Awareness] Error testing connection: $e");
        _channel?.sink.close();
        _channel = null;
        await _connectToYoloServer();
        return true;
      }
    } catch (e) {
      print("[Awareness] Failed to ensure connection: $e");
      return false;
    }
  }

  Future<void> startAwarenessMode() async {
    if (_isAwarenessActive) return;

    try {
      // Stop and block any ongoing TTS
      _ttsService.stop();
      // _ttsService.blockLowPriority(); // Replace this with the specific blocking for awareness mode
      _blockNonEssentialTts(); // ADD THIS LINE: Block TTS for awareness mode

      print("[Awareness] Speaking: Starting awareness mode...");
      await _ttsService.speakAndWait(
          "Starting awareness mode...", TtsPriority.awareness);

      await preload();
      await _initializeCamera();

      // Try to connect to server but don't block startup if it fails
      try {
        print("[Awareness] Speaking: Connecting to analysis server...");
        await _ttsService.speakAndWait(
            "Connecting to analysis server...", TtsPriority.awareness);
        await _connectToYoloServer();
      } catch (e) {
        // Continue without server - we'll try again when scanning
        print("[Awareness] Speaking: Warning about server connection");
        await _ttsService.speakAndWait(
            "Warning: Could not connect to analysis server. You can still use awareness mode, but object detection may not work.",
            TtsPriority.awareness);
      }

      _isAwarenessActive = true;

      // Notify UI to switch to camera view
      _awarenessStateController.add(true);
      print("[Awareness] Notified UI to switch to awareness mode");

      // Give the UI time to transition before continuing
      await Future.delayed(const Duration(milliseconds: 500));

      // Provide haptic feedback
      HapticFeedback.mediumImpact();

      // Add a small delay to ensure TTS is ready
      await Future.delayed(const Duration(milliseconds: 300));

      // Detailed voice instructions for the gestures - with more logging
      print("[Awareness] Speaking: Instructions for awareness mode");
      try {
        // Make sure to wait for this to complete
        await _ttsService.speakAndWait(
            "Awareness mode active. Single tap to scan objects. Double tap to exit. Triple tap for emergency.",
            TtsPriority.awareness);
        print("[Awareness] Instructions spoken successfully");
      } catch (e) {
        print("[Awareness] Error speaking instructions: $e");
      }

      print("[Awareness] Awareness mode started");
    } catch (e) {
      _isAwarenessActive = false;
      await _ttsService.speakAndWait(
          "Failed to start awareness mode: ${e.toString()}",
          TtsPriority.awareness);
      print("[Awareness] Failed to start awareness mode: $e");

      // Unblock TTS for other services
      _ttsService.unblockLowPriority();

      // Clean up resources
      await stopAwarenessMode();
    }
  }

  // Add a helper method to repeat instructions if needed
  Future<void> speakTapInstructions() async {
    if (!_isAwarenessActive) return;

    await _ttsService.speakAndWait(
        "Tap once to scan surroundings. Double tap to exit. Triple tap for emergency.",
        TtsPriority.awareness);
  }

  Future<void> stopAwarenessMode() async {
    if (!_isAwarenessActive) return;

    try {
      _isAwarenessActive = false;

      // Close camera
      await _cameraController?.dispose();
      _cameraController = null;

      // Close WebSocket
      _channel?.sink.close();
      _channel = null;

      // Notify UI to switch back to navigation view
      _awarenessStateController.add(false);

      await _ttsService.speakAndWait(
          "Returning to navigation mode.", TtsPriority.awareness);

      print("[Awareness] Awareness mode stopped");
    } catch (e) {
      print("[Awareness] Error stopping awareness mode: $e");
    } finally {
      // Unblock ALL TTS for other services when exiting awareness mode
      _unblockAllTts();
    }
  }

  // Handle tap detection internally
  void handleTap() {
    // Cancel any existing timer to prevent premature triggering
    _tapTimer?.cancel();

    // Increment tap count
    _tapCount++;

    // Set timer to wait a bit longer to catch multi-taps
    _tapTimer = Timer(const Duration(milliseconds: 500), () {
      // Only process the tap count after the delay
      _handleTapCount(_tapCount);
      _tapCount = 0;
    });
  }

  void _handleTapCount(int count) {
    if (count == 1) {
      handleGesture(AwarenessGesture.singleTap);
    } else if (count == 2) {
      handleGesture(AwarenessGesture.doubleTap);
    } else if (count >= 3) {
      handleGesture(AwarenessGesture.tripleTap);
    }
  }

  Future<void> handleGesture(AwarenessGesture gesture) async {
    if (!_isInitialized) {
      await preload();
    }

    switch (gesture) {
      case AwarenessGesture.singleTap:
        if (_isAwarenessActive) {
          // Check if we're already processing before analyzing
          if (_isProcessing) {
            print("[Awareness] Already processing, ignoring tap");
            // Optional: Give haptic feedback to indicate the tap was received but ignored
            HapticFeedback.lightImpact();
            return;
          }
          await _captureAndAnalyzeImage();
        } else {
          await startAwarenessMode();
          // Call speakTapInstructions explicitly to ensure it's spoken
          await speakTapInstructions();
        }
        break;

      case AwarenessGesture.doubleTap:
        if (_isAwarenessActive) {
          HapticFeedback.mediumImpact();
          await stopAwarenessMode();
        }
        break;

      case AwarenessGesture.tripleTap:
        // Stop ALL other TTS immediately when SOS is triggered
        _ttsService.stop(); // Stop any current speech

        // Provide strong haptic feedback to indicate emergency mode
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 200));
        HapticFeedback.heavyImpact(); // Double vibration for emergency

        // Emergency message gets highest priority
        await _ttsService.speakAndWait(
            "Emergency assistance activated. Sending SOS alert now.",
            TtsPriority.sos);

        // Trigger the actual SOS service
        await _sosService.triggerSOS();
        break;
    }
  }

  // Update the _captureAndAnalyzeImage method to use auto-reconnect
  Future<void> _captureAndAnalyzeImage() async {
    // Return immediately if already processing
    if (_isProcessing) {
      print("[Awareness] Already processing an image, ignoring tap");
      await _ttsService.speakAndWait(
          "Please wait, still processing previous scan.",
          TtsPriority.awareness);
      return;
    }

    if (!_isAwarenessActive ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      print("[Awareness] Camera not ready or not initialized.");
      await _ttsService.speakAndWait(
          "Camera not ready. Please try again.", TtsPriority.awareness);
      return;
    }

    try {
      // Set processing flag
      _isProcessing = true;

      HapticFeedback.lightImpact();
      print("[Awareness] Speaking: Scanning environment");
      await _ttsService.speakAndWait(
          "Scanning environment", TtsPriority.awareness);

      final XFile image = await _cameraController!.takePicture();
      print("[Awareness] Image captured at: ${image.path}");

      final bytes = await File(image.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      // Check and reconnect if needed
      try {
        print("[Awareness] Ensuring server connection...");
        if (!await _ensureConnected()) {
          await _ttsService.speakAndWait(
              "Cannot connect to analysis server. Please ensure the YOLO server is running and try again.",
              TtsPriority.awareness);
          return;
        }
      } catch (e) {
        print("[Awareness] Could not connect to analysis server: $e");
        await _ttsService.speakAndWait(
            "Cannot connect to analysis server. Please ensure the YOLO server is running and try again.",
            TtsPriority.awareness);
        return;
      }

      final requestData = {
        'type': 'image',
        'data': base64Image,
        'confidence': 0.3
      };

      print(
          "[Awareness] Sending image request: ${jsonEncode(requestData).substring(0, 200)}..."); // Print first 200 chars for brevity
      _channel!.sink.add(jsonEncode(requestData));

      await _processServerResponse();
    } catch (e) {
      print("[Awareness] Error capturing and analyzing image: $e");
      await _ttsService.speakAndWait(
          "Failed to analyze environment. Please try again.",
          TtsPriority.awareness);
    } finally {
      // Make sure to clear the flag even if there's an error
      _isProcessing = false;
    }
  }

  // Update the _processServerResponse method to handle server connection issues
  Future<void> _processServerResponse() async {
    if (_channel == null) {
      print("[Awareness] No connection to analysis server.");
      await _ttsService.speakAndWait(
          "No connection to analysis server. Please try again later.",
          TtsPriority.awareness);
      return;
    }

    try {
      print("[Awareness] Speaking: Processing image...");
      await _ttsService.speakAndWait(
          "Processing image...", TtsPriority.awareness);

      print("[Awareness] Waiting for server response...");
      String response;
      try {
        response = await _channelStream.firstWhere((msg) {
          try {
            final data = jsonDecode(msg);
            // Only accept messages that are not ping responses
            return !(data['status'] == 'success' &&
                data['message'] == 'Server is running');
          } catch (_) {
            return true;
          }
        }) as String;
      } catch (e) {
        print("[Awareness] Error waiting for server response: $e");
        await _ttsService.speakAndWait(
            "Analysis server is not responding. Please ensure the server is running and try again.",
            TtsPriority.awareness);
        return;
      }

      print("[Awareness] Raw server response: $response");

      Map<String, dynamic> responseData;
      try {
        responseData = jsonDecode(response);
        print("[Awareness] Decoded server response: $responseData");
      } catch (e) {
        print("[Awareness] Error parsing server response: $e");
        await _ttsService.speakAndWait(
            "Received invalid response from server. Please try again.",
            TtsPriority.awareness);
        return;
      }

      if (responseData['status'] == 'success') {
        final detectionResults = responseData['detection_results'] ?? {};
        final objectsCount = detectionResults['objects_count'] ?? 0;
        final classCounts = detectionResults['class_counts'] ?? {};

        print(
            "[Awareness] Objects count: $objectsCount, classCounts: $classCounts");

        if (objectsCount == 0 || classCounts.isEmpty) {
          await _ttsService.speakAndWait(
              "No objects detected in your surroundings.",
              TtsPriority.awareness);
          return;
        }

        List<String> objectDescriptions = [];
        classCounts.forEach((className, count) {
          objectDescriptions.add("$count $className${count > 1 ? 's' : ''}");
        });

        String description =
            "I detect $objectsCount object${objectsCount > 1 ? 's' : ''}: " +
                objectDescriptions.join(", ");

        print("[Awareness] Speaking result: $description");
        await _ttsService.speakAndWait(description, TtsPriority.awareness);
      } else {
        final errorMessage = responseData['error'] ?? "Unknown error";
        print("[Awareness] Server error: $errorMessage");
        await _ttsService.speakAndWait(
            "Analysis failed: $errorMessage", TtsPriority.awareness);
      }
    } catch (e) {
      print("[Awareness] Error processing server response: $e");
      await _ttsService.speakAndWait(
          "Failed to process environment analysis. Please try again.",
          TtsPriority.awareness);
    }
  }

  // Dispose method to clean up resources
  void dispose() {
    _tapTimer?.cancel();
    _awarenessStateController.close();
    stopAwarenessMode();
  }

  // Safely expose camera controller for the UI
  CameraController? getCameraController() {
    return _cameraController;
  }

  // Add this method to block all TTS except SOS and awareness
  void _blockNonEssentialTts() {
    print("[Awareness] Blocking all non-essential TTS");
    _ttsService.blockAllExcept([TtsPriority.sos, TtsPriority.awareness]);
  }

  // Add this method to unblock all TTS
  void _unblockAllTts() {
    print("[Awareness] Unblocking all TTS");
    _ttsService.unblockLowPriority();
  }
}
