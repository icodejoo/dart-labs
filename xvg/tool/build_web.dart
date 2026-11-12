import 'dart:io';

/// Rust 构建命令。
const _cargo = 'cargo';

/// 与锁文件保持一致的 wasm 绑定工具。
const _wasmBindgen = 'wasm-bindgen';

/// 可选的 wasm 优化工具。
const _wasmOpt = 'wasm-opt';

/// 工具版本查询参数。
const _versionFlag = '--version';

/// 构建目标参数。
const _targetFlag = '--target';

/// 构建 GitHub Pages 使用的无模块 wasm 产物，不需要共享内存。
Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  final rust = '${root.path}/rust';
  final output = '${root.path}/example/web/pkg';
  await checkWasmBindgenVersion(File('$rust/Cargo.lock'));
  await Directory(output).create(recursive: true);
  await run(_cargo, [
    '+nightly-2026-06-24',
    'build',
    '--locked',
    '--release',
    _targetFlag,
    'wasm32-unknown-unknown',
    '--target-dir',
    '$rust/target',
  ], rust);
  await run(_wasmBindgen, [
    _targetFlag,
    'no-modules',
    '--out-name',
    'xvg',
    '--out-dir',
    output,
    '$rust/target/wasm32-unknown-unknown/release/xvg.wasm',
  ], rust);
  try {
    final probe = await Process.run(_wasmOpt, [_versionFlag]);
    if (probe.exitCode != 0) throw const ProcessException(_wasmOpt, []);
  } on ProcessException {
    stdout.writeln('wasm-opt unavailable; skipping optional optimization.');
    return;
  }
  final wasm = '$output/xvg_bg.wasm';
  await run(_wasmOpt, ['-Oz', '--all-features', wasm, '-o', '$wasm.opt'], rust);
  await File('$wasm.opt').rename(wasm);
}

/// 从锁文件读取绑定版本，构建前拒绝与本机 CLI 不匹配的工具链。
Future<void> checkWasmBindgenVersion(File lockfile) async {
  final expected = wasmBindgenVersion(lockfile.readAsStringSync());
  final install = 'cargo install wasm-bindgen-cli --version $expected --locked';
  ProcessResult result;
  try {
    result = await Process.run(_wasmBindgen, [_versionFlag]);
  } on ProcessException {
    throw StateError('$_wasmBindgen unavailable. Install with: $install');
  }
  final actual = result.stdout.toString().trim();
  if (result.exitCode != 0 || actual != '$_wasmBindgen $expected') {
    throw StateError(
      '$_wasmBindgen version mismatch: expected $expected, got "$actual". '
      'Install with: $install',
    );
  }
}

/// 读取 Cargo.lock 中唯一的 wasm-bindgen 包版本，缺失或重复时拒绝构建。
String wasmBindgenVersion(String lockfile) {
  final versions = <String>[];
  for (final block in lockfile.replaceAll('\r\n', '\n').split('[[package]]')) {
    if (RegExp(r'^name = "wasm-bindgen"$', multiLine: true).hasMatch(block)) {
      final version = RegExp(
        r'^version = "([^"]+)"$',
        multiLine: true,
      ).firstMatch(block);
      if (version != null) versions.add(version.group(1)!);
    }
  }
  if (versions.length != 1) {
    throw StateError(
      'Cargo.lock must contain exactly one wasm-bindgen version.',
    );
  }
  return versions.single;
}

/// 透传构建日志并在任一工具失败时停止。
Future<void> run(String executable, List<String> args, String directory) async {
  stdout.writeln('$executable ${args.join(' ')}');
  final process = await Process.start(
    executable,
    args,
    environment: executable == _cargo ? {'RUSTC_WRAPPER': ''} : null,
    workingDirectory: directory,
    mode: ProcessStartMode.inheritStdio,
  );
  final result = await process.exitCode;
  if (result != 0) exit(result);
}
