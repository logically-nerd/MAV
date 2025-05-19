package com.example.MAV

import android.app.Activity
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class CameraMetricsHelper(private val activity: Activity) {
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    
    fun setupMethodChannel(messenger: BinaryMessenger) {
        MethodChannel(messenger, "camera_metrics").setMethodCallHandler { call, result ->
            when (call.method) {
                "get_metrics" -> {
                    val metrics = getCurrentMetrics()
                    result.success(metrics)
                }
                "getFocalLength" -> {
                    val focalLength = getCameraFocalLength()
                    if (focalLength != -1.0) {
                        result.success(focalLength)
                    } else {
                        result.error("UNAVAILABLE", "Focal length not available.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun getCurrentMetrics(): Map<String, Any> {
        // Use Camera2 API to get camera characteristics
        val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val cameraIds = cameraManager.cameraIdList
        
        if (cameraIds.isEmpty()) {
            return mapOf("error" to "No cameras available")
        }
        
        try {
            // Get the back camera (usually camera ID "0")
            val cameraId = cameraIds.first { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            }
            
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            
            // Get focal lengths - this will be an array in case of zoom lenses
            val focalLengths = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            val focalLength = focalLengths?.firstOrNull() ?: 4.2f
            
            // Get sensor size
            val sensorSize = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            val sensorHeight = sensorSize?.height ?: 3.6f
            
            return mapOf(
                "focalLength" to focalLength,
                "sensorHeight" to sensorHeight,
                "magnification" to (focalLength / 1000.0f).toDouble()  // Convert to double
            )
        } catch (e: Exception) {
            return mapOf("error" to "Failed to get camera metrics: ${e.message}")
        }
    }
    
    private fun getCameraFocalLength(): Double {
        try {
            val cameraManager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIds = cameraManager.cameraIdList
            
            if (cameraIds.isEmpty()) {
                return -1.0
            }
            
            // Get the back camera
            val cameraId = cameraIds.first { id ->
                val characteristics = cameraManager.getCameraCharacteristics(id)
                characteristics.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            }
            
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val focalLengths = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
            
            return focalLengths?.firstOrNull()?.toDouble() ?: -1.0
        } catch (e: Exception) {
            e.printStackTrace()
            return -1.0
        }
    }
    
    // Add a method to initialize the camera
    fun initializeCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(activity)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                camera = bindCamera()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }, ContextCompat.getMainExecutor(activity))
    }
    
    private fun bindCamera(): Camera? {
        val cameraProvider = cameraProvider ?: return null
        
        // Select back camera as a default
        val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
        
        try {
            // Unbind any bound use cases before rebinding
            cameraProvider.unbindAll()
            
            // Just bind to camera lifecycle without any use case
            return cameraProvider.bindToLifecycle(
                activity as androidx.lifecycle.LifecycleOwner,
                cameraSelector
            )
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
}