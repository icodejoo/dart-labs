import 'dart:io';

/// Windows 文件换行符。
const bridgeCrlf = '\r\n';

/// 生成内容比较使用的统一换行符。
const bridgeLf = '\n';

/// 桥接检查成功时的统一提示。
const bridgeCheckSuccess = 'Native/web bridge consistency OK.';

/// native/web 共用的条件导出入口，防止普通 codegen 覆盖它。
const bridgeForwarder =
    '// 平台入口：native 保留预编译库协议，web 使用同步初始化桥接。\n'
    "export 'frb_generated.native.dart'\n"
    "    if (dart.library.js_interop) 'frb_generated.web_init.dart';\n";

/// native 初始化方法中需要替换为 web 同步调用的代码。
const nativeInitializer = '''
  Future<void> crateApiSimpleInitApp() {
    return handler.executeNormal(
      NormalTask(
        callFfi: (port_) {
          final serializer = SseSerializer(generalizedFrbRustBinding);
          pdeCallFfi(
            generalizedFrbRustBinding,
            serializer,
            funcId: 2,
            port: port_,
          );
''';

/// web 初始化方法的同步调用代码，其他 API 保持与 native 一致。
const webInitializer = '''
  void crateApiSimpleInitApp() {
    return handler.executeSync(
      SyncTask(
        callFfi: () {
          final serializer = SseSerializer(generalizedFrbRustBinding);
          return pdeCallFfi(generalizedFrbRustBinding, serializer, funcId: 2)!;
''';

/// 检查并替换唯一标记，缺失或重复均拒绝继续生成。
String replaceRequired(String source, String marker, String replacement) {
  if (marker.isEmpty || marker.allMatches(source).length != 1) {
    throw StateError('Expected exactly one codegen marker: $marker');
  }
  return source.replaceFirst(marker, replacement);
}

/// 从 native 桥接推导仅初始化方式不同的 web 桥接。
String expectedWebBridge(String native) {
  var expected = native.replaceAll(bridgeCrlf, bridgeLf);
  expected = replaceRequired(
    expected,
    '    await api.crateApiSimpleInitApp();',
    '    api.crateApiSimpleInitApp();',
  );
  expected = replaceRequired(
    expected,
    '  Future<void> crateApiSimpleInitApp();',
    '  void crateApiSimpleInitApp();',
  );
  return replaceRequired(expected, nativeInitializer, webInitializer);
}

/// 校验转发入口及 native/web 桥接，发现覆盖或 API 脱节时抛错。
void checkWebBridge(Directory root) {
  final directory = '${root.path}/lib/src/rust';
  final forwarder = File('$directory/frb_generated.dart').readAsStringSync();
  if (forwarder.replaceAll(bridgeCrlf, bridgeLf) != bridgeForwarder) {
    throw StateError(
      'frb_generated.dart was overwritten. Follow tool/README.md codegen steps.',
    );
  }
  final native = File('$directory/frb_generated.native.dart')
      .readAsStringSync();
  final web = File('$directory/frb_generated.web_init.dart').readAsStringSync();
  if (web.replaceAll(bridgeCrlf, bridgeLf) != expectedWebBridge(native)) {
    throw StateError(
      'Native/web bridge mismatch. Run dart run tool/generate_web_bridge.dart.',
    );
  }
}

/// 直接运行桥接一致性检查，失败时以非零状态退出。
void main() {
  checkWebBridge(File.fromUri(Platform.script).parent.parent);
  stdout.writeln(bridgeCheckSuccess);
}
