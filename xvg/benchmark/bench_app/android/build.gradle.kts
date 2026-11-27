allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// 真机基准可在构建时用工作区产物替换插件的 JNI 输入目录。
if (providers.environmentVariable("XVG_BENCH_JNI_DIR").isPresent) {
    apply(from = "xvg-bench-jni.gradle")
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
