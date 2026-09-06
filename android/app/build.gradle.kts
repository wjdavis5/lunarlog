import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wjdavis5.lunarlog"
    // flutter_secure_storage v11 compiles against Android SDK 37
    // (flutter.compileSdkVersion is 36 on this toolchain).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // U3 (R7): Prefab lets sentry-native-ndk consume sentry-android's
    // prefab-packaged native libs. Without this, enableNativeCrashHandling
    // in sentry_bootstrap.dart is a switch on a capability the build never
    // compiled in -- NDK crashes would not actually be captured.
    buildFeatures {
        prefab = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wjdavis5.lunarlog"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // flutter_secure_storage (DB key storage) requires minSdk 23.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                val storePath = keystoreProperties["storeFile"] as String
                storeFile = file(storePath)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (keystorePropertiesFile.exists() && releaseSigning.storeFile != null && releaseSigning.storeFile!!.exists()) {
                releaseSigning
            } else {
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
    // U3 (R7): real Android NDK crash capture. `sentry-native-ndk` carries
    // its own independent version series (0.x), separate from
    // `io.sentry:sentry-android`'s (8.x) -- a versionless declaration fails
    // to resolve (verified), and so does guessing the sentry-android
    // version. Pinned to 0.16.2, the exact version `io.sentry:sentry-
    // android-ndk:8.53.0` depends on internally per sentry-java's own
    // gradle/libs.versions.toml at that tag (sentry_flutter 9.28.0 pulls
    // sentry-android 8.53.0 as `api`, transitively pulling
    // sentry-android-ndk 8.53.0). Re-check this pin whenever sentry_flutter
    // is upgraded.
    implementation("io.sentry:sentry-native-ndk:0.16.2")
}

flutter {
    source = "../.."
}
