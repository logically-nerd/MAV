import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_tts/flutter_tts.dart';

class SensorWebSocketService {
  final String serverUrl;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  final FlutterTts _tts = FlutterTts();

  SensorWebSocketService({required this.serverUrl});

  Future<void> connect() async {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _isConnected = true;      // Listen for messages or errors
      _channel!.stream.listen((message) async {
        try {
          final response = jsonDecode(message);
          if (response is Map && response['status'] == 'success' && response.containsKey('all_angles')) {
            final allAngles = response['all_angles'] as List;
            await _speakAllDirectionsResults(allAngles);
          }
        } catch (e) {
          // Ignore JSON or TTS errors
        }
      }, onError: (error) async {
        _isConnected = false;
        await _speakConnectionError();
      }, onDone: () async {
        _isConnected = false;
        await _speakConnectionError();
      });
    } catch (e) {
      _isConnected = false;
      await _speakConnectionError();
    }
  }

  String _angleToPosition(dynamic angle) {
    // Accept int or double
    int a = 0;
    if (angle is int) a = angle;
    if (angle is double) a = angle.round();
    switch (a) {
      case 0:
        return 'front';
      case 90:
        return 'right';
      case 180:
        return 'back';
      case 270:
        return 'left';
      default:
        return 'unknown position';
    }
  }

  Future<void> sendImageWithAngle(Uint8List imageBytes, double angle) async {
    if (!_isConnected || _channel == null) {
      await _speakConnectionError();
      return;
    }
    try {
      final base64Image = base64Encode(imageBytes);
      final message = jsonEncode({
        'type': 'image',
        'data': base64Image,
        'format': 'png',
        'angle': angle,
      });
      _channel!.sink.add(message);
    } catch (e) {
      await _speakConnectionError();
    }
  }

  Future<void> _speakConnectionError() async {
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.35);
    await _tts.speak("Unable to tell surrounding awareness");
  }
  Future<void> _speakAllDirectionsResults(List allAngles) async {
    Map<String, List<String>> directionObjects = {
      'front': [],
      'right': [],
      'back': [],
      'left': [],
    };

    // Collect all objects for each direction
    for (final angleResult in allAngles) {
      final angle = angleResult['angle'];
      final detectionResults = angleResult['detection_results'];
      String position = _angleToPosition(angle);
      
      if (detectionResults != null && detectionResults['objects'] is List) {
        final objects = detectionResults['objects'] as List;
        final objectNames = objects.map((o) => o['class_name'] as String).toSet().toList();
        if (objectNames.isNotEmpty) {
          directionObjects[position]?.addAll(objectNames);
        }
      }
    }

    // Build comprehensive announcement
    List<String> announcements = [];
    
    directionObjects.forEach((direction, objects) {
      if (objects.isNotEmpty) {
        String objectList = objects.toSet().join(', ');
        announcements.add('At $direction: $objectList');
      } else {
        announcements.add('At $direction: no objects detected');
      }
    });

    // Speak the complete results
    String fullAnnouncement = 'Surrounding awareness complete. ${announcements.join('. ')}.';
    
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.4);
    await _tts.speak(fullAnnouncement);
  }

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }
}
