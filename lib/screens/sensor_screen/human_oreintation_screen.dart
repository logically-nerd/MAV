import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:MAV/services/sensor_service/human_orientation_service.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'device_orientation.dart';

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
  FlutterTts? _flutterTts;
  List<CapturedAnglePhoto> _capturedAnglePhotos = [];

  final List<int> _targetAngles = [0, 90, 180, 270];
  final Set<int> _capturedAngles = {};
  bool _orientationConfirmed = false;

  @override
  void initState() {
    super.initState();
    _flutterTts = FlutterTts();
    _checkVibrationAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speak('Please rotate the device in a clockwise direction to start capturing.');
    });
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
    if (_flutterTts != null) {
      await _flutterTts!.speak(message);
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available';
        });
        await _speak('No cameras available');
        return;
      }

      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.low,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
      });

      // Initialize rotation detector after camera is ready
      _rotationDetector = RotationDetector();
      _rotationDetector!.startListening(
        onRotated90Degrees: () async {
          int? angle = _rotationDetector!.currentAngle;
          print('DEBUG: Rotation detected at angle: $angle');
          if (_capturedAnglePhotos.length >= 4) {
            // await _speak('All 4 photos captured. No more photos will be taken.');
            return;
          }
          if (angle != null && _targetAngles.contains(angle) && !_capturedAngles.contains(angle)) {
            if (!_orientationConfirmed) {
              bool isStable = await _showOrientationScreen();
              if (!isStable) {
                await _speak('Device not stable. Please try again.');
                return;
              }
              _orientationConfirmed = true;
            }
            _capturedAngles.add(angle);
            await _vibrate();
            await _capturePhoto(angle: angle.toDouble());
            int remaining = 4 - _capturedAnglePhotos.length;
            if (remaining > 0) {
              await _speak('Photo captured at $angle degrees. $remaining more to go. Please rotate to the next position.');
            } else {
              await _speak('All 4 photos captured. Thank you.');
            }
            _orientationConfirmed = false; // Reset for next rotation
          }
        },
        debounceTime: const Duration(seconds: 2),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
      await _speak('Failed to initialize camera');
    }
  }

  Future<void> _capturePhoto({double? angle}) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      await _speak('Camera not ready');
      return;
    }
    
    // Prevent more than 4 photos
    if (_capturedAnglePhotos.length >= 4) {
      await _speak('All 4 photos captured');
      return;
    }
    
    try {
      // Wait a moment to stabilize after rotation
      await Future.delayed(const Duration(milliseconds: 500));
      
      final photo = await _cameraController!.takePicture();
      setState(() {
        if (angle != null && _capturedAnglePhotos.length < 4) {
          _capturedAnglePhotos.add(CapturedAnglePhoto(angle: angle, photoPath: photo.path));
        }
      });
      
      await _vibrate();
      print('Photo saved at angle ${angle?.toInt()}°: ${photo.path}');
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to capture photo: $e';
      });
      await _speak('Failed to capture photo');
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
    _flutterTts?.stop();
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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