import 'dart:ui';
import 'package:MAV/services/safe_path_service/yolo_model.dart';
import 'package:flutter/material.dart';
import 'package:MAV/screens/intent_listener_widget.dart';
import 'package:MAV/screens/map_screen.dart';
import 'screens/camera_screen/camera_screen.dart';
import 'screens/sensor_screen/device_orientation.dart';
import 'package:camera/camera.dart';
import 'screens/yoloe_screen/websocket_client_yoloe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await requestRequiredPermissions();
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
  late List<CameraDescription> _cameras = [];
  // final YoloModel _yoloModel = YoloModel();

  @override
  void initState() {
    super.initState();
    _initializeCameras();
    testYoloPrediction();
  }

  Future<void> _initializeCameras() async {
    try {
      _cameras = await availableCameras();
      setState(() {});
    } catch (e) {
      debugPrint('Error initializing cameras: $e');
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
      // body:
    );
  }
}
