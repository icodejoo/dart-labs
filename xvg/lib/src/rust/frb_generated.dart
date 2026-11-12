// 平台入口：native 保留预编译库协议，web 使用同步初始化桥接。
export 'frb_generated.native.dart'
    if (dart.library.js_interop) 'frb_generated.web_init.dart';
