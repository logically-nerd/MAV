import 'package:flutter/material.dart';
// import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math';
import 'sensor_readings.dart'; // Import your SensorReadings class

void main() {
  runApp(const MovementDetectorApp());
}

class MovementDetectorApp extends StatelessWidget {
  const MovementDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Device Movement Detector',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MovementDetectorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MovementDetectorScreen extends StatefulWidget {
  const MovementDetectorScreen({super.key});

  @override
  State<MovementDetectorScreen> createState() => _MovementDetectorScreenState();
}

class _MovementDetectorScreenState extends State<MovementDetectorScreen> {
  late final SensorReadings _sensorReadings;
  double _movementScore = 0.0;

  @override
  void initState() {
    super.initState();
    _sensorReadings = SensorReadings();
  }

  @override
  void dispose() {
    _sensorReadings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Orientation Detector'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Movement Score
            const Text(
              'Movement Score',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            StreamBuilder(
              stream: Stream.periodic(const Duration(milliseconds: 100)),
              builder: (context, snapshot) {
                _movementScore = (_sensorReadings.smoothedAcceleration * 0.7) +
                    (_sensorReadings.smoothedRotation * 0.3);
                return Column(
                  children: [
                    Text(
                      _movementScore.toStringAsFixed(2),
                      style: TextStyle(
                        fontSize: 24,
                        color: _getMovementColor(_movementScore),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildMovementIndicator(_movementScore),
                  ],
                );
              },
            ),

            const SizedBox(height: 30),

            // Rotation Angles
            const Text(
              'Rotation Angles',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            StreamBuilder(
              stream: Stream.periodic(const Duration(milliseconds: 100)),
              builder: (context, snapshot) {
                return Column(
                  children: [
                    Text(
                        'Roll (X): ${_sensorReadings.rollAngle.toStringAsFixed(1)}°'),
                    Text(
                        'Pitch (Y): ${_sensorReadings.pitchAngle.toStringAsFixed(1)}°'),
                    Text(
                        'Yaw (Z): ${_sensorReadings.yawAngle.toStringAsFixed(1)}°'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _getMovementColor(double score) {
    if (score < 0.5) return Colors.green;
    if (score < 2.0) return Colors.orange;
    return Colors.red;
  }

  Widget _buildMovementIndicator(double score) {
    double indicatorWidth = MediaQuery.of(context).size.width * 0.8;
    double filledWidth = min(score * 50, indicatorWidth);

    return Container(
      height: 30,
      width: indicatorWidth,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Stack(
        children: [
          Container(
            width: filledWidth,
            decoration: BoxDecoration(
              color: _getMovementColor(score),
              borderRadius: BorderRadius.circular(15),
            ),
          ),
          Center(
            child: Text(
              _getMovementText(score),
              style: const TextStyle(
                  color: Color.fromARGB(255, 21, 20, 33),
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  String _getMovementText(double score) {
    if (score < 0.2) return "Device is still";
    if (score < 0.5) return "Slight movement";
    if (score < 2.0) return "Moderate movement";
    return "Strong movement!";
  }
}
