plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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

    flavorDimensions += "default"
    productFlavors {
        create("dev") {
            dimension = "default"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Diaries Club Dev")
        }
        create("staging") {
            dimension = "default"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Diaries Club Staging")
        }
        create("prod") {
            dimension = "default"
            resValue("string", "app_name", "Diaries Club")
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
            // TODO: real signing config for prod release builds.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}
