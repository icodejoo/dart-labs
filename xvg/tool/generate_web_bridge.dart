// API 变更须先更新 native，再生成 web；完整顺序见 tool/README.md。
// --check 只读校验条件入口与两个生成变体，供 CI 使用。
import 'dart:io';

import 'check_web_bridge.dart';

/// 从同一 API 生成 web 同步初始化桥接，始终恢复 native 文件。
Future<void> main(List<String> args) async {
  final root = File.fromUri(Platform.script).parent.parent;
  if (args.isNotEmpty) {
    if (args.length != 1 || args.single != '--check') {
      throw ArgumentError('Usage: generate_web_bridge.dart [--check]');
    }
    checkWebBridge(root);
    stdout.writeln(bridgeCheckSuccess);
    return;
  }
  final paths = [
    'rust/src/api/simple.rs',
    'rust/src/frb_generated.rs',
    'lib/src/rust/frb_generated.dart',
    'lib/src/rust/frb_generated.io.dart',
    'lib/src/rust/frb_generated.web.dart',
    'lib/src/rust/api/simple.dart',
    'lib/src/rust/api/svg.dart',
  ];
  final backups = {
    for (final path in paths)
      path: File('${root.path}/$path').readAsBytesSync(),
  };
  try {
    final api = File('${root.path}/${paths.first}');
    api.writeAsStringSync(
      replaceRequired(api.readAsStringSync(), 'frb(init)', 'frb(init, sync)'),
    );
    final process = await Process.start(
      'flutter_rust_bridge_codegen',
      ['generate'],
      workingDirectory: root.path,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result != 0) throw StateError('FRB codegen failed: $result');
    copyGenerated(
      File('${root.path}/rust/src/frb_generated.rs'),
      File('${root.path}/rust/src/frb_generated_web.rs'),
    );
    copyGenerated(
      File('${root.path}/lib/src/rust/frb_generated.dart'),
      File('${root.path}/lib/src/rust/frb_generated.web_init.dart'),
    );
  } finally {
    for (final entry in backups.entries) {
      File('${root.path}/${entry.key}').writeAsBytesSync(entry.value);
    }
  }
  checkWebBridge(root);
}

/// 保存生成内容并沿用目标文件已有换行符，避免本机 codegen 改写整份文件风格。
void copyGenerated(File source, File destination) {
  final lineEnding =
      destination.existsSync() &&
          destination.readAsStringSync().contains(bridgeCrlf)
      ? bridgeCrlf
      : bridgeLf;
  final generated = source.readAsStringSync().replaceAll(bridgeCrlf, bridgeLf);
  destination.writeAsStringSync(generated.replaceAll(bridgeLf, lineEnding));
}
