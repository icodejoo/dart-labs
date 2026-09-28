plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.icodejoo.mova.mova_example"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.icodejoo.mova.mova_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Local device testing only targets arm64 hardware; building the other
        // ABIs (notably x86_64) pointlessly drags in native modules like the
        // jni package's CMake config, which is broken for x86_64 on this
        // Windows toolchain (CMAKE_RC_COMPILER not set). Real releases should
        // remove this filter and let Play/CI produce the full ABI set.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

}

// libmpv.so no longer needs pickFirsts / a local jniLibs sync: the
// dependency_overrides on media_kit_libs_android_video (see
// example/pubspec.yaml -> packages/media_kit_libs_android_video_slim)
// replaces upstream's package wholesale, so it's the sole provider of
// libmpv.so / libmediakitandroidhelper.so in the dependency graph — there's
// nothing left to merge-conflict with. If that override is ever removed,
// upstream's own jar becomes the sole provider again, equally cleanly.

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
