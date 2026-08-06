allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Temporary workaround: AGP 9's built-in Kotlin support isn't picked up by
// file_picker/package_info_plus/wakelock_plus's own build scripts (they skip
// `apply plugin: 'org.jetbrains.kotlin.android'` once they detect AGP >= 9,
// assuming built-in Kotlin compiles their .kt sources — it doesn't, on this
// AGP+Gradle combo, so e.g. FilePickerPlugin.kt silently never gets compiled
// and GeneratedPluginRegistrant.java fails with "找不到符号"). Force-apply the
// plugin here instead of downgrading AGP+Gradle wrapper together. Remove once
// these plugins ship an AGP-9-compatible fix upstream.
//
// 临时绕开方案：AGP 9 的内置 Kotlin 支持没有被 file_picker/package_info_plus/
// wakelock_plus 自己的构建脚本正确接住（它们检测到 AGP>=9 就跳过显式
// `apply plugin: 'org.jetbrains.kotlin.android'`，指望内置 Kotlin 编译它们的
// .kt 源码——在当前 AGP+Gradle 组合下并没有生效，导致
// `FilePickerPlugin.kt` 悄悄没被编译，`GeneratedPluginRegistrant.java` 报
// "找不到符号"）。这里强制补 apply，而不是把 AGP+Gradle wrapper 一起回退。
// 等这些插件上游修好 AGP 9 兼容问题后可以删掉。
subprojects {
    if (project.name in listOf("file_picker", "package_info_plus", "wakelock_plus")) {
        plugins.withId("com.android.library") {
            if (!project.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
                project.pluginManager.apply("org.jetbrains.kotlin.android")
            }
            // These plugins' own `kotlinOptions { jvmTarget = ... }` block also
            // lives inside the same `if (!isAgp9OrAbove)` branch we're bypassing
            // above, so Kotlin defaults to the toolchain's JVM (21) while Java
            // stays at the plugin's own `compileOptions` (17) — mismatch fails
            // the build. Pin Kotlin to match.
            //
            // 这些插件自己的 `kotlinOptions { jvmTarget = ... }` 也在同一个被
            // 绕开的 `if (!isAgp9OrAbove)` 分支里，导致 Kotlin 用工具链默认版本
            // （21）而 Java 仍是插件自己 `compileOptions` 里的 17——不一致导致
            // 构建失败，这里手动钉住一致。
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
