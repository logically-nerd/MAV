import 'dart:async';

import 'package:MAV/screens/sensor_screen/device_orientation.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:MAV/services/surrounding_awareness_service/human_orientation_service.dart';
import 'package:vibration/vibration.dart';
import 'package:MAV/services/tts_service.dart';
import 'package:MAV/services/surrounding_awareness_service/sensor_websocket_service.dart';
import 'dart:io';

class CameraPreviewPage extends StatefulWidget {
  const CameraPreviewPage({Key? key}) : super(key: key);

  @override
  _CameraPreviewPageState createState() => _CameraPreviewPageState();
}

class CapturedAnglePhoto {
  final double angle;
  final String photoPath;
  CapturedAnglePhoto({required this.angle, required this.photoPath});
}

class _CameraPreviewPageState extends State<CameraPreviewPage> {
  CameraController? _cameraController;
  RotationDetector? _rotationDetector;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _hasVibration = false;
  final TtsService _ttsService = TtsService.instance;
  List<CapturedAnglePhoto> _capturedAnglePhotos = [];
  final List<int> _targetAngles = [0, 90, 180, 270];
  final Set<int> _capturedAngles = {};
  bool _orientationConfirmed = false;
  bool _isShowingOrientationScreen =
      false; // Prevent multiple orientation screens
  late SensorWebSocketService _wsService;

  bool _isCapturing = false;
  bool _isSpeaking = false; // Prevent TTS overlapping

  @override
  void initState() {
    super.initState();
    _checkVibrationAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak(
          'Please rotate the device in a clockwise direction to start capturing.');
    });

    // For a real device via USB, use your laptop's actual local IP address.
    // Make sure your server is listening on 0.0.0.0 and your firewall allows the connection.
    _wsService = SensorWebSocketService(serverUrl: 'ws://192.168.231.31:8765');
    _wsService.connect();
    _initializeCamera();
  }

  Future<void> _checkVibrationAvailability() async {
    _hasVibration = await Vibration.hasVibrator();
    print('DEBUG: Vibration available: $_hasVibration');
  }

  Future<void> _vibrate() async {
    if (!_hasVibration) {
      print('DEBUG: Vibration not available on this device');
      return;
    }

    try {
      // Pattern: wait 0ms, vibrate 100ms, wait 100ms, vibrate 100ms
      await Vibration.vibrate(
        pattern: [0, 100, 100, 100],
        intensities: [0, 255, 0, 255],
      );
      print('DEBUG: Vibration triggered');
    } catch (e) {
      print('DEBUG: Vibration error: $e');
    }
  }

  Future<void> _speak(String message) async {
    if (!_isSpeaking) {
      _isSpeaking = true;

      // Create a completer to wait for speech completion
      final completer = Completer<void>();

      _ttsService.speak(message, TtsPriority.conversation, onComplete: () {
        _isSpeaking = false;
        completer.complete();
      });

      // Wait for speech to complete
      await completer.future;
    }
  }

  Future<void> _initializeCamera() async {
    print('[DEBUG] Initializing camera...');
    try {
      final cameras = await availableCameras();
      print('[DEBUG] Available cameras: ${cameras.length}');
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available';
        });
        print('[DEBUG] No cameras available');
        await _speak('No cameras available');
        return;
      }

      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.low,
        enableAudio: false,
      );

      try {
        await _cameraController!.initialize();
        print('[DEBUG] Camera initialized successfully');
      } catch (e) {
        setState(() {
          _errorMessage = 'Failed to initialize camera: $e';
        });
        print('[DEBUG] Failed to initialize camera: $e');
        await _speak('Failed to initialize camera');
        return;
      }

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });
      print('[DEBUG] Camera controller is set and widget is mounted');

      // Initialize rotation detector after camera is ready
      _rotationDetector = RotationDetector();
      try {
        _rotationDetector!.startListening(
          onRotated90Degrees: () async {
            int? angle = _rotationDetector!.currentAngle;
            print('[DEBUG] Rotation detected at angle: $angle');
            if (_capturedAnglePhotos.length >= 4) {
              print('[DEBUG] Already captured 4 photos, skipping');
              return;
            }
            if (angle != null &&
                _targetAngles.contains(angle) &&
                !_capturedAngles.contains(angle)) {
              // Check if we need to show orientation screen and it's not already showing
              if (!_orientationConfirmed && !_isShowingOrientationScreen) {
                print('[DEBUG] Showing orientation screen for stability check');
                _isShowingOrientationScreen = true;
                bool isStable = await _showOrientationScreen();
                _isShowingOrientationScreen = false;

                if (!isStable) {
                  print('[DEBUG] Device not stable, skipping photo capture');
                  await _speak('Device not stable. Please try again.');
                  return;
                }
                _orientationConfirmed = true;
              }

              _capturedAngles.add(angle);
              await _vibrate();
              print('[DEBUG] Capturing photo at angle: $angle');
              await _capturePhoto(angle: angle.toDouble());
              int remaining = 4 - _capturedAnglePhotos.length;
              if (remaining > 0) {
                print(
                    '[DEBUG] Photo captured at $angle degrees. $remaining more to go.');
                await _speak(
                    'Photo captured at $angle degrees. $remaining more to go. Please rotate to the next position.');
              } else {
                print('[DEBUG] All 4 photos captured.');
                await _speak('All 4 photos captured. Thank you.');
              }
              // Don't reset _orientationConfirmed to prevent repeated orientation screens
            }
          },
          debounceTime: const Duration(seconds: 2),
        );
        print('[DEBUG] Rotation detector started');
      } catch (e) {
        setState(() {
          _errorMessage = 'Failed to start rotation detector: $e';
        });
        print('[DEBUG] Failed to start rotation detector: $e');
        await _speak('Failed to start rotation detector');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
      print('[DEBUG] Exception during camera initialization: $e');
      await _speak('Failed to initialize camera');
    }
  }

  Future<void> _capturePhoto({double? angle}) async {
    if (_isCapturing) {
      print('[DEBUG] Already capturing, skipping...');
      return;
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print('[DEBUG] Camera not ready');
      await _speak('Camera not ready');
      return;
    }

    if (_capturedAnglePhotos.length >= 4) {
      print('[DEBUG] Already captured 4 photos');
      await _speak('All 4 photos captured');
      return;
    }

    setState(() => _isCapturing = true); // Lock capture

    try {
      await Future.delayed(const Duration(milliseconds: 500));
      final photo = await _cameraController!.takePicture();
      print('[DEBUG] Photo taken: ${photo.path}');

      // Add to state only after successful capture
      if (angle != null && _capturedAnglePhotos.length < 4) {
        setState(() {
          _capturedAnglePhotos
              .add(CapturedAnglePhoto(angle: angle, photoPath: photo.path));
          _capturedAngles.add(angle.toInt());
        });
      }

      await _vibrate();
      print('[DEBUG] Photo saved at angle ${angle?.toInt()}°: ${photo.path}');

      // Send image via WebSocket (await to ensure completion)
      try {
        final fileBytes = await File(photo.path).readAsBytes();
        print(
            '[DEBUG] Sending image to websocket, bytes: ${fileBytes.length}, angle: $angle');
        if (angle != null) {
          await _wsService.sendImageWithAngle(
              fileBytes, angle); // Ensure this is awaited
        }
      } catch (e) {
        print('[DEBUG] Error sending image via websocket: $e');
        await _speak('Failed to send photo');
      }
    } catch (e) {
      print('[DEBUG] Failed to capture photo: $e');
      await _speak('Failed to capture photo');
    } finally {
      setState(() => _isCapturing = false); // Unlock capture
    }
  }

  Future<bool> _showOrientationScreen() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeviceOrientationScreen(),
        fullscreenDialog: true,
      ),
    );
    return result == true;
  }

  /// Returns the captured photos with their angles
  List<CapturedAnglePhoto> getCapturedAnglePhotos() {
    return List.unmodifiable(_capturedAnglePhotos);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _rotationDetector?.dispose();
    _isSpeaking = false;
    _wsService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initializeCamera,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Preview'),
        actions: [
          // Display counter of captured photos
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                '${_capturedAnglePhotos.length}/4 Photos',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: CameraPreview(_cameraController!),
          ),
          // Display captured angles
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.black12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Captured Angles: ${_capturedAngles.toList().join(', ')}',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Remaining: ${_targetAngles.where((a) => !_capturedAngles.contains(a)).toList().join(', ')}',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
