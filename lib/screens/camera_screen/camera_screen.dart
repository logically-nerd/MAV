import 'package:flutter/material.dart';
import '../../services/camera_service/camera_service.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final CameraService _cameraService = CameraService();
   

  @override
  void initState() {
    super.initState();
     
  }

  Future<void> _captureImage() async {
    final image = await _cameraService.captureImage();
    if (image != null) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Text(
          'Camera Metadata:',
          style: TextStyle(fontSize: 24),
        ), 
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _captureImage,
          child: const Text('Capture Image'),
        ),
        const SizedBox(height: 20),
        _cameraService.exifData == null
            ? const Text(
                'No EXIF data available.',
                style: TextStyle(color: Colors.white),
              )
            : Expanded(
                child: ListView(
                  children: _cameraService.exifData!.entries.map((entry) {
                    return ListTile(
                      title: Text(
                        entry.key ?? 'default key',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        entry.value.toString(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    );
                  }).toList(),
                ),
              ),
      ],
    );
  }
}
