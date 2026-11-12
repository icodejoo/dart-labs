import 'dart:js_interop';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart'
    as web;

import 'package:xvg/xvg.dart';

/// example/index.html 创建的 wasm 加载承诺，避免 FRB 再次插入同一脚本。
@JS('xvgReady')
external JSPromise<JSAny?> get _ready;

/// 等待宿主页加载 wasm，再使用同步 web 桥接初始化。
Future<void> initializeDemo() async {
  await _ready.toDart;
  // 此文件仅在 web 导入；dynamic 避免 VM 分析器把平台条件类型解析为 io。
  final dynamic library = const web.ExternalLibrary(
    debugInfo: 'example index.html initialized wasm',
    wasmBindgenName: 'wasm_bindgen',
  );
  await RustLib.init(externalLibrary: library);
}
