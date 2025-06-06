import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo_result.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_task.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

class YoloSegmentation extends StatefulWidget {
  // Path to the model asset file
  final String modelAssetPath;

  // Optional parameters
  final YOLOTask task;
  final bool showControls;
  final Function(List<YOLOResult>)? onResultsUpdated;

  const YoloSegmentation({
    Key? key,
    required this.modelAssetPath,
    this.task = YOLOTask.segment,
    this.showControls = true,
    this.onResultsUpdated,
  }) : super(key: key);

  @override
  State<YoloSegmentation> createState() => _YoloSegmentationState();
}

class _YoloSegmentationState extends State<YoloSegmentation> {
  // Create a controller to interact with the YoloView
  final YOLOViewController _controller = YOLOViewController();
  String _modelPath = '';
  bool _modelLoaded = false;
  List<YOLOResult> _results = [];
  double _confidenceThreshold = 0.5;
  double _iouThreshold = 0.45;
  int _numItemsThreshold = 20;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      // Extract the filename from the asset path
      final fileName = widget.modelAssetPath.split('/').last;

      // Copy model from assets to temporary directory
      final byteData = await rootBundle.load(widget.modelAssetPath);
      final file = File('${(await getTemporaryDirectory()).path}/$fileName');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      setState(() {
        _modelPath = file.path;
        _modelLoaded = true;
      });

      print('YOLO Model loaded successfully at: $_modelPath');
    } catch (e) {
      print('Error loading YOLO model: $e');
      // You might want to add a retry mechanism or error display here
    }
  }

  void _handleDetectionResults(List<YOLOResult> results) {
    setState(() {
      _results = results;
    });

    // Call the callback if provided
    if (widget.onResultsUpdated != null) {
      widget.onResultsUpdated!(results);
    }

    // Print the first few results for debugging
    if (results.isNotEmpty) {
      print('YOLO: Received ${results.length} detection results');
      for (var i = 0; i < results.length && i < 3; i++) {
        final result = results[i];
        print(
            '  Result $i: ${result.className} (${(result.confidence * 100).toStringAsFixed(2)}%)');
        if (result.mask != null) {
          print('    Has segmentation mask');
        }
      }
    }
  }

  void _updateConfidenceThreshold(double value) {
    setState(() {
      _confidenceThreshold = value;
    });
    _controller.setConfidenceThreshold(value);
  }

  void _updateIoUThreshold(double value) {
    setState(() {
      _iouThreshold = value;
    });
    _controller.setIoUThreshold(value);
  }

  void _updateNumItemsThreshold(double value) {
    setState(() {
      _numItemsThreshold = value.round();
    });
    _controller.setNumItemsThreshold(value.round());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // YOLO View for camera feed and object detection/segmentation
        Expanded(
          flex: 3,
          child: _modelLoaded
              ? YOLOView(
                  controller: _controller,
                  modelPath: _modelPath,
                  task: widget.task,
                  onResult: _handleDetectionResults,
                  streamingConfig: YOLOStreamingConfig.custom(
                    maxFPS: 2,
                    inferenceFrequency: 2,
                    includeMasks: true,
                  ),
                  onPerformanceMetrics: (metrics) {
                    // Real-time performance monitoring
                    print('Metrics: $metrics');
                  },
                  showNativeUI: false, // We'll use our own UI controls
                )
              : const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading YOLO model...')
                    ],
                  ),
                ),
        ),

        // Results display
        if (widget.showControls)
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.black.withOpacity(0.05),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Detections: ${_results.length}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (context, index) {
                        final result = _results[index];
                        return ListTile(
                          dense: true,
                          title: Text(result.className),
                          subtitle: Text(
                            'Confidence: ${(result.confidence * 100).toStringAsFixed(1)}%',
                          ),
                          trailing: result.mask != null
                              ? const Icon(Icons.auto_awesome,
                                  color: Colors.green, size: 20)
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Controls section - only show if showControls is true
        if (widget.showControls)
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey.shade200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Confidence threshold slider
                Row(
                  children: [
                    const SizedBox(width: 120, child: Text('Confidence:')),
                    Expanded(
                      child: Slider(
                        value: _confidenceThreshold,
                        min: 0.1,
                        max: 0.9,
                        divisions: 8,
                        label: _confidenceThreshold.toStringAsFixed(1),
                        onChanged: _updateConfidenceThreshold,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('${(_confidenceThreshold * 100).round()}%'),
                    ),
                  ],
                ),

                // IoU threshold slider
                Row(
                  children: [
                    const SizedBox(width: 120, child: Text('IoU Threshold:')),
                    Expanded(
                      child: Slider(
                        value: _iouThreshold,
                        min: 0.1,
                        max: 0.9,
                        divisions: 8,
                        label: _iouThreshold.toStringAsFixed(1),
                        onChanged: _updateIoUThreshold,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('${(_iouThreshold * 100).round()}%'),
                    ),
                  ],
                ),

                // Max detections slider
                Row(
                  children: [
                    const SizedBox(width: 120, child: Text('Max Detections:')),
                    Expanded(
                      child: Slider(
                        value: _numItemsThreshold.toDouble(),
                        min: 1,
                        max: 50,
                        divisions: 49,
                        label: _numItemsThreshold.toString(),
                        onChanged: _updateNumItemsThreshold,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('$_numItemsThreshold'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
