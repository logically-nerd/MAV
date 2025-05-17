import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'dart:async';
import 'dart:math';

class SensorScreen extends StatefulWidget {
  const SensorScreen ({Key? key}) : super(key: key);

  SensorScreenState createState() => SensorScreenState();
}
class SensorScreenState extends State<SensorScreen> {
  final FlutterTts flutterTts = FlutterTts();

  double tiltAngle = 0.0;
  bool isOutOfRange = false;

  double _gyroAngleX = 0.0;
  double _angleFusedX = 0.0;
  double _biasX = 0.0;

  final double alpha = 0.98; // Complementary filter weight
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    _listenToSensors();
  }

  void _listenToSensors() {
    DateTime? lastTime;

    accelerometerEventStream().listen((AccelerometerEvent acc) {
      gyroscopeEventStream().listen((GyroscopeEvent gyro) {
        final now = DateTime.now();
        if (lastTime != null) {
          final dt = now.difference(lastTime!).inMicroseconds / 1000000.0;

          final double accPitchRad = atan2(acc.x, sqrt(acc.y * acc.y + acc.z * acc.z));

          _gyroAngleX += gyro.x * dt;

          _biasX = alpha * _biasX + (1 - alpha) * accPitchRad;
          _angleFusedX = alpha * (_gyroAngleX + _biasX) + (1 - alpha) * accPitchRad;

          final double tilt = radiansToDegrees(_angleFusedX).abs();

          setState(() {
            tiltAngle = tilt;
          });

          if (tilt > 10) {
            if (!isOutOfRange) {
              // Start a delayed warning
              _feedbackTimer = Timer(Duration(milliseconds: 1500), () {
                if (tiltAngle > 10) {
                  setState(() {
                    isOutOfRange = true;
                  });
                  _warnUser();
                }
              });
            }
          } else {
            if (isOutOfRange) {
              setState(() {
                isOutOfRange = false;
              });
            }
            // Cancel timer if tilt corrected before warning
            _feedbackTimer?.cancel();
          }
        }
        lastTime = now;
      });
    });
  }

  double radiansToDegrees(double radians) {
    return radians * 180.0 / 3.141592653589793;
  }

  void _warnUser() async {
    await Vibration.vibrate(duration: 300);
    await flutterTts.speak("Please straighten your phone.");
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Hold Phone Vertically")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Tilt Angle: ${tiltAngle.toStringAsFixed(2)}°",
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 20),
            Text(
              isOutOfRange ? "Too Tilted!" : "Good Position",
              style: TextStyle(
                fontSize: 28,
                color: isOutOfRange ? Colors.red : Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

