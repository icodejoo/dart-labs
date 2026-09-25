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

    // media_kit_libs_android_video ships its own libmpv.so; ours (from
    // libmpv/, src/main/jniLibs/arm64-v8a/) must win the merge so
    // the slimmed build actually ships instead of upstream's ~11.8MiB one.
    packaging {
        jniLibs {
            pickFirsts += "**/libmpv.so"
        }
    }
}

// libmpv/<abi>/libmpv.so is the CI-rebuilt artifact (LFS);
// src/main/jniLibs/<abi>/libmpv.so is what Gradle actually packages. These
// used to drift silently (CI never wrote to jniLibs/) — sync on every build
// so jniLibs/ can't go stale again.
val syncMovaLibmpv by tasks.registering(Copy::class) {
    val distDir = layout.projectDirectory.dir("../../../libmpv")
    listOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64").forEach { abi ->
        from(distDir.dir(abi).file("libmpv.so")) {
            into(abi)
        }
    }
    destinationDir = file("src/main/jniLibs")
}

tasks.named("preBuild") {
    dependsOn(syncMovaLibmpv)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
