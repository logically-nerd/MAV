import 'package:flutter/material.dart';
import 'package:MAV/screens/intent_listener_widget.dart';
import 'package:MAV/screens/map_screen.dart';
import 'screens/camera_screen/camera_screen.dart';
import 'screens/sensor_screen/device_orientation.dart';
import 'package:camera/camera.dart';
import 'screens/yoloe_screen/websocket_client_yoloe.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MAV',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
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

  @override
  void initState() {
    super.initState();
    _initializeCameras();
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
        // body: MapScreen(),
        body: Stack(
          children: [
            const MapScreen(),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Center(
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 0.5, sigmaY: 0.5),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: Colors.black.withAlpha(10),
                      child: const IntentListenerWidget(),
                    ),
                  ),
                ),
              ),
            )
          ],
        ));
  }
}
