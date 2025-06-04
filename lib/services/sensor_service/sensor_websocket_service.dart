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
      _isConnected = true;
      // Optionally listen for messages or errors
      _channel!.stream.listen((message) {}, onError: (error) async {
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

  void disconnect() {
    _channel?.sink.close();
    _isConnected = false;
  }
}
