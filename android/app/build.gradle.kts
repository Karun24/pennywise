plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Permanent signing key. On GitHub the workflow writes the key from the
// DEBUG_KEYSTORE_BASE64 secret and sets PENNYWISE_KEYSTORE_PATH. Using an
// explicit path (instead of relying on ~/.android/debug.keystore) guarantees
// every build has the same signature, so updates install over the old app.
val pennywiseKeystore: String? = System.getenv("PENNYWISE_KEYSTORE_PATH")

android {
    namespace = "com.pennywise.pennywise"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Needed by flutter_local_notifications (scheduled reminders).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.pennywise.pennywise"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("pennywise") {
            pennywiseKeystore?.let { path ->
                storeFile = file(path)
                storeType = "pkcs12"
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (pennywiseKeystore != null) {
                signingConfigs.getByName("pennywise")
            } else {
                // Local builds without the key fall back to the debug key.
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Recommended alongside desugaring to avoid crashes on Android 12L+.
    implementation("androidx.window:window:1.0.0")
    implementation("androidx.window:window-java:1.0.0")
    // AppCompat themes for the App lock fingerprint dialog.
    implementation("androidx.appcompat:appcompat:1.7.0")
}

flutter {
    source = "../.."
}
