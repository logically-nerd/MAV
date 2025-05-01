import 'package:image_picker/image_picker.dart';
import 'package:exif/exif.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

class CameraService {
  final ImagePicker _picker = ImagePicker();
  XFile? _image;
  Map<String?, IfdTag>? _exifData;
  static const _channel = MethodChannel('camera_metrics');

  //  Getting focal lenght using method Channel
  static Future<Map<String, dynamic>> getMetrics() async {
    try {
      return Map<String, dynamic>.from(
          await _channel.invokeMethod('get_metrics'));
    } on PlatformException catch (e) {
      throw Exception("Failed to get metrics: ${e.message}");
    }
  }

  Future<double> getFocalLength() async {
    try {
      final double focalLength = await _channel.invokeMethod('getFocalLength');
      return focalLength;
    } on PlatformException catch (e) {
      print("Failed to get focal length: '");
      return 0.0;
    }
  }

  Future<XFile?> captureImage() async {
    try {
      final XFile? pickedImage =
          await _picker.pickImage(source: ImageSource.camera);
      if (pickedImage != null) {
        _image = pickedImage;
        await _extractExifData(pickedImage);
        await _saveImageToDirectory(pickedImage);
        return pickedImage;
      }
    } catch (e) {
      print('Error capturing image: $e');
    }
    return null;
  }

  Future<void> _extractExifData(XFile image) async {
    try {
      final bytes = await image.readAsBytes();
      final data = await readExifFromBytes(bytes);
      if (data == null) {
        throw Exception('No EXIF data found in the image.');
      }
      _exifData = data;
    } catch (e) {
      print('Error extracting EXIF data: $e');
    }
  }

  Future<void> _saveImageToDirectory(XFile image) async {
    try {
      if (await Permission.storage.request().isGranted) {
        final directory = await getDownloadsDirectory();
        final String publicPath = '${directory!.path}/${image.name}';
        await File(image.path).copy(publicPath);
        print('Image saved to: $publicPath');
      }
    } catch (e) {
      print('Error saving image: $e');
    }
  }

  Map<String?, IfdTag>? get exifData => _exifData;
  XFile? get currentImage => _image;
}
