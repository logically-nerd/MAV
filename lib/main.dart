import 'dart:ui';
import 'package:MAV/screens/map_screen.dart';
import 'package:MAV/services/safe_path_service/calibration_service.dart';
import 'package:MAV/services/safe_path_service/pipeline_controller.dart';
import 'package:MAV/services/safe_path_service/pipeline_models.dart';
import 'package:MAV/services/safe_path_service/yolo_segmentation.dart';
import 'package:flutter/material.dart';
import 'package:keep_screen_on/keep_screen_on.dart';
import 'package:ultralytics_yolo/yolo_view.dart';
import 'screens/sensor_screen/device_orientation.dart';
import 'package:MAV/screens/intent_listener_widget.dart';
import 'screens/sensor_screen/device_orientation.dart';
import 'package:camera/camera.dart';
import 'screens/yoloe_screen/websocket_client_yoloe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:ultralytics_yolo/yolo_result.dart';
import 'package:ultralytics_yolo/yolo_task.dart';
import 'package:flutter_tts/flutter_tts.dart'; // Add TTS import
import 'dart:async'; // Add for Timer

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KeepScreenOn.turnOn();
  await dotenv.load(fileName: ".env");
  await requestRequiredPermissions();
  // Initialize cameras and calibration before running the app
  final cameras = await availableCameras();
  if (cameras.isNotEmpty) {
    // Initialize CameraController to get the preview size
    final controller = CameraController(cameras[0], ResolutionPreset.high);
    await controller.initialize();
    final previewSize = controller.value.previewSize;
    if (previewSize != null) {
      await CalibrationService.initializeCalibration(
        cameraPreviewWidth: previewSize.width.toInt(),
        cameraPreviewHeight: previewSize.height.toInt(),
      );
    } else {
      print("Preview size is null, using fallback values");
      await CalibrationService.initializeCalibration(
        cameraPreviewWidth: 640,
        cameraPreviewHeight: 480,
      );
    }
    // Dispose controller if needed, depending on your app structure
    await controller.dispose();
  } else {
    print("No cameras available for calibration");
  }
  runApp(const MyApp());
}

Future<void> requestRequiredPermissions() async {
  print("PERMISSIONS: Requesting all required permissions");
  await _requestLocationPermission();
  await _requestMicrophonePermission();
  await _requestCameraPermission();
  await _requestStoragePermission();
  print("PERMISSIONS: All permission requests completed");
}

Future<void> _requestLocationPermission() async {
  print("PERMISSIONS: Requesting location permission");
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    print("PERMISSIONS: Location services are disabled");
    return;
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    print("PERMISSIONS: Location permission status after request: $permission");
  } else {
    print("PERMISSIONS: Location permission already granted: $permission");
  }
}

Future<void> _requestMicrophonePermission() async {
  print("PERMISSIONS: Requesting microphone permission");
  PermissionStatus status = await Permission.microphone.request();
  print("PERMISSIONS: Microphone permission status: $status");

  final speech = stt.SpeechToText();
  bool available = await speech.initialize();
  print("PERMISSIONS: Speech recognition available: $available");
}

Future<void> _requestCameraPermission() async {
  print("PERMISSIONS: Requesting camera permission");
  PermissionStatus status = await Permission.camera.request();
  print("PERMISSIONS: Camera permission status: $status");

  try {
    final cameras = await availableCameras();
    print("PERMISSIONS: Found ${cameras.length} cameras");
  } catch (e) {
    print("PERMISSIONS: Error initializing cameras: $e");
  }
}

Future<void> _requestStoragePermission() async {
  print("PERMISSIONS: Requesting storage permission");
  PermissionStatus status = await Permission.storage.request();
  print("PERMISSIONS: Storage permission status: $status");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MAV',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepOrangeAccent,
          brightness: Brightness.light,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // ++ Add Pipeline Controller instance ++
  late NavigationPipelineController _pipelineController;
  NavigationPipelineOutput?
      _latestPipelineOutput; // To store and display output

  // TTS Integration
  late FlutterTts _flutterTts;
  bool _isTtsInitialized = false;
  bool _isModelReady = false;
  String? _lastCommand;
  DateTime? _lastPromptTime;
  Timer? _periodicTimer;

  static const Duration PERIODIC_INTERVAL = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _pipelineController = NavigationPipelineController();
    _initializeTts();
    print("HomePage: NavigationPipelineController initialized.");
  }

  @override
  void dispose() {
    super.dispose();
    _periodicTimer?.cancel();
    _flutterTts.stop();
    KeepScreenOn.turnOff();
  }

  Future<void> _initializeTts() async {
    _flutterTts = FlutterTts();

    // Configure TTS settings
    await _flutterTts.setLanguage('en-US');
    await _flutterTts.setSpeechRate(0.8);
    await _flutterTts.setVolume(0.8);
    await _flutterTts.setPitch(1.0);

    _isTtsInitialized = true;
    print('TTS initialized');
  }

  Future<void> _speakModelReady() async {
    if (!_isTtsInitialized) await _initializeTts();
    await _flutterTts.speak("Navigation model is ready and running");
    print('TTS: Navigation model is ready and running');
  }

  Future<void> _speakNavigationCommand(String command) async {
    if (!_isTtsInitialized) await _initializeTts();

    DateTime now = DateTime.now();
    bool shouldSpeak = false;

    // Speak if command changed
    if (_lastCommand != command) {
      shouldSpeak = true;
      _lastCommand = command;
    }
    // Speak if 5 seconds have passed since last prompt
    else if (_lastPromptTime == null ||
        now.difference(_lastPromptTime!) >= PERIODIC_INTERVAL) {
      shouldSpeak = true;
    }

    if (shouldSpeak) {
      _lastPromptTime = now;
      String spokenText = _formatCommandForSpeech(command);
      await _flutterTts.speak(spokenText);
      print('TTS: $spokenText');
    }
  }

  String _formatCommandForSpeech(String command) {
    // Convert technical commands to natural speech
    switch (command.toLowerCase()) {
      case 'move_forward':
        return 'Move forward';
      case 'turn_left':
        return 'Turn left';
      case 'turn_right':
        return 'Turn right';
      case 'move_left':
        return 'Move left';
      case 'move_right':
        return 'Move right';
      case 'stop':
        return 'Stop';
      case 'slow_down':
        return 'Slow down';
      case 'no_detection':
        return 'Cannot detect walkable path. Please move slowly';
      case 'processing_error':
        return 'Navigation processing error. Please try again';
      default:
        return command.replaceAll('_', ' ');
    }
  }

  void _onResultsReceived(List<YOLOResult> results) async {
    print(
        "=========================================================================================================");
    print(results);
    print(
        "=========================================================================================================");

    // Announce model ready on first successful processing
    if (!_isModelReady) {
      _isModelReady = true;
      await _speakModelReady();
    }

    // Check if no detections found
    if (results.isEmpty) {
      await _speakNavigationCommand("no_detection");
      print("No detections found - guiding user");
      return;
    }
    for (var result in results) {
      print(
          'Detected: ${result.className} | Confidence: ${result.confidence} ');
      print('Mask:');
      print("Datatye: ${result.mask.runtimeType}");
      print("Mask Lenght: ${result.mask!.length}");
      print("Mask[0] Lenght: ${result.mask![0].length}");
      print("*" * 150);
    }
    // --- Call the Navigation Pipeline ---
    try {
      NavigationPipelineOutput pipelineOutput =
          await _pipelineController.processFrame(results);

      setState(() {
        _latestPipelineOutput = pipelineOutput;
      });

      // Speak navigation command with smart timing
      String command = pipelineOutput.navigationCommand.primaryAction;
      await _speakNavigationCommand(command);

      // Log the JSON output (or parts of it)
      print("--- PIPELINE OUTPUT ---");
      print(
          "Navigation Command: ${pipelineOutput.navigationCommand.primaryAction} towards ${pipelineOutput.navigationCommand.targetSurface}");
      print("Voice Command: ${pipelineOutput.accessibility.voiceCommand}");
      print("-----------------------");
    } catch (e, stackTrace) {
      print("HomePage: Error processing frame with navigation pipeline: $e");
      print("Stack trace: $stackTrace");
      // Fallback for processing errors
      await _speakNavigationCommand("processing_error");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 0, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            spacing: 13,
            children: [
              Text(
                'MAV',
                style: GoogleFonts.tektur(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  color: const Color.fromARGB(215, 255, 255, 255),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.blueAccent,
      ),
      // body: Column(
      //   children: [
      //     Expanded(
      //       flex: 4, // Increased space for camera view
      //       child: YoloSegmentation(
      //         modelAssetPath: 'assets/models/v11_best_float32.tflite',
      //         task: YOLOTask.segment,
      //         showControls: false,
      //         onResultsUpdated: _onResultsReceived,
      //       ),
      //     ),

      //     // Clean status display instead of debug info
      //     Container(
      //       height: 80,
      //       width: double.infinity,
      //       color: Colors.black87,
      //       child: Center(
      //         child: Column(
      //           mainAxisAlignment: MainAxisAlignment.center,
      //           children: [
      //             if (_latestPipelineOutput != null)
      //               Text(
      //                 _formatCommandForSpeech(_latestPipelineOutput!
      //                         .navigationCommand.primaryAction)
      //                     .toUpperCase(),
      //                 style: TextStyle(
      //                   color: Colors.white,
      //                   fontSize: 24,
      //                   fontWeight: FontWeight.bold,
      //                 ),
      //               )
      //             else
      //               Text(
      //                 _isModelReady ? 'READY' : 'INITIALIZING...',
      //                 style: TextStyle(
      //                   color: Colors.white70,
      //                   fontSize: 18,
      //                 ),
      //               ),
      //             if (_latestPipelineOutput != null)
      //               Text(
      //                 'Confidence: ${(_latestPipelineOutput!.navigationCommand.confidence * 100).toStringAsFixed(1)}%',
      //                 style: TextStyle(color: Colors.white70, fontSize: 14),
      //               ),
      //           ],
      //         ),
      //       ),
      //     ),

      //     /*
      //     // COMMENTED OUT: Debug info - can be re-enabled later if needed
      //     if (_latestPipelineOutput != null)
      //       Expanded(
      //         flex: 1,
      //         child: Container(
      //           padding: const EdgeInsets.all(8.0),
      //           color: Colors.grey[200],
      //           child: SingleChildScrollView(
      //             child: Column(
      //               crossAxisAlignment: CrossAxisAlignment.start,
      //               children: [
      //                 Text("Pipeline Debug Output:", style: Theme.of(context).textTheme.titleMedium),
      //                 const SizedBox(height: 8),
      //                 Text("Command: ${_latestPipelineOutput!.navigationCommand.primaryAction}"),
      //                 Text("Target: ${_latestPipelineOutput!.navigationCommand.targetSurface}"),
      //                 Text("Confidence: ${(_latestPipelineOutput!.navigationCommand.confidence * 100).toStringAsFixed(1)}%"),
      //                 Text("Reason: ${_latestPipelineOutput!.navigationCommand.reason}"),
      //                 Text("Voice: ${_latestPipelineOutput!.accessibility.voiceCommand}"),
      //                 const SizedBox(height: 8),
      //                 Text("Best Zone: ${_latestPipelineOutput!.zoneAnalysis.currentBestZoneId}"),
      //                 Text("Scores:"),
      //                 ..._latestPipelineOutput!.zoneAnalysis.scores.entries
      //                     .map((e) => Text("  ${e.key}: ${e.value.toStringAsFixed(2)}"))
      //                     .toList(),
      //               ],
      //             ),
      //           ),
      //         ),
      //       ),
      //     */
      //   ],
      // ),

      body: Stack(
        children: [
          // Main Content: Camera view and status bar
          Column(
            children: [
              Expanded(
                flex: 4,
                child: YoloSegmentation(
                  modelAssetPath: 'assets/models/v11_best_float32.tflite',
                  task: YOLOTask.segment,
                  showControls: false,
                  onResultsUpdated: _onResultsReceived,
                ),
              ),
              Container(
                height: 80,
                width: double.infinity,
                color: Colors.black87,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_latestPipelineOutput != null)
                        Text(
                          _formatCommandForSpeech(_latestPipelineOutput!
                                  .navigationCommand.primaryAction)
                              .toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        Text(
                          _isModelReady ? 'READY' : 'INITIALIZING...',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                          ),
                        ),
                      if (_latestPipelineOutput != null)
                        Text(
                          'Confidence: ${(_latestPipelineOutput!.navigationCommand.confidence * 100).toStringAsFixed(1)}%',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Top-right floating map
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              width: 110,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const MapScreen(),
            ),
          ),

          // High z-index full-screen overlay
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                child: Container(
                  color: Colors.black.withAlpha(10),
                  child: const IntentListenerWidget(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}