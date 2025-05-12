import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:permission_handler/permission_handler.dart';

class YoloDetectionApp extends StatefulWidget {
  final List<CameraDescription> cameras;

  const YoloDetectionApp({Key? key, required this.cameras}) : super(key: key);

  @override
  _YoloDetectionAppState createState() => _YoloDetectionAppState();
}

class _YoloDetectionAppState extends State<YoloDetectionApp> {
  late CameraController _cameraController;
  bool _isCameraInitialized = false;
  bool _isDetecting = false;

  // WebSocket connection
  WebSocketChannel? _channel;
  bool _isConnected = false;

  // Detection results
  List<Detection> _detections = [];
  double _processingTime = 0;
  int _framesPerSecond = 0;
  int _frameCount = 0;
  Timer? _fpsTimer;

  // Configuration
  String _serverUrl =
      'ws://192.168.143.31:8765'; // Default for Android emulator connecting to localhost
  double _confidenceThreshold = 0.25;
  int _frameSkip = 3; // Process every Nth frame
  int _currentFrameCount = 0;
  bool _showDetections = true;

  bool _isConvertingImage = false;
  final _imageConversionQueue = StreamController<CameraImage>.broadcast();
  late StreamSubscription _imageConversionSub;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _startFpsCounter();

    // Setup image conversion pipeline
    _imageConversionSub = _imageConversionQueue.stream
        .asyncMap((image) => _convertAndSendImage(image))
        .listen((_) {});
  }

  Future<void> _convertAndSendImage(CameraImage image) async {
    if (_isConvertingImage || !_isConnected || _isDetecting) return;

    setState(() => _isDetecting = true);
    _currentFrameCount++;
    if (_currentFrameCount % _frameSkip != 0) {
      setState(() => _isDetecting = false);
      return;
    }

    try {
      _isConvertingImage = true;
      final stopwatch = Stopwatch()..start();

      // Convert to JPEG
      final jpegBytes = await _convertCameraImageToJpeg(image);
      if (jpegBytes.isEmpty) {
        print('Failed to convert image to JPEG');
        return;
      }

      final base64Image = base64Encode(jpegBytes);

      final message = jsonEncode({
        'type': 'image',
        'data': base64Image,
        'format': 'jpeg', // Important: specify the format as JPEG
        'width': image.width,
        'height': image.height,
        'conf': _confidenceThreshold,
      });

      _channel?.sink.add(message);
      _frameCount++;

      debugPrint('Image processed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('Error converting/sending image: $e');
    } finally {
      _isConvertingImage = false;
      if (mounted) setState(() => _isDetecting = false);
    }
  }

  Future<Uint8List> _convertCameraImageToJpeg(CameraImage image) async {
    try {
      // Convert based on image format
      if (image.format.group == ImageFormatGroup.yuv420) {
        return await _convertYUV420toJPEG(image);
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        return await _convertBGRA8888toJPEG(image);
      } else {
        // Fallback for other formats: just use the first plane
        debugPrint(
            'Using fallback conversion for format: ${image.format.group}');
        final plane = image.planes[0];

        // We'll generate a simple image from the Y plane data
        int width = image.width;
        int height = image.height;

        // Create an in-memory image from the Y plane data
        // This is a grayscale image, so we'll convert it to RGB
        final img = await _createGrayscaleImage(plane.bytes, width, height);
        return img;
      }
    } catch (e) {
      debugPrint('Image conversion error: $e');

      // Return an empty error image rather than failing
      try {
        // Create a small error image
        final errorImage = await _createErrorImage(320, 240);
        return errorImage;
      } catch (e2) {
        debugPrint('Error creating error image: $e2');
        return Uint8List(0);
      }
    }
  }

  Future<Uint8List> _createGrayscaleImage(
      Uint8List yData, int width, int height) async {
    final completer = Completer<Uint8List>();

    try {
      // Convert grayscale to RGB by copying the Y value to R, G, and B channels
      final rgbaData = Uint8List(width * height * 4);
      for (int i = 0; i < width * height; i++) {
        final y = yData[i];
        rgbaData[i * 4] = y; // R
        rgbaData[i * 4 + 1] = y; // G
        rgbaData[i * 4 + 2] = y; // B
        rgbaData[i * 4 + 3] = 255; // A
      }

      ui.decodeImageFromPixels(
        rgbaData,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (ui.Image image) async {
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          completer.complete(byteData!.buffer.asUint8List());
          image.dispose();
        },
      );
    } catch (e) {
      completer.completeError('Failed to create grayscale image: $e');
    }

    return completer.future;
  }

  Future<Uint8List> _createErrorImage(int width, int height) async {
    final completer = Completer<Uint8List>();

    try {
      // Create a red image with "Error" text
      final rgbaData = Uint8List(width * height * 4);
      for (int i = 0; i < width * height; i++) {
        rgbaData[i * 4] = 255; // R
        rgbaData[i * 4 + 1] = 0; // G
        rgbaData[i * 4 + 2] = 0; // B
        rgbaData[i * 4 + 3] = 255; // A
      }

      ui.decodeImageFromPixels(
        rgbaData,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (ui.Image image) async {
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          completer.complete(byteData!.buffer.asUint8List());
          image.dispose();
        },
      );
    } catch (e) {
      completer.completeError('Failed to create error image: $e');
    }

    return completer.future;
  }

  Future<Uint8List> _convertYUV420toJPEG(CameraImage image) async {
    final yuvConverter = YUVtoRGBConverter(
      width: image.width,
      height: image.height,
    );
    final rgbBytes = yuvConverter.convert(image);
    return await _encodeRGBtoJPEG(rgbBytes, image.width, image.height);
  }

  Future<Uint8List> _convertBGRA8888toJPEG(CameraImage image) async {
    final plane = image.planes[0];
    final bytes = plane.bytes;
    return await _encodeRGBtoJPEG(
      bytes,
      image.width,
      image.height,
      format: ui.ImageByteFormat.rawRgba,
    );
  }

  Future<Uint8List> _encodeRGBtoJPEG(
    Uint8List bytes,
    int width,
    int height, {
    ui.ImageByteFormat format = ui.ImageByteFormat.rawRgba,
  }) async {
    final completer = Completer<Uint8List>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      format as ui.PixelFormat,
      (ui.Image image) {
        image.toByteData(format: ui.ImageByteFormat.png).then((byteData) {
          completer.complete(byteData!.buffer.asUint8List());
          image.dispose();
        });
      },
    );
    return await completer.future;
  }

  void _startFpsCounter() {
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _framesPerSecond = _frameCount;
        _frameCount = 0;
      });
    });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      _initializeCamera();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission is required')));
    }
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No cameras found')));
      return;
    }

    // Use the first available camera
    _cameraController = CameraController(
      widget.cameras[0],
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController.initialize();

      // Set up image stream
      _cameraController.startImageStream((image) {
        _processImageFrame(image);
      });

      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  void _connectToServer() async {
    try {
      print('Attempting to connect to $_serverUrl');
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl));

      // Add connection timeout
      try {
        await _channel!.ready.timeout(const Duration(seconds: 10));
      } catch (e) {
        print('WebSocket connection not ready: $e');
        // Continue anyway - some WebSocket implementations don't support 'ready'
      }

      print('WebSocket connection established');
      _channel!.stream.listen((message) {
        print('Received message: ${message.length} bytes');
        _handleServerMessage(message);
      }, onDone: () {
        print('WebSocket connection closed by server');
        if (mounted) {
          setState(() {
            _isConnected = false;
          });
        }
      }, onError: (error) {
        print('WebSocket error: $error');
        if (mounted) {
          setState(() {
            _isConnected = false;
          });
          // Try to reconnect automatically
          Future.delayed(Duration(seconds: 2), () {
            if (mounted && !_isConnected) {
              _connectToServer();
            }
          });
        }
      });

      if (mounted) {
        setState(() {
          _isConnected = true;
        });
      }
    } on TimeoutException {
      print('Connection timeout');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Connection timeout')));
      }
    } catch (e) {
      print('Connection error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection failed: ${e.toString()}')));
      }
    }
  }

  void _processImageFrame(CameraImage image) {
    if (!_imageConversionQueue.isClosed) {
      _imageConversionQueue.sink.add(image);
    }

    // Skip frames based on frameSkip setting to reduce load
    _currentFrameCount++;
    if (_currentFrameCount % _frameSkip != 0) return;

    // Ensure we're connected and not currently processing
    if (!_isConnected || _isDetecting) return;

    setState(() {
      _isDetecting = true;
    });

    // Don't send raw image directly - let the conversion pipeline handle it
    _isDetecting = false;

    // The _convertAndSendImage function in the conversion queue will properly
    // convert the image to JPEG and send it to the server
  }

  void _handleServerMessage(dynamic message) {
    try {
      print('Received server message of length: ${message.length}');
      final Map<String, dynamic> data = jsonDecode(message);

      if (data.containsKey('error')) {
        print('Server error: ${data['error']}');
        setState(() {
          _isDetecting = false;
        });
        return;
      }

      // Extract processing time
      double processingTime = data['processing_time_ms'] ?? 0.0;
      print('Processing time: ${processingTime.toStringAsFixed(2)}ms');

      // Parse detections
      List<Detection> detections = [];
      if (data.containsKey('detections')) {
        print('Server sent ${data['detections'].length} detections');

        for (var det in data['detections']) {
          final bbox = List<int>.from(det['bbox']);
          final className = det['class_name'];
          final confidence = det['confidence'];

          print('Detection: class=$className, conf=$confidence, bbox=$bbox');

          detections.add(Detection(
            bbox: bbox,
            className: className,
            confidence: confidence,
            maskData: det.containsKey('mask') ? det['mask'] : null,
          ));
        }
      } else {
        print('No detections field in server response');
      }

      setState(() {
        _detections = detections;
        _processingTime = processingTime;
        _isDetecting = false;
      });

      print('Updated state with ${_detections.length} detections');
    } catch (e) {
      print('Error handling server message: $e');
      setState(() {
        _isDetecting = false;
      });
    }
  }

  void _testConnection() async {
    try {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Testing connection...')));

      final testChannel = WebSocketChannel.connect(Uri.parse(_serverUrl));
      await testChannel.ready.timeout(const Duration(seconds: 3));
      testChannel.sink.close();

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection successful!')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Connection test failed: $e')));
    }
  }

  void _disconnectFromServer() {
    _channel?.sink.close();
    setState(() {
      _isConnected = false;
    });
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _channel?.sink.close();
    _cameraController.dispose();
    _imageConversionSub.cancel();
    _imageConversionQueue.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('YOLO Real-time Detection'),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.cloud_done : Icons.cloud_off),
            onPressed: _isConnected ? _disconnectFromServer : _connectToServer,
            tooltip: _isConnected ? 'Disconnect' : 'Connect',
          ),
          IconButton(
            icon:
                Icon(_showDetections ? Icons.visibility : Icons.visibility_off),
            onPressed: () {
              setState(() {
                _showDetections = !_showDetections;
              });
            },
            tooltip: _showDetections ? 'Hide Detections' : 'Show Detections',
          ),
          IconButton(
            icon: const Icon(Icons.network_check),
            onPressed: _testConnection,
            tooltip: 'Test Connection',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isCameraInitialized
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera preview
                      AspectRatio(
                        aspectRatio: _cameraController.value.aspectRatio,
                        child: CameraPreview(_cameraController),
                      ),

                      // Detection overlays
                      if (_showDetections && _detections.isNotEmpty)
                        CustomPaint(
                          size: Size.infinite,
                          painter: DetectionPainter(
                            detections: _detections,
                            previewSize: Size(
                              _cameraController.value.previewSize!.width,
                              _cameraController.value.previewSize!.height,
                            ),
                            screenSize: MediaQuery.of(context).size,
                          ),
                        ),

                      // Visualization debug info (temporary)
                      if (_showDetections)
                        Positioned(
                          bottom: 70,
                          left: 10,
                          right: 10,
                          child: Text(
                            'Preview size: ${_cameraController.value.previewSize!.width}x${_cameraController.value.previewSize!.height}\n'
                            'Detections: ${_detections.length}',
                            style: TextStyle(
                              color: Colors.white,
                              backgroundColor: Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                        ),

                      // Status indicator
                      Positioned(
                        top: 20,
                        left: 20,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _isDetecting
                                ? Colors.orange
                                : (_isConnected ? Colors.green : Colors.red),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),

                      // Stats overlay
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'FPS: $_framesPerSecond',
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                'Processing: ${_processingTime.toStringAsFixed(1)}ms',
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                'Objects: ${_detections.length}',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : const Center(child: CircularProgressIndicator()),
          ),

          // Settings panel
          Container(
            color: Colors.grey[200],
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Row(
                  children: [
                    const Text('Server URL: '),
                    Expanded(
                      child: TextField(
                        controller: TextEditingController(text: _serverUrl),
                        onChanged: (value) {
                          _serverUrl = value;
                        },
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Confidence: '),
                    Expanded(
                      child: Slider(
                        value: _confidenceThreshold,
                        min: 0.1,
                        max: 0.9,
                        divisions: 8,
                        label: _confidenceThreshold.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() {
                            _confidenceThreshold = value;
                          });
                        },
                      ),
                    ),
                    Text(_confidenceThreshold.toStringAsFixed(2)),
                  ],
                ),
                Row(
                  children: [
                    const Text('Skip frames: '),
                    Expanded(
                      child: Slider(
                        value: _frameSkip.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        label: _frameSkip.toString(),
                        onChanged: (value) {
                          setState(() {
                            _frameSkip = value.toInt();
                          });
                        },
                      ),
                    ),
                    Text(_frameSkip.toString()),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class YUVtoRGBConverter {
  final int width;
  final int height;

  YUVtoRGBConverter({required this.width, required this.height});

  Uint8List convert(CameraImage image) {
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final rgbaBytes = Uint8List(width * height * 4);

    // Convert YUV to RGBA
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = (x / 2).floor() + (y / 2).floor() * (width / 2).floor();
        final yIndex = y * width + x;

        final yVal = yPlane.bytes[yIndex];
        final uVal = uPlane.bytes[uvIndex];
        final vVal = vPlane.bytes[uvIndex];

        // Convert YUV to RGB
        var r = yVal + 1.402 * (vVal - 128);
        var g = yVal - 0.344136 * (uVal - 128) - 0.714136 * (vVal - 128);
        var b = yVal + 1.772 * (uVal - 128);

        // Clamp values
        r = r.clamp(0, 255).toDouble();
        g = g.clamp(0, 255).toDouble();
        b = b.clamp(0, 255).toDouble();

        // Set RGBA values
        final index = yIndex * 4;
        rgbaBytes[index] = r.toInt();
        rgbaBytes[index + 1] = g.toInt();
        rgbaBytes[index + 2] = b.toInt();
        rgbaBytes[index + 3] = 255; // Alpha
      }
    }

    return rgbaBytes;
  }
}

class Detection {
  final List<int> bbox; // [x1, y1, x2, y2]
  final String className;
  final double confidence;
  final Map<String, dynamic>? maskData; // For segmentation

  Detection({
    required this.bbox,
    required this.className,
    required this.confidence,
    this.maskData,
  });
}

class DetectionPainter extends CustomPainter {
  final List<Detection> detections;
  final Size previewSize;
  final Size screenSize;

  DetectionPainter({
    required this.detections,
    required this.previewSize,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    print('DetectionPainter: painting ${detections.length} detections');
    print(
        'DetectionPainter: preview size: $previewSize, screen size: $screenSize, canvas size: $size');

    final Paint boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.red;

    final Paint maskPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red.withOpacity(0.3);

    final TextStyle textStyle = TextStyle(
      color: Colors.white,
      backgroundColor: Colors.red.withOpacity(0.7),
      fontSize: 16,
    );

    // Calculate the scaling factors to map from model coordinates to screen
    // Most mobile cameras are in landscape mode internally, but displayed in portrait
    // The YOLO detections come in the original camera coordinates (typically landscape)
    // but we need to display them in the rotated portrait view

    // Account for camera rotation (90 degrees typically)
    bool needsRotation =
        previewSize.width > previewSize.height != size.width > size.height;

    // Calculate scale based on the canvas size (which is the actual display size)
    double scaleX, scaleY;

    if (needsRotation) {
      // For 90 degree rotation (common in phones), we swap width/height
      scaleX = size.width / previewSize.height;
      scaleY = size.height / previewSize.width;
      print(
          'DetectionPainter: using rotation adjustment with scale factors: $scaleX, $scaleY');
    } else {
      // Without rotation, direct mapping
      scaleX = size.width / previewSize.width;
      scaleY = size.height / previewSize.height;
      print(
          'DetectionPainter: using direct mapping with scale factors: $scaleX, $scaleY');
    }

    for (var detection in detections) {
      try {
        // Original bounding box coordinates from YOLO
        final bbox = detection.bbox;

        double x1, y1, x2, y2;

        if (needsRotation) {
          // Convert the coordinates accounting for 90 degree rotation
          // For 90 degree CCW rotation:
          // x' = height - y
          // y' = x
          x1 = previewSize.height - bbox[1] * scaleX;
          y1 = bbox[0] * scaleY;
          x2 = previewSize.height - bbox[3] * scaleX;
          y2 = bbox[2] * scaleY;
        } else {
          // Direct mapping
          x1 = bbox[0] * scaleX;
          y1 = bbox[1] * scaleY;
          x2 = bbox[2] * scaleX;
          y2 = bbox[3] * scaleY;
        }

        print(
            'DetectionPainter: class=${detection.className}, confidence=${detection.confidence}');
        print('DetectionPainter: original bbox: [${bbox.join(', ')}]');
        print('DetectionPainter: transformed bbox: [$x1, $y1, $x2, $y2]');

        // Ensure the coordinates are in the correct order (top-left to bottom-right)
        double left = min(x1, x2);
        double top = min(y1, y2);
        double right = max(x1, x2);
        double bottom = max(y1, y2);

        // Draw bounding box
        canvas.drawRect(
          Rect.fromLTRB(left, top, right, bottom),
          boxPaint,
        );

        // Draw label
        final textSpan = TextSpan(
          text:
              ' ${detection.className} ${(detection.confidence * 100).toStringAsFixed(0)}% ',
          style: textStyle,
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, Offset(left, top - textPainter.height));

        // Draw mask if available
        if (detection.maskData != null) {
          print('DetectionPainter: has mask data');
          // This is a placeholder for mask rendering
          final maskRect = Rect.fromLTRB(left, top, right, bottom);
          canvas.drawRect(maskRect, maskPaint);
        }
      } catch (e) {
        print('DetectionPainter: Error rendering detection: $e');
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Helper function
double min(double a, double b) => a < b ? a : b;
double max(double a, double b) => a > b ? a : b;
