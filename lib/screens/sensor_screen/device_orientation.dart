import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:MAV/services/tts_service.dart'; // Add this import

class DeviceOrientationScreen extends StatefulWidget {
  const DeviceOrientationScreen({Key? key}) : super(key: key);

  @override
  State<DeviceOrientationScreen> createState() =>
      _DeviceOrientationScreenState();
}

class _DeviceOrientationScreenState extends State<DeviceOrientationScreen> {
  // Subscriptions for sensor events
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;

  // Text-to-speech engine
  final TtsService _ttsService = TtsService.instance; // Add this

  // Sensor data
  AccelerometerEvent? _accelerometerEvent;

  // Orientation values
  double _pitch = 0.0; // Forward/backward tilt
  double _roll = 0.0; // Left/right tilt

  // Filtered values for sensor fusion
  double _filteredPitch = 0.0;
  double _filteredRoll = 0.0;
  double _lastTimestamp = 0.0;
  final double _alpha = 0.98; // Complementary filter constant

  // Calibration
  Timer? _calibrationTimer;
  double _pitchOffset = 0.0;
  double _rollOffset = 0.0;

  // Define tolerance (10 degrees as mentioned)
  final double _tolerance = 10.0;

  // Direction to guide the user
  String _direction = "Hold phone vertically";
  bool _isCorrectOrientation = false;

  // Timer for periodic speech feedback
  Timer? _speechTimer;

  // Flag to avoid repeated speech for the same instruction
  String _lastSpokenDirection = "";

  // Flag to track if speaking is in progress
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initSensorFusion();

    // Speak initial instruction after a short delay
    Future.delayed(const Duration(seconds: 1), () {
      _speakWithDelay("Please hold the phone vertically");
    });

    // Set up timer for periodic guidance (every 10 seconds, less frequent)
    _speechTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isCorrectOrientation && _direction != _lastSpokenDirection) {
        _speakWithDelay(_direction);
        _lastSpokenDirection = _direction;
      }
    });

    // Calibration timer
    _calibrationTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _calibrateOffsets();
    });
  }

  // Update the speech method to use the TTS service
  Future<void> _speakWithDelay(String text) async {
    if (!_isSpeaking) {
      _isSpeaking = true;

      // Create a completer to wait for speech completion
      final completer = Completer<void>();

      _ttsService.speak(text, TtsPriority.confirmation, onComplete: () {
        _isSpeaking = false;
        completer.complete();
      });

      // Wait for speech to complete
      await completer.future;

      // Add a small delay after speech
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  void _initSensorFusion() {
    // Accelerometer provides gravity vector components
    _accelerometerSubscription =
        accelerometerEvents.listen((AccelerometerEvent event) {
      if (!mounted) return;

      setState(() {
        _accelerometerEvent = event;
        _updateOrientation();
      });
    });
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      if (!mounted) return;
      _updateOrientationFusion(event);
    });
  }

  void _updateOrientationFusion(GyroscopeEvent gyroEvent) {
    if (_accelerometerEvent == null) return;
    // Time delta
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final dt = (_lastTimestamp == 0.0) ? 0.02 : (now - _lastTimestamp);
    _lastTimestamp = now;

    // Gyro rates (rad/s)
    final gx = gyroEvent.x;
    final gy = gyroEvent.y;

    // Integrate gyro to estimate angles
    _filteredPitch += gx * dt;
    _filteredRoll += gy * dt;

    // Calculate from accelerometer
    final ax = _accelerometerEvent!.x;
    final ay = _accelerometerEvent!.y;
    final az = _accelerometerEvent!.z;
    final accPitch = atan2(-ax, sqrt(ay * ay + az * az));
    final accRoll = atan2(ay, az);

    // Complementary filter
    _filteredPitch = _alpha * _filteredPitch + (1 - _alpha) * accPitch;
    _filteredRoll = _alpha * _filteredRoll + (1 - _alpha) * accRoll;

    // Apply calibration offsets
    _pitch = _filteredPitch - _pitchOffset;
    _roll = _filteredRoll - _rollOffset;

    setState(() {
      _updateOrientation();
    });
  }

  void _calibrateOffsets() {
    // Use current filtered values as zero reference
    _pitchOffset = _filteredPitch;
    _rollOffset = _filteredRoll;
  }

  void _updateOrientation() {
    if (_accelerometerEvent == null) return;

    // Calculate roll (left-right tilt) and pitch (forward-backward tilt) from accelerometer
    final double x = _accelerometerEvent!.x;
    final double y = _accelerometerEvent!.y;
    final double z = _accelerometerEvent!.z;

    // Calculate roll (rotation around X-axis, left-right tilt)
    _roll = atan2(y, z);

    // Calculate pitch (rotation around Y-axis, forward-backward tilt)
    _pitch = atan2(-x, sqrt(y * y + z * z));

    // Determine orientation guidance
    _determineOrientation();
  }

  void _determineOrientation() {
    // Check if within tolerance for both roll and pitch
    // rollOk is true when roll (in degrees) is between 80 and 100
    double rollDegrees = _roll * 180 / pi;
    bool rollOk = rollDegrees >= 60 && rollDegrees <= 105;

    // pitchOk is true when pitch (in degrees) is close to 0 (within tolerance)
    double pitchDegrees = _pitch * 180 / pi;
    bool pitchOk = pitchDegrees.abs() < _tolerance;

    if (rollOk && pitchOk) {
      _direction = "Perfect! Hold this position.";
      _isCorrectOrientation = true;
      if (_lastSpokenDirection != _direction) {
        _speakWithDelay(_direction);
        _lastSpokenDirection = _direction;
      }
    } else {
      _isCorrectOrientation = false;

      // Determine which direction needs correction (prioritize the largest deviation)
      if (rollOk) {
        // Roll is good, but pitch needs adjustment
        if (_pitch < 0) {
          _direction = "Tilt the phone right";
        } else {
          _direction = "Tilt the phone left";
        }
      } else if (pitchOk) {
        // Pitch is good, but roll needs adjustment
        if (_roll > 110) {
          _direction = "Tilt the phone backward";
        } else if (_roll < 60) {
          _direction = "Tilt the phone forward";
        }
      } else {
        // Both need adjustment, handle the larger deviation
        if (_roll.abs() > _pitch.abs()) {
          if (_roll > 110) {
            _direction = "Tilt the phone backward";
          } else if (_roll < 60) {
            _direction = "Tilt the phone forward";
          }
        } else {
          if (_pitch > 0) {
            _direction = "Tilt the phone right";
          } else {
            _direction = "Tilt the phone left";
          }
        }
      }

      if (_lastSpokenDirection != _direction) {
        _speakWithDelay(_direction);
        _lastSpokenDirection = _direction;
      }
    }
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _calibrationTimer?.cancel();
    _speechTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Orientation'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Text(
              _direction,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'Roll: ${(_roll * 180 / pi).toStringAsFixed(1)}°\nPitch: ${(_pitch * 180 / pi).toStringAsFixed(1)}°',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // Automatically pop when orientation is correct
            Builder(
              builder: (context) {
                if (_isCorrectOrientation) {
                  // Delay pop to allow user to hear the feedback
                  Future.microtask(() {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop(true);
                    }
                  });
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}
