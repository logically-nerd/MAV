import 'dart:ui';
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
  // late List<CameraDescription> _cameras = [];
  // List<YOLOResult> _latestResults = [];

  // ++ Add Pipeline Controller instance ++
  late NavigationPipelineController _pipelineController;
  NavigationPipelineOutput?
      _latestPipelineOutput; // To store and display output

  @override
  void initState() {
    super.initState();
    // _initializeCameras();
    _pipelineController = NavigationPipelineController();
    print("HomePage: NavigationPipelineController initialized.");
  }

  @override
  void dispose() {
    // TODO: implement dispose
    super.dispose();
    KeepScreenOn.turnOff();
  }

  // Future<void> _initializeCameras() async {
  //   try {
  //     _cameras = await availableCameras();
  //     setState(() {});
  //   } catch (e) {
  //     debugPrint('Error initializing cameras: $e');
  //   }
  // }

  void _onResultsReceived(List<YOLOResult> results) async {
    print(
        "=========================================================================================================");
    print(results);
    print(
        "=========================================================================================================");
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
        // _latestResults = results; // If you still need to store raw yolo results
        _latestPipelineOutput = pipelineOutput;
      });

      // Log the JSON output (or parts of it)
      print("--- PIPELINE OUTPUT ---");
      print(
          "Navigation Command: ${pipelineOutput.navigationCommand.primaryAction} towards ${pipelineOutput.navigationCommand.targetSurface}");
      print("Voice Command: ${pipelineOutput.accessibility.voiceCommand}");
      // print("Full JSON: ${jsonEncode(pipelineOutput.toJson())}"); // Can be very verbose
      print("-----------------------");
    } catch (e, stackTrace) {
      print("HomePage: Error processing frame with navigation pipeline: $e");
      print("Stack trace: $stackTrace");
      // Optionally set a default/error state for _latestPipelineOutput
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
      // body: Stack(
      //   children: [
      //     const MapScreen(),
      //     Positioned(
      //       top: 0,
      //       left: 0,
      //       right: 0,
      //       bottom: 0,
      //       child: Center(
      //         child: ClipRect(
      //           child: BackdropFilter(
      //             filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
      //             child: Container(
      //               width: double.infinity,
      //               height: double.infinity,
      //               color: Colors.black.withAlpha(10),
      //               child: const IntentListenerWidget(),
      //             ),
      //           ),
      //         ),
      //       ),
      //     )
      //   ],
      // )
      // body: YoloSegmentation(
      //   modelAssetPath: 'assets/models/v11_best_float32.tflite',
      //   task: YOLOTask.segment,
      //   showControls: false,
      //   onResultsUpdated: _onResultsReceived,
      // ),
      body: Column(
        // Changed to Column to display pipeline output potentially
        children: [
          Expanded(
            flex: 3, // Give more space to camera view
            child: YoloSegmentation(
              modelAssetPath: 'assets/models/v11_best_float32.tflite',
              task: YOLOTask.segment,
              showControls:
                  false, // Set to true if you want YOLO controls visible
              onResultsUpdated: _onResultsReceived,
            ),
          ),
          // Optionally display some pipeline output for debugging
          if (_latestPipelineOutput != null)
            Expanded(
              flex: 1, // Less space for debug text
              child: Container(
                padding: const EdgeInsets.all(8.0),
                color: Colors.grey[200],
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Pipeline Debug Output:",
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                          "Command: ${_latestPipelineOutput!.navigationCommand.primaryAction}"),
                      Text(
                          "Target: ${_latestPipelineOutput!.navigationCommand.targetSurface}"),
                      Text(
                          "Confidence: ${(_latestPipelineOutput!.navigationCommand.confidence * 100).toStringAsFixed(1)}%"),
                      Text(
                          "Reason: ${_latestPipelineOutput!.navigationCommand.reason}"),
                      Text(
                          "Voice: ${_latestPipelineOutput!.accessibility.voiceCommand}"),
                      const SizedBox(height: 8),
                      Text(
                          "Best Zone: ${_latestPipelineOutput!.zoneAnalysis.currentBestZoneId}"),
                      Text("Scores:"),
                      ..._latestPipelineOutput!.zoneAnalysis.scores.entries
                          .map((e) =>
                              Text("  ${e.key}: ${e.value.toStringAsFixed(2)}"))
                          .toList(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
