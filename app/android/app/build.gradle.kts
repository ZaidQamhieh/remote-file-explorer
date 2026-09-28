import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config (gitignored). Present locally (generated keystore) and
// recreated on the CI runner from GitHub secrets. Debug builds remain usable
// without release credentials; release task graphs are rejected below unless
// production signing is configured or a local test override is explicit.
// See android/.gitignore + .github/workflows/release.yml.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseSigning = keystorePropertiesFile.exists()
val allowDebugSigning = project.hasProperty("allowDebugSigning")
if (hasReleaseSigning) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Gradle configures every build type before it knows which variant task will
// run. Keep local debug installs working without release secrets, but reject
// any task graph that actually contains a release variant unless the owner
// explicitly opted into a debug-signed local release build.
if (!hasReleaseSigning && !allowDebugSigning) {
    gradle.taskGraph.whenReady {
        if (allTasks.any { it.name.contains("Release", ignoreCase = true) }) {
            throw GradleException(
                "Release build has no key.properties. Provide production " +
                    "signing, or pass -PallowDebugSigning for a local test build."
            )
        }
    }
}

android {
    namespace = "com.zqamhieh.remote_file_explorer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (L3, v1.24.0) requires desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zqamhieh.remote_file_explorer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion // mobile_scanner (QR pairing) requires API 23+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Use the dedicated upload key when key.properties is present
            // (local dev + CI release builds). The task-graph guard above
            // prevents a release build from using the debug key accidentally.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
