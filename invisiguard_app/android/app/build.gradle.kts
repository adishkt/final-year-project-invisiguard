plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.example.invisiguard_app"
    compileSdk = flutter.compileSdkVersion.toInt()
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // 🔥 ADD THIS LINE - Enable core library desugaring
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.invisiguard_app"
        
        // Convert to Int to avoid null issues
        minSdk = flutter.minSdkVersion.toInt()
        targetSdk = flutter.targetSdkVersion.toInt()
        
        // Safely get version code and name with defaults
        val flutterVersionCode = System.getenv("FLUTTER_VERSION_CODE")?.toIntOrNull() ?: 1
        val flutterVersionName = System.getenv("FLUTTER_VERSION_NAME") ?: "1.0.0"
        
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        // ⚠️ REMOVE THIS DUPLICATE LINE - you already set minSdk above
        // minSdk = flutter.minSdkVersion
        // Safely get MAPS_API_KEY
        val mapsApiKey = project.findProperty("MAPS_API_KEY") as? String ?: ""
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        
        // 🔥 ADD THIS ONLY IF YOUR minSdk IS 20 OR LOWER
        // Check your Flutter project's android/local.properties or your Flutter config
        // multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 🔥 ADD THIS DEPENDENCY - Core library desugaring
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    
    implementation(platform("com.google.firebase:firebase-bom:34.7.0"))
    implementation("com.google.firebase:firebase-analytics")
}