import 'package:flutter/material.dart';
import 'dart:math';
import '../../services/sensor_service/sensor_service.dart';

class SensorScreen extends StatefulWidget {
  const SensorScreen({super.key});

  @override
  State<SensorScreen> createState() => _SensorScreenState();
}

class _SensorScreenState extends State<SensorScreen> {
  late final SensorService _sensorService;
  double _movementScore = 0.0;

  @override
  void initState() {
    super.initState();
    _sensorService = SensorService();
    _sensorService.startListening();
  }

  @override
  void dispose() {
    _sensorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Movement Score',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        StreamBuilder(
          stream: Stream.periodic(const Duration(milliseconds: 100)),
          builder: (context, snapshot) {
            _movementScore = (_sensorService.smoothedAcceleration * 0.7) +
                (_sensorService.smoothedRotation * 0.3);
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
                    'Roll (X): ${_sensorService.rollAngle.toStringAsFixed(1)}°'),
                Text(
                    'Pitch (Y): ${_sensorService.pitchAngle.toStringAsFixed(1)}°'),
                Text('Yaw (Z): ${_sensorService.yawAngle.toStringAsFixed(1)}°'),
              ],
            );
          },
        ),
      ],
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
