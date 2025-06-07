import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../services/conversation_service/conversation_service.dart';
import '../services/conversation_service/sos_service.dart';

class IntentListenerWidget extends StatefulWidget {
  const IntentListenerWidget({Key? key}) : super(key: key);

  @override
  State<IntentListenerWidget> createState() => _IntentListenerWidgetState();
}

class _IntentListenerWidgetState extends State<IntentListenerWidget> {
  final _conversationService = ConversationService.instance;
  bool _isListening = false;
  double _circleSize = 100.0;
  Color buttonColor = Colors.green;
  String buttonText = "Double Tap\nVoice Command";

  Timer? _tapTimer; // Timer to resolve tap conflicts
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _preloadServices();
  }

  Future<void> _preloadServices() async {
    print('[UI] Preloading conversation services');
    await _conversationService.preload();
  }

  Future<void> _startListening() async {
    if (_isListening) return;

    setState(() {
      _isListening = true;
      buttonColor = Colors.blue;
      buttonText = "Listening...";
      _circleSize = 150.0;
    });

    print("[UI] Starting voice command...");
    await _conversationService.listenAndClassify();

    setState(() {
      _isListening = false;
      buttonColor = Colors.green;
      buttonText = "Start Voice Command";
      _circleSize = 100.0;
    });
  }

  void _handleTapCount(int count) {
    if (count == 3) {
      print('[UI] Triple tap detected. Triggering SOS.');
      SOSService.instance.triggerSOS();
    } else if (count == 2) {
      print('[UI] Double tap detected. Starting voice command.');
      _startListening();
    } else if (count == 1) {
      print('[UI] Single tap detected. Starting voice command.');
      _startListening();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      gestures: {
        SerialTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<SerialTapGestureRecognizer>(
                SerialTapGestureRecognizer.new,
                (SerialTapGestureRecognizer instance) {
          instance.onSerialTapDown = (SerialTapDownDetails details) {
            _tapCount = details.count;

            _tapTimer?.cancel(); // Cancel existing timer
            _tapTimer = Timer(const Duration(milliseconds: 300), () {
              _handleTapCount(_tapCount);
              _tapCount = 0;
            });
          };
        }),
      },
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {
            print('[UI] Tap detected. Starting voice command.');
            _startListening();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _circleSize,
            height: _circleSize,
            decoration: BoxDecoration(
              color: buttonColor.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              "$buttonText",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tapTimer?.cancel();
    super.dispose();
  }
}
