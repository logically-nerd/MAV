import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';

class DeviceOrientationScreen extends StatefulWidget {
  const DeviceOrientationScreen({Key? key}) : super(key: key);

  @override
  State<DeviceOrientationScreen> createState() => _DeviceOrientationScreenState();
}

class _DeviceOrientationScreenState extends State<DeviceOrientationScreen> {
  // Subscriptions for sensor events
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  
  // Text-to-speech engine
  final FlutterTts _flutterTts = FlutterTts();
  
  // Sensor data
  AccelerometerEvent? _accelerometerEvent;
  
  // Orientation values
  double _pitch = 0.0; // Forward/backward tilt
  double _roll = 0.0;  // Left/right tilt
  
  // Define tolerance (10 degrees as mentioned)
  final double _tolerance = 10.0 * (pi / 180.0); // Convert to radians
  
  // Direction to guide the user
  String _direction = "Hold phone vertically";
  bool _isCorrectOrientation = false;
  
  // Timer for periodic speech feedback
  Timer? _speechTimer;
  
  // Flag to avoid repeated speech for the same instruction
  String _lastSpokenDirection = "";

  @override
  void initState() {
    super.initState();
    _initTts();
    _initSensors();
    
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
  }

  // Lower speech rate for clarity
  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.35); // slower for less overwhelming
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speakWithDelay(String text) async {
    await _flutterTts.speak(text);
    await Future.delayed(const Duration(seconds: 2));
  }

  void _initSensors() {
    // Accelerometer provides gravity vector components
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      if (!mounted) return;
      
      setState(() {
        _accelerometerEvent = event;
        _updateOrientation();
      });
    });
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
    bool pitchOk = pitchDegrees.abs() < (_tolerance * 180 / pi);
    
    if (rollOk && pitchOk) {
      _direction = "Perfect! Hold this position. The camera is now seeing straight ahead.";
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
        if (_roll >110) {
          _direction = "Tilt the phone backward";
        } else if(_roll<60) {
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
    _speechTimer?.cancel();
    _flutterTts.stop();
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
