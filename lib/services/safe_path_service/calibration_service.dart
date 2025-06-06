// lib/navigation_pipeline/calibration_service.dart
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CalibrationService {
  // IMPORTANT: This value is critical and needs to be set based on
  // how much real-world distance a pixel in the 160x160 segmentation mask represents
  // in the 'immediate' ground area for a typical pedestrian phone-holding scenario.
  // This will likely require experimentation and tuning.
  // Example: If the 160px width of the mask, in the immediate zone, typically
  // covers 3.2 meters of real-world width, then pixelsPerMeter could be 160px / 3.2m = 50 px/m.
  // This is a placeholder and MUST be tuned.
  static double _pixelsPerMeter =
      30.0; // Example: 30 pixels in the mask roughly equal 1 meter.

  static int _cameraPreviewWidth = 0;
  static int _cameraPreviewHeight = 0;

  // Getter for pixelsPerMeter
  static double get pixelsPerMeter => _pixelsPerMeter;

  // Simplified initialization: Receives camera/preview resolution for context.
  // The actual pixelsPerMeter for the 160x160 mask space is a tuned constant.
  static Future<void> initializeCalibration({
    int cameraPreviewWidth = 0, // e.g., width of image fed to YOLO
    int cameraPreviewHeight = 0, // e.g., height of image fed to YOLO
  }) async {
    _cameraPreviewWidth = cameraPreviewWidth;
    _cameraPreviewHeight = cameraPreviewHeight;

    print(
        "CALIBRATION: Received camera preview resolution (context): ${_cameraPreviewWidth}w x ${_cameraPreviewHeight}h");
    print(
        "CALIBRATION: Using pre-tuned pixelsPerMeter for 160x160 mask space: $_pixelsPerMeter px/m.");
    print(
        "CALIBRATION: This value is crucial for metric calculations (margins, distances).");
    // No actual calculation from resolution is done here to keep it simple,
    // as deriving it accurately is complex and depends on FoV, lens, distance to ground plane etc.
    // _pixelsPerMeter should be determined through empirical testing for the specific use case.
    await Future.delayed(
        const Duration(milliseconds: 50)); // Simulate async work
    print("CALIBRATION: Initialization complete.");
  }

  // Allow updating the tuned value if necessary (e.g., from settings)
  static void setPixelsPerMeter(double value) {
    if (value > 0) {
      _pixelsPerMeter = value;
      print(
          "CALIBRATION: Pixels per meter manually set to $_pixelsPerMeter for 160x160 mask space.");
    }
  }

  // Helper to convert meters to pixels in the 160x160 mask space
  static double metersToPixels(double meters) {
    return meters * _pixelsPerMeter;
  }

  // Helper to convert pixels (in 160x160 mask space) to meters
  static double pixelsToMeters(double pixels) {
    if (_pixelsPerMeter == 0) return 0; // Avoid division by zero
    return pixels / _pixelsPerMeter;
  }
}
