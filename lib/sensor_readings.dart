import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';
import 'dart:async';

class SensorReadings {
  // Raw sensor values
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 0.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _gyroZ = 0.0;

  // Processed values
  double _smoothedAcceleration = 0.0;
  double _smoothedRotation = 0.0;

  // Rotation angles (in degrees)
  double _rollAngle = 0.0; // X-axis rotation
  double _pitchAngle = 0.0; // Y-axis rotation
  double _yawAngle = 0.0; // Z-axis rotation

  // Timing variables for integration
  DateTime? _lastUpdateTime;
  double _dt = 0.0; // Delta time in seconds

  // History buffers
  final List<double> _accelHistory = [];
  final List<double> _gyroHistory = [];
  static const int _historyLength = 5;

  // Stream subscriptions
  late StreamSubscription<AccelerometerEvent> _accelSubscription;
  late StreamSubscription<GyroscopeEvent> _gyroSubscription;

  SensorReadings() {
    _initSensors();
  }

  void _initSensors() {
    _lastUpdateTime = DateTime.now();

    // Accelerometer
    _accelSubscription = accelerometerEventStream().listen((event) {
      _accelX = event.x;
      _accelY = event.y;
      _accelZ = event.z;

      double totalAccel =
          sqrt(pow(_accelX, 2) + pow(_accelY, 2) + pow(_accelZ, 2)) - 9.8;
      totalAccel = totalAccel.abs();

      _accelHistory.add(totalAccel);
      if (_accelHistory.length > _historyLength) {
        _accelHistory.removeAt(0);
      }
      _smoothedAcceleration = _accelHistory.isNotEmpty
          ? _accelHistory.reduce((a, b) => a + b) / _accelHistory.length
          : 0.0;

      _printDebugData();
    });

    // Gyroscope
    _gyroSubscription = gyroscopeEventStream().listen((event) {
      final now = DateTime.now();
      _dt = now.difference(_lastUpdateTime!).inMilliseconds / 1000.0;
      _lastUpdateTime = now;

      _gyroX = event.x;
      _gyroY = event.y;
      _gyroZ = event.z;

      // Calculate angular displacement (integration)
      _rollAngle += _gyroX * _dt * (180 / pi); // Convert radians to degrees
      _pitchAngle += _gyroY * _dt * (180 / pi);
      _yawAngle += _gyroZ * _dt * (180 / pi);

      // Keep angles between 0-360 degrees
      _rollAngle %= 360;
      _pitchAngle %= 360;
      _yawAngle %= 360;

      double totalRotation =
          sqrt(pow(_gyroX, 2) + pow(_gyroY, 2) + pow(_gyroZ, 2));

      _gyroHistory.add(totalRotation);
      if (_gyroHistory.length > _historyLength) {
        _gyroHistory.removeAt(0);
      }
      _smoothedRotation = _gyroHistory.isNotEmpty
          ? _gyroHistory.reduce((a, b) => a + b) / _gyroHistory.length
          : 0.0;

      _printDebugData();
    });
  }

  void _printDebugData() {
    print('''
=== Sensor Readings ===
Accelerometer:
  X: ${_accelX.toStringAsFixed(2)} m/s²
  Y: ${_accelY.toStringAsFixed(2)} m/s²
  Z: ${_accelZ.toStringAsFixed(2)} m/s²
  Smoothed: ${_smoothedAcceleration.toStringAsFixed(2)} m/s²

Gyroscope:
  X: ${_gyroX.toStringAsFixed(2)} rad/s
  Y: ${_gyroY.toStringAsFixed(2)} rad/s
  Z: ${_gyroZ.toStringAsFixed(2)} rad/s
  Smoothed: ${_smoothedRotation.toStringAsFixed(2)} rad/s

Rotation Angles:
  Roll (X): ${_rollAngle.toStringAsFixed(1)}°
  Pitch (Y): ${_pitchAngle.toStringAsFixed(1)}°
  Yaw (Z): ${_yawAngle.toStringAsFixed(1)}°
=======================
''');
  }

  // Getters
  double get smoothedAcceleration => _smoothedAcceleration;
  double get smoothedRotation => _smoothedRotation;
  double get rollAngle => _rollAngle;
  double get pitchAngle => _pitchAngle;
  double get yawAngle => _yawAngle;

  void dispose() {
    _accelSubscription.cancel();
    _gyroSubscription.cancel();
  }
}
