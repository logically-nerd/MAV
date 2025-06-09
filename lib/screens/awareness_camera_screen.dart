import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import '../services/surrounding_awareness/awareness_handler.dart';

class AwarenessCameraScreen extends StatefulWidget {
  const AwarenessCameraScreen({Key? key}) : super(key: key);

  @override
  State<AwarenessCameraScreen> createState() => _AwarenessCameraScreenState();
}

class _AwarenessCameraScreenState extends State<AwarenessCameraScreen> {
  final AwarenessHandler _awarenessHandler = AwarenessHandler.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          _awarenessHandler.handleTap();
        },
        child: Stack(
          children: [
            // Full-screen camera preview
            _buildCameraPreview(),

            // Small indicator at the top
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Awareness Mode Active',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            // Persistent instructions at the bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: const [
                      _CommandTile(
                        icon: Icons.touch_app,
                        text: 'Tap Once',
                        subtext: 'Scan',
                      ),
                      _CommandTile(
                        icon: Icons.double_arrow,
                        text: 'Double Tap',
                        subtext: 'Exit',
                      ),
                      _CommandTile(
                        icon: Icons.warning_amber,
                        text: 'Triple Tap',
                        subtext: 'Emergency',
                        color: Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to access camera preview without exposing private fields
  Widget _buildCameraPreview() {
    // Get access to camera controller through a safe method
    final controller = _awarenessHandler.getCameraController();

    if (controller != null && controller.value.isInitialized) {
      return SizedBox.expand(
        child: CameraPreview(controller),
      );
    } else {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }
  }
}

// Helper widget for the command instructions
class _CommandTile extends StatelessWidget {
  final IconData icon;
  final String text;
  final String subtext;
  final Color color;

  const _CommandTile({
    Key? key,
    required this.icon,
    required this.text,
    required this.subtext,
    this.color = Colors.white,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: color,
          size: 28,
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          subtext,
          style: TextStyle(
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
