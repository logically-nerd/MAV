import com.android.build.gradle.internal.cxx.configure.gradleLocalProperties
import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    buildFeatures {
        buildConfig = true
    }

    namespace = "com.example.sensor_demo"
    
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    ndkVersion = "27.0.12077973"

   
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.sensor_demo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        
        val localProperties = Properties().apply {
            load(FileInputStream(rootProject.file("local.properties")))
        }
        val apiKey = localProperties.getProperty("GOOGLE_MAPS_API_KEY")
            ?: throw GradleException("Missing GOOGLE_MAPS_API_KEY in local.properties")
        
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = apiKey
        buildConfigField("String", "GOOGLE_MAPS_API_KEY", "\"$apiKey\"")
        
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
configurations.all {
    resolutionStrategy {
        force("com.google.guava:guava:31.0.1-android")
        exclude("com.google.guava", "listenablefuture")
    }
}


dependencies {
    implementation("com.google.guava:guava:31.0.1-android")

    // CameraX core library
    implementation("androidx.camera:camera-core:1.2.2")
    // CameraX Camera2 extensions
    implementation("androidx.camera:camera-camera2:1.2.2")
    // CameraX Lifecycle library
    implementation("androidx.camera:camera-lifecycle:1.2.2")
    // CameraX View class
    implementation("androidx.camera:camera-view:1.2.2")
}