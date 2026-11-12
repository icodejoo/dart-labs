package com.example.bench_app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    // Benchmark only: make the system create the app-specific external files dir
    // (/storage/emulated/0/Android/data/<id>/files) with the right owner before Dart
    // writes the report / screenshots there; a plain mkdir from Dart is denied.
    // 仅基准用：让系统先建好应用专属外部目录（属主正确），Dart 再往里写报告/截图；
    // 直接在 Dart 里 mkdir 会被拒绝。
    override fun onCreate(savedInstanceState: Bundle?) {
        getExternalFilesDir(null)
        super.onCreate(savedInstanceState)
    }
}
