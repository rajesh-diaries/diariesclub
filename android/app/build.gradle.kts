import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing reads credentials from android/key.properties (gitignored,
// never committed). If the file is missing (fresh clone, CI without
// secrets), release builds fall back to the debug keystore — project still
// builds, but the produced AAB cannot be uploaded to Play Console.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}
val hasReleaseKey = keystorePropertiesFile.exists()

android {
    namespace = "com.diariesclub.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications and a few other plugins on
        // Android API < 26 to use modern java.time APIs.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.diariesclub.app"
        minSdk = flutter.minSdkVersion   // Android 6.0 — per Session 3 constraint
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    flavorDimensions += "default"
    productFlavors {
        create("dev") {
            dimension = "default"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Play Diaries Dev")
        }
        create("staging") {
            dimension = "default"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Play Diaries Staging")
        }
        create("prod") {
            dimension = "default"
            resValue("string", "app_name", "Play Diaries")
        }
        // Staff flavors (Session 10, phone-only per DECISION-001).
        // Different applicationId from the customer app so both can
        // coexist on the same device.
        create("staffDev") {
            dimension = "default"
            applicationId = "com.diariesclub.staff"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-staff-dev"
            resValue("string", "app_name", "Diaries Staff Dev")
        }
        create("staffProd") {
            dimension = "default"
            applicationId = "com.diariesclub.staff"
            versionNameSuffix = "-staff"
            resValue("string", "app_name", "Diaries Staff")
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Fallback so release builds still produce an artifact on
                // machines without the upload keystore (e.g. fresh clone).
                // Such an AAB cannot be uploaded to Play Console — it must
                // be re-signed on a machine that has key.properties.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
