import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_exceptions.dart';
import 'package:ultralytics_yolo/yolo_method_channel.dart';
import 'package:ultralytics_yolo/yolo_platform_interface.dart';
import 'package:ultralytics_yolo/yolo_result.dart';
import 'package:ultralytics_yolo/yolo_task.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class YoloModel {
  late YOLO _yolo;

  Future<void> load() async {
    final modelPath = await getModelPath('assets/models/best_float32.tflite');

    _yolo = YOLO(
      modelPath: modelPath,
      task: YOLOTask.segment,
    );
    bool loaded = await _yolo.loadModel();
    if (loaded) {
      print('Model loaded successfully!');
    } else {
      print('Failed to load model.');
    }
  }

  Future<void> predictImage(String assetImagePath) async {
    // Load image as bytes from assets
    final ByteData imageData = await rootBundle.load(assetImagePath);
    final Uint8List imageBytes = imageData.buffer.asUint8List();

    // Run prediction
    final results = await _yolo.predict(imageBytes);
    print(
        "========================================================================================================");
    print('Raw YOLO results: $results');

    // Print results
    // Print results
    if (results['boxes'] != null && results['boxes'] is List) {
      for (final result in results['boxes'] as List<dynamic>) {
        print(
            'Detected: ${result['class']} | Confidence: ${result['confidence']} | Box: (${result['x1']}, ${result['y1']}) - (${result['x2']}, ${result['y2']})');
      }
    } else {
      print("No detections found.");
    }
  }
}

void testYoloPrediction() async {
  final yoloModel = YoloModel();
  await yoloModel.load();
  // Hardcoded asset path, change as needed
  await yoloModel.predictImage('assets/test_data/t2.jpg');
}

Future<String> getModelPath(String assetPath) async {
  final byteData = await rootBundle.load(assetPath);
  final file =
      File('${(await getTemporaryDirectory()).path}/best_float32.tflite');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  return file.path;
}
