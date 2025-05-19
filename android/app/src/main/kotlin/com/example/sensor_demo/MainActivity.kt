package com.example.MAV

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private lateinit var cameraMetricsHelper: CameraMetricsHelper
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Create and store the instance
        cameraMetricsHelper = CameraMetricsHelper(this)
        
        // Initialize the camera
        cameraMetricsHelper.initializeCamera()
        
        // Set up the method channel for Flutter to call
        cameraMetricsHelper.setupMethodChannel(flutterEngine.dartExecutor.binaryMessenger)
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Clean up resources if needed
        // You might want to add a cleanup method to CameraMetricsHelper
    }
}