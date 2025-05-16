import 'dart:math';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math.dart';

class RotationDetector {
  // Constants for detection configuration
  static const double _rotationThresholdDegrees = 85.0;  // Slightly less than 90° for better detection
  
  // Sensor data and rotation state
  Vector3 _gravity = Vector3(0, 0, 0);
  Vector3 _magneticField = Vector3(0, 0, 0);
  double _initialAzimuth = 0.0;
  double _currentAzimuth = 0.0;
  bool _isCalibrated = false;
  DateTime? _lastCaptureTime;
  bool _isListening = false;

  // Stream subscriptions
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetSubscription;
  
  // Orientation matrices
  final List<double> _rotationMatrix = List.filled(9, 0.0);
  final List<double> _orientationAngles = List.filled(3, 0.0);

  /// Starts listening to sensor events and detects 90-degree rotations
  void startListening({
    required Function() onRotated90Degrees,
    Duration debounceTime = const Duration(milliseconds: 1000),
  }) {
    if (_isListening) {
      print('DEBUG: Already listening to sensor events');
      return;
    }

    print('DEBUG: Starting sensor listening for 90° rotations');
    _isListening = true;
    _isCalibrated = false;
    
    // Listen to accelerometer for gravity vector
    _accelSubscription = accelerometerEventStream().listen((AccelerometerEvent event) {
      // Low-pass filter to extract gravity component
      const alpha = 0.8;
      _gravity.x = alpha * _gravity.x + (1 - alpha) * event.x;
      _gravity.y = alpha * _gravity.y + (1 - alpha) * event.y;
      _gravity.z = alpha * _gravity.z + (1 - alpha) * event.z;
      
      // Process orientation if we have both gravity and magnetic field data
      if (_magneticField.length > 0) {
        _updateOrientation();
      }
    });

    // Listen to magnetometer for compass heading
    _magnetSubscription = magnetometerEventStream().listen((MagnetometerEvent event) {
      // Low-pass filter for magnetic field
      const alpha = 0.6;
      _magneticField.x = alpha * _magneticField.x + (1 - alpha) * event.x;
      _magneticField.y = alpha * _magneticField.y + (1 - alpha) * event.y;
      _magneticField.z = alpha * _magneticField.z + (1 - alpha) * event.z;
      
      // Process orientation if we have gravity data
      if (_gravity.length > 0) {
        _updateOrientation();
        
        // Calibrate the initial azimuth if not calibrated
        if (!_isCalibrated) {
          _initialAzimuth = _orientationAngles[0];
          _isCalibrated = true;
          print('DEBUG: Calibrated initial azimuth: ${degrees(_initialAzimuth).toStringAsFixed(2)}°');
        } else {
          // Calculate rotation from initial position
          double rotationDegrees = _calculateRotationDegrees();
          
          // Check for 90-degree rotation
          if (_shouldTriggerRotationEvent(rotationDegrees, debounceTime)) {
            print('DEBUG: 90-degree rotation detected! Rotation: ${rotationDegrees.toStringAsFixed(2)}°');
            onRotated90Degrees();
            _lastCaptureTime = DateTime.now();
            // Update initial azimuth to current position for next rotation
            _initialAzimuth = _currentAzimuth;
          }
        }
      }
    });
  }
  
  /// Updates device orientation based on gravity and magnetic field
  void _updateOrientation() {
    // Get the rotation matrix
    if (!SensorManager.getRotationMatrix(_rotationMatrix, null, 
                                        _gravity.storage, _magneticField.storage)) {
      return;
    }
    
    // Get orientation angles from rotation matrix
    SensorManager.getOrientation(_rotationMatrix, _orientationAngles);
    
    // Update current azimuth (yaw)
    _currentAzimuth = _orientationAngles[0];
    
    // Debug print significant changes
    if (_isCalibrated && (_lastCaptureTime == null || 
        DateTime.now().difference(_lastCaptureTime!) > Duration(milliseconds: 500))) {
      final rotationDegrees = _calculateRotationDegrees();
      if (rotationDegrees.abs() % 45 < 2 || rotationDegrees.abs() % 45 > 43) {
        print('DEBUG: Current rotation: ${rotationDegrees.toStringAsFixed(2)}°');
      }
    }
  }
  
  /// Calculate rotation in degrees from initial position
  double _calculateRotationDegrees() {
    // Calculate difference between current and initial azimuth
    double rotationRadians = _currentAzimuth - _initialAzimuth;
    
    // Normalize to [-π, π]
    while (rotationRadians > pi) rotationRadians -= 2 * pi;
    while (rotationRadians < -pi) rotationRadians += 2 * pi;
    
    // Convert to degrees
    return degrees(rotationRadians);
  }
  
  /// Determine if we should trigger the rotation event
  bool _shouldTriggerRotationEvent(double rotationDegrees, Duration debounceTime) {
    // Check if enough time has passed since last trigger
    final bool timeElapsed = _lastCaptureTime == null || 
                           DateTime.now().difference(_lastCaptureTime!) > debounceTime;
    
    // Check if rotation is approximately 90 degrees (±5°)
    final bool is90DegreeRotation = 
        (rotationDegrees.abs() > _rotationThresholdDegrees && rotationDegrees.abs() < 95) ||
        (rotationDegrees.abs() > 175 && rotationDegrees.abs() < 185) ||
        (rotationDegrees.abs() > 265 && rotationDegrees.abs() < 275);
    
    return _isCalibrated && timeElapsed && is90DegreeRotation;
  }

  /// Stops listening to sensor events
  void stopListening() {
    print('DEBUG: Stopping sensor listening');
    _accelSubscription?.cancel();
    _magnetSubscription?.cancel();
    _isListening = false;
    _isCalibrated = false;
  }

  /// Resets the rotation detection state
  void reset() {
    print('DEBUG: Resetting rotation detector');
    _isCalibrated = false;
    _lastCaptureTime = null;
  }

  /// Gets the current rotation angle in degrees from initial position
  double getCurrentRotation() {
    if (!_isCalibrated) return 0.0;
    final rotation = _calculateRotationDegrees();
    return rotation;
  }

  /// Checks if the detector is currently listening
  bool get isListening {
    return _isListening;
  }

  /// Disposes the detector and cleans up resources
  void dispose() {
    print('DEBUG: Disposing rotation detector');
    stopListening();
  }
}

/// Utility class to compute rotation and orientation
class SensorManager {
  /// Get the rotation matrix from gravity and magnetic field
  static bool getRotationMatrix(List<double> R, List<double>? I,
      List<double> gravity, List<double> geomagnetic) {
    double Ax = gravity[0];
    double Ay = gravity[1];
    double Az = gravity[2];
    final double normsqA = (Ax * Ax + Ay * Ay + Az * Az);
    final double g = 9.81;
    final double freeFallGravitySquared = 0.01 * g * g;
    
    // Check if gravity is too small
    if (normsqA < freeFallGravitySquared) {
      return false;
    }
    
    final double Ex = geomagnetic[0];
    final double Ey = geomagnetic[1];
    final double Ez = geomagnetic[2];
    double Hx = Ey * Az - Ez * Ay;
    double Hy = Ez * Ax - Ex * Az;
    double Hz = Ex * Ay - Ey * Ax;
    final double normH = sqrt(Hx * Hx + Hy * Hy + Hz * Hz);
    
    if (normH < 0.1) {
      // Magnetic field is too weak
      return false;
    }
    
    final double invH = 1.0 / normH;
    Hx *= invH;
    Hy *= invH;
    Hz *= invH;
    final double invA = 1.0 / sqrt(normsqA);
    Ax *= invA;
    Ay *= invA;
    Az *= invA;
    final double Mx = Ay * Hz - Az * Hy;
    final double My = Az * Hx - Ax * Hz;
    final double Mz = Ax * Hy - Ay * Hx;
    
    R[0] = Hx; R[1] = Hy; R[2] = Hz;
    R[3] = Mx; R[4] = My; R[5] = Mz;
    R[6] = Ax; R[7] = Ay; R[8] = Az;
    
    return true;
  }
  
  /// Get the orientation angles from the rotation matrix
  static void getOrientation(List<double> R, List<double> values) {
    // Azimuth/Yaw (rotation around the -z axis)
    values[0] = atan2(R[1], R[0]);
    
    // Pitch (rotation around the x axis)
    values[1] = asin(-R[2]);
    
    // Roll (rotation around the y axis)
    values[2] = atan2(-R[5], R[8]);
  }
}