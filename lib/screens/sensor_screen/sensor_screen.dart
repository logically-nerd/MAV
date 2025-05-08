import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart'; // For accessing motion sensors
import 'package:flutter_tts/flutter_tts.dart'; // For text-to-speech feedback

 

class  SensorScreen extends StatefulWidget {
  const SensorScreen({Key? key}) : super(key: key);

  @override
  State<SensorScreen> createState() => _PhoneOrientationPageState();
}

class _PhoneOrientationPageState extends State<SensorScreen> {
  final FlutterTts _flutterTts = FlutterTts();
  
  // Streaming subscriptions for sensors
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  
  // Sensor values
  AccelerometerEvent? _accelerometerValues;
  GyroscopeEvent? _gyroscopeValues;
  
  // Orientation status
  bool _isPhoneVertical = false;
  bool _isPhoneStraight = false;
  bool isPhoneUpright = false;
  
  // Feedback control
  DateTime _lastFeedbackTime = DateTime.now();
  bool _feedbackEnabled = true;
  Timer? _feedbackTimer;
  
  // Thresholds for detecting orientation
  // These can be adjusted based on testing and user needs
  final double _verticalThreshold = 8.0; // Threshold for detecting vertical orientation
  final double _straightThreshold = 1.5; // Threshold for detecting straightness
  
  @override
  void initState() {
    super.initState();
    _initializeTts();
    _startListeningToSensors();
    
    // Initial instruction after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      _speakInstruction("Double tap anywhere to start orientation guidance. Triple tap to toggle feedback.");
    });
  }
  
  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }
  
  void _startListeningToSensors() {
    // Listen to accelerometer events
    _accelerometerSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      setState(() {
        _accelerometerValues = event;
        _checkOrientation();
      });
    });
    
    // Listen to gyroscope events
    _gyroscopeSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      setState(() {
        _gyroscopeValues = event;
      });
    });
  }
  
  void _checkOrientation() {
    if (_accelerometerValues == null) return;
    
    // Check if phone is held vertically (perpendicular to ground)
    // When phone is vertical, z-axis value is close to 0 and y-axis has higher value
    final double y = _accelerometerValues!.y;
    final double z = _accelerometerValues!.z;

    if (z>0) {
      isPhoneUpright = true;
    } else {
      isPhoneUpright = false;
    }
    
    // Calculate the absolute values
    final double absY = y.abs();
    final double absZ = z.abs();
    
    // Check if phone is vertical (perpendicular to ground)
    _isPhoneVertical = absY > _verticalThreshold && absZ < _straightThreshold;
    
    // Check if phone is straight (not tilted left or right)
    // Using x-axis for left/right tilt
    _isPhoneStraight = _accelerometerValues!.x.abs() < _straightThreshold;
    
    // Provide feedback if needed
    _provideFeedbackIfNeeded();
  }
  
  void _provideFeedbackIfNeeded() {
    if (!_feedbackEnabled) return;
    
    // Only give feedback every 3 seconds to avoid overwhelming the user
    final now = DateTime.now();
    if (now.difference(_lastFeedbackTime).inSeconds < 3) return;
    
    String feedback = "";
    
    if (!_isPhoneVertical && !_isPhoneStraight) {
      feedback = "Please hold the phone vertically and straight";
    } else if (!_isPhoneVertical) {
      feedback = "Please hold the phone vertically";
    } else if (!_isPhoneStraight) {
      if (_accelerometerValues!.x > 0) {
        feedback = "Tilt the phone right";
      } else {
        feedback = "Tilt the phone left";
      }
    } else if(!isPhoneUpright){
      feedback  = "please rotate the 180 degrees";
    }
    
     else if (_isPhoneVertical && _isPhoneStraight) {
      feedback = "Perfect position";
      
      // Schedule a timer to repeat this message occasionally
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (_isPhoneVertical && _isPhoneStraight && _feedbackEnabled) {
          _speakInstruction("Position maintained correctly");
        }
      });
    }
    
    
    if (feedback.isNotEmpty) {
      _speakInstruction(feedback);
      _lastFeedbackTime = now;
    }
  }
  
  Future<void> _speakInstruction(String text) async {
    await _flutterTts.speak(text);
  }
  
  void _toggleFeedback() {
    setState(() {
      _feedbackEnabled = !_feedbackEnabled;
      _speakInstruction(_feedbackEnabled ? "Feedback enabled" : "Feedback disabled");
    });
  }
  
  void _startGuidance() {
    _speakInstruction("Orientation guidance active. Hold your phone vertically and straight.");
    _feedbackEnabled = true;
  }
  
  int _tapCount = 0;
  Timer? _tapTimer;
  
  void _handleTap() {
    _tapCount++;
    
    _tapTimer?.cancel();
    _tapTimer = Timer(const Duration(milliseconds: 500), () {
      if (_tapCount == 2) {
        _startGuidance();
      } else if (_tapCount >= 3) {
        _toggleFeedback();
      }
      _tapCount = 0;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    // Get the screen size
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phone Orientation Guide'),
      ),
      body: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Phone Orientation Guide',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Text(
                  _feedbackEnabled 
                      ? 'Guidance Active'
                      : 'Guidance Paused',
                  style: TextStyle(
                    fontSize: 18,
                    color: _feedbackEnabled ? Colors.green : Colors.red,
                  ),
                ),
                const SizedBox(height: 40),
                Container(
                  width: size.width * 0.8,
                  height: size.width * 0.8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isPhoneVertical && _isPhoneStraight 
                        ? Colors.green.withOpacity(0.3)
                        : Colors.red.withOpacity(0.3),
                    border: Border.all(
                      color: _isPhoneVertical && _isPhoneStraight
                          ? Colors.green
                          : Colors.red,
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      _isPhoneVertical && _isPhoneStraight
                          ? Icons.check_circle_outline
                          : Icons.phonelink_setup,
                      size: 80,
                      color: _isPhoneVertical && _isPhoneStraight
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Text(
                  'Instructions:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '• Double tap anywhere to start guidance\n'
                    '• Triple tap to toggle feedback\n'
                    '• Follow the audio instructions to position your phone',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _feedbackTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }
}
