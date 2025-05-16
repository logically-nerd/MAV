import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensor_demo/services/sensor_service/human_orientation_service.dart';
import 'package:vibration/vibration.dart';

class CameraPreviewPage extends StatefulWidget {
  const CameraPreviewPage({Key? key}) : super(key: key);

  @override
  _CameraPreviewPageState createState() => _CameraPreviewPageState();
}

class _CameraPreviewPageState extends State<CameraPreviewPage> {
  CameraController? _cameraController;
  RotationDetector? _rotationDetector;
  bool _isInitialized = false;
  String? _lastCapturedImagePath;
  String? _errorMessage;
  bool _hasVibration = false;

  @override
  void initState() {
    super.initState();
    _checkVibrationAvailability();
    _initializeCamera();
  }

  Future<void> _checkVibrationAvailability() async {
    _hasVibration = await Vibration.hasVibrator() ?? false;
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

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _errorMessage = 'No cameras available';
        });
        return;
      }

      _cameraController = CameraController(
        cameras[0],
        ResolutionPreset.high,
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
          // Trigger vibration
          await _vibrate();
          // Capture photo
          await _capturePhoto();
        },
        debounceTime: const Duration(seconds: 2),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _capturePhoto() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      final photo = await _cameraController!.takePicture();
      setState(() {
        _lastCapturedImagePath = photo.path;
      });
      await _vibrate();
      print('Photo saved: ${photo.path}');
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to capture photo: $e';
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _rotationDetector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Center(
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
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Preview'),
      ),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(_cameraController!),
          ),
          if (_lastCapturedImagePath != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Last photo: $_lastCapturedImagePath',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
