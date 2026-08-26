// Produces the precompiled native artifacts that svgx ships in `prebuilt/`.
//
// 产出 svgx 随包分发在 `prebuilt/` 下的预编译原生产物。
//
// Replaces cargokit: consumers no longer compile Rust at all, so this script
// (locally or in CI) is the only place the Rust crate is ever built for
// distribution.
//
// 取代 cargokit：下游不再编译 Rust，本脚本（本地或 CI）是唯一构建分发产物的地方。
//
// Usage / 用法:
//   dart run tool/build_prebuilt.dart --group windows
//   dart run tool/build_prebuilt.dart --group android --group windows
//   dart run tool/build_prebuilt.dart --target x86_64-pc-windows-msvc
//   dart run tool/build_prebuilt.dart --all          # host-buildable groups
//   dart run tool/build_prebuilt.dart --list
//
// Each group can only be built on a suitable host (Apple targets need macOS,
// MSVC targets need Windows, Linux targets need Linux); anything unbuildable on
// the current host is reported and skipped rather than faked.
//
// 每个分组只能在合适的宿主上构建（Apple 需 macOS、MSVC 需 Windows、Linux 需
// Linux）；当前宿主构建不了的会明确报告并跳过，而不是伪造产物。

import 'dart:io';

import 'prebuilt_common.dart';

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final root = packageRoot(Platform.script);

  if (args.contains('--list')) {
    for (final t in kTargets) {
      final where = t.output ?? '(lipo input only)';
      stdout.writeln(
        '${t.group.padRight(8)} ${t.triple.padRight(30)} -> $where',
      );
    }
    return 0;
  }

  // `--restage` refreshes MANIFEST.json from whatever is already present under
  // `prebuilt/`, without building anything. This is how the CI `package` job
  // registers slices produced on other runners (Apple on macOS, Linux on
  // ubuntu), and how a developer registers a binary cross-built by hand.
  //
  // `--restage` 不构建任何东西，只根据 `prebuilt/` 下已有文件刷新 MANIFEST.json。
  // CI 的 `package` job 靠它登记其它 runner 产出的 slice（Apple 在 macOS、Linux 在
  // ubuntu），开发者手工交叉编译出来的产物也用它登记。
  if (args.contains('--restage')) {
    final dir = Directory('${root.path}/prebuilt');
    if (!dir.existsSync()) {
      stderr.writeln('No prebuilt/ directory to restage.');
      return 1;
    }
    final found = <String>[];
    for (final e in dir.listSync(recursive: true)) {
      if (e is! File) continue;
      final rel = e.path.substring(dir.path.length + 1).replaceAll(r'\', '/');
      if (rel == 'MANIFEST.json') continue;
      found.add(rel);
    }
    found.sort();
    _updateManifest(root, found, _hostName());
    for (final f in found) {
      stdout.writeln('  staged prebuilt/$f');
    }
    return 0;
  }

  final groups = <String>{};
  final triples = <String>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--group':
        groups.add(args[++i]);
      case '--target':
        triples.add(args[++i]);
      case '--all':
        groups.addAll(kTargets.map((t) => t.group));
      case '--check':
      case '--restage':
      case '--list':
        break; // mode flags, handled above
      default:
        stderr.writeln('Unknown argument: ${args[i]}');
        return 2;
    }
  }
  if (groups.isEmpty && triples.isEmpty) {
    stderr.writeln(
      'Nothing selected. Pass --group <name>, --target <triple>, --all or --list.',
    );
    return 2;
  }

  final host = _hostName();
  final selected = kTargets
      .where((t) => groups.contains(t.group) || triples.contains(t.triple))
      .toList();

  final skipped = <PrebuiltTarget>[];
  final buildable = <PrebuiltTarget>[];
  for (final t in selected) {
    if (t.requiresHost != null && t.requiresHost != host) {
      skipped.add(t);
    } else {
      buildable.add(t);
    }
  }

  for (final t in skipped) {
    stdout.writeln(
      'SKIP ${t.triple}: requires a ${t.requiresHost} host (current host: $host).',
    );
  }
  if (buildable.isEmpty) {
    stderr.writeln('No selected target can be built on this host.');
    return 1;
  }

  // `--check` type-checks each target instead of producing artifacts. This is
  // the cheap CI sentinel: it catches platform-specific compile errors (a
  // `#[cfg(target_os)]` branch that stopped compiling, a dependency that does
  // not support a triple) on every push, without paying for a full LTO +
  // build-std release link per target.
  //
  // `--check` 只对每个 target 做类型检查，不产出产物。这是廉价的 CI 哨兵：每次
  // push 都能抓到平台相关的编译错误（某个 `#[cfg(target_os)]` 分支编不过、某个依赖
  // 不支持该三元组），而不必为每个 target 付出完整的 LTO + build-std 链接开销。
  if (args.contains('--check')) {
    var failed = 0;
    for (final t in buildable) {
      stdout.writeln('\n=== cargo check ${t.triple} ===');
      if (!await _checkTarget(root, t, host)) failed++;
    }
    if (failed > 0) {
      stderr.writeln('\n$failed target(s) failed to type-check.');
      return 1;
    }
    stdout.writeln('\nAll ${buildable.length} selected target(s) type-check.');
    return 0;
  }

  final built = <String, String>{}; // triple -> cargo output path
  for (final t in buildable) {
    stdout.writeln('\n=== building ${t.triple} ===');
    final artifact = await _buildTarget(root, t, host);
    if (artifact == null) return 1;
    built[t.triple] = artifact;
  }

  // Stage plain (non-lipo) outputs.
  // 落位普通（非 lipo）产物。
  final produced = <String>[];
  for (final t in buildable) {
    if (t.output == null) continue;
    if (t.group == 'macos') continue; // handled by the lipo step below
    final dest = File('${root.path}/prebuilt/${t.output}');
    dest.parent.createSync(recursive: true);
    File(built[t.triple]!).copySync(dest.path);
    produced.add(t.output!);
    stdout.writeln('  -> prebuilt/${t.output} (${dest.lengthSync()} bytes)');
  }

  // `lib/src/rust/frb_generated.dart` loads from `rust/target/release/` when
  // svgx runs outside a platform build (plain `flutter test`, scripts). The
  // build-std artifact lands in `target/<triple>/release/`, so mirror the host
  // dynamic library across.
  //
  // `lib/src/rust/frb_generated.dart` 在非平台构建场景（纯 `flutter test`、脚本）
  // 下从 `rust/target/release/` 加载。build-std 的产物落在
  // `target/<triple>/release/`，所以把宿主动态库镜像过去。
  for (final t in buildable) {
    if (t.cargoArtifact.endsWith('.a')) continue;
    if (t.triple != _hostTriple()) continue;
    final dest = File('${root.path}/rust/target/release/${t.cargoArtifact}');
    dest.parent.createSync(recursive: true);
    File(built[t.triple]!).copySync(dest.path);
    stdout.writeln('  -> rust/target/release/${t.cargoArtifact} (host loader)');
  }

  // Apple lipo merges: iOS simulator (arm64 + x86_64) and macOS universal.
  // Apple 侧 lipo 合并：iOS 模拟器（arm64 + x86_64）与 macOS 通用库。
  if (host == 'macos') {
    if (built.containsKey('aarch64-apple-ios-sim') &&
        built.containsKey('x86_64-apple-ios')) {
      await _lipo(root, [
        built['aarch64-apple-ios-sim']!,
        built['x86_64-apple-ios']!,
      ], 'ios/simulator/libsvgx.a');
      produced.add('ios/simulator/libsvgx.a');
    }
    if (built.containsKey('aarch64-apple-darwin') &&
        built.containsKey('x86_64-apple-darwin')) {
      await _lipo(root, [
        built['aarch64-apple-darwin']!,
        built['x86_64-apple-darwin']!,
      ], 'macos/libsvgx.a');
      produced.add('macos/libsvgx.a');
    }
  }

  _updateManifest(root, produced, host);

  stdout.writeln('\nDone. ${produced.length} artifact(s) written.');
  if (skipped.isNotEmpty) {
    stdout.writeln(
      'NOTE: ${skipped.length} target(s) skipped — they need a different host. '
      'Run this script there (or let CI do it) before publishing.',
    );
  }
  return 0;
}

/// Maps `Platform.operatingSystem` onto the names used by
/// [PrebuiltTarget.requiresHost].
///
/// 把 `Platform.operatingSystem` 映射成 [PrebuiltTarget.requiresHost] 用的名字。
String _hostName() => Platform.operatingSystem;

/// The host's own Rust target triple, as reported by `rustc -vV`.
///
/// 由 `rustc -vV` 报告的宿主机自身 Rust 目标三元组。
String? _hostTriple() {
  final r = Process.runSync('rustc', <String>['-vV'], runInShell: true);
  if (r.exitCode != 0) return null;
  for (final line in (r.stdout as String).split('\n')) {
    if (line.startsWith('host:')) return line.substring(5).trim();
  }
  return null;
}

/// Runs the release cargo build for one target and returns the absolute path of
/// the emitted artifact, or `null` if the build failed.
///
/// 为单个 target 跑 release 构建，返回产物绝对路径；失败时返回 `null`。
Future<String?> _buildTarget(
  Directory root,
  PrebuiltTarget target,
  String host,
) async {
  final rustDir = '${root.path}/rust';
  final env = _crossEnv(target, host, release: true);
  if (env == null) return null;

  final result = await Process.start(
    'cargo',
    <String>[
      '+$kToolchain',
      'build',
      '--release',
      ...kBuildStdFlags,
      '--target',
      target.triple,
    ],
    workingDirectory: rustDir,
    environment: env,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  final code = await result.exitCode;
  if (code != 0) {
    stderr.writeln('ERROR: cargo build failed for ${target.triple} ($code).');
    return null;
  }

  final out =
      '$rustDir/target/${target.triple}/release/${target.cargoArtifact}';
  if (!File(out).existsSync()) {
    stderr.writeln('ERROR: expected artifact missing: $out');
    return null;
  }
  return out;
}

/// Type-checks one target with `cargo check`, returning whether it succeeded.
///
/// 用 `cargo check` 对单个 target 做类型检查，返回是否成功。
///
/// Runs on the default (stable) toolchain without `-Z build-std`: the point is
/// only "does this crate still compile for this triple", and the release
/// nightly flags would cost far more for no extra signal.
///
/// 走默认（stable）工具链且不带 `-Z build-std`：目的只是“这个 crate 对该三元组还
/// 编得过吗”，加上 release 的 nightly flag 只会显著变慢而不增加信息量。
Future<bool> _checkTarget(
  Directory root,
  PrebuiltTarget target,
  String host,
) async {
  final env = _crossEnv(target, host, release: false);
  if (env == null) return false;
  final p = await Process.start(
    'cargo',
    <String>['check', '--target', target.triple],
    workingDirectory: '${root.path}/rust',
    environment: env,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  return await p.exitCode == 0;
}

/// Builds the environment a cargo invocation needs to cross-compile [target].
///
/// 构造 cargo 交叉编译 [target] 所需的环境变量。
///
/// Returns `null` (after printing why) when a required toolchain is missing.
/// [release] selects the size-optimised RUSTFLAGS; a `cargo check` run must not
/// get them, because `-Zunstable-options` is rejected by the stable toolchain.
///
/// 缺少必要工具链时打印原因并返回 `null`。[release] 决定是否带上瘦身用的
/// RUSTFLAGS；`cargo check` 不能带，因为 stable 工具链会拒绝 `-Zunstable-options`。
Map<String, String>? _crossEnv(
  PrebuiltTarget target,
  String host, {
  required bool release,
}) {
  final env = <String, String>{
    // An empty value still overrides any RUSTFLAGS inherited from the shell,
    // which is what a stable `cargo check` needs.
    // 空值同样会覆盖从 shell 继承来的 RUSTFLAGS，正是 stable `cargo check` 所需。
    'RUSTFLAGS': release ? kBaseRustFlags : '',
  };

  // Cross-compiling aarch64 on an x86_64 Linux host needs the GNU cross
  // toolchain (`apt install gcc-aarch64-linux-gnu`); on a native arm64 host the
  // default cc is already right, so only set these when the tool exists.
  //
  // 在 x86_64 Linux 上交叉编译 aarch64 需要 GNU 交叉工具链
  // （`apt install gcc-aarch64-linux-gnu`）；原生 arm64 宿主的默认 cc 本就正确，
  // 因此仅在该工具存在时才设置。
  if (target.triple == 'aarch64-unknown-linux-gnu' &&
      !Platform.version.contains('arm64')) {
    const cross = 'aarch64-linux-gnu-gcc';
    env['CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER'] = cross;
    env['CC_aarch64_unknown_linux_gnu'] = cross;
  }

  if (target.group == 'android') {
    final ndk = _findNdk();
    if (ndk == null) {
      stderr.writeln(
        'ERROR: Android NDK not found. Set ANDROID_NDK_HOME (or ANDROID_NDK_ROOT), '
        'or install one under \$ANDROID_HOME/ndk/.',
      );
      return null;
    }
    final bin = '$ndk/toolchains/llvm/prebuilt/${_ndkHostTag(host)}/bin';
    final ext = host == 'windows' ? '.cmd' : '';
    final clang =
        '$bin/${_androidClangPrefix(target.triple)}'
        '$kAndroidApiLevel-clang$ext';
    if (!File(clang).existsSync()) {
      stderr.writeln('ERROR: NDK clang not found at $clang');
      return null;
    }
    final upper = target.triple.toUpperCase().replaceAll('-', '_');
    final lower = target.triple.replaceAll('-', '_');
    env['CARGO_TARGET_${upper}_LINKER'] = clang;
    env['CC_$lower'] = clang;
    env['AR_$lower'] = '$bin/llvm-ar${host == 'windows' ? '.exe' : ''}';
    // 16 KB page alignment is a Google Play requirement for 64-bit native
    // libraries. NDK r28's clang already defaults to it (verified: LOAD
    // segments align at 0x4000), but passing it explicitly means an older NDK
    // on someone's machine cannot silently produce a non-compliant .so.
    //
    // 16 KB 页对齐是 Google Play 对 64 位原生库的硬要求。NDK r28 的 clang 默认
    // 已经这样做（实测 LOAD 段对齐 0x4000），但显式传一遍可以避免有人用更老的
    // NDK 时静默产出不合规的 .so。
    // `--icf=all` is lld's identical-code-folding: byte-identical function
    // bodies (the usual monomorphization duplicates) are merged into a single
    // copy, all their symbols aliasing the same address. Dart looks the bridge
    // exports up by name, so folding costs nothing here — pure size win.
    //
    // `--icf=all` 是 lld 的相同代码折叠：字节完全一致的函数体（泛型单态化产生
    // 的重复实现）合并成一份，原来的多个符号指向同一地址。Dart 侧是按符号名查
    // 找桥接导出的，折叠不影响调用，是纯粹的体积收益。
    env['RUSTFLAGS'] =
        '${env['RUSTFLAGS']} -C link-arg=-Wl,-z,max-page-size=16384'
                ' -C link-arg=-Wl,--icf=all'
            .trim();
  }

  return env;
}

/// `lipo -create`s [inputs] into `prebuilt/<relative>`.
///
/// 把 [inputs] 用 `lipo -create` 合并到 `prebuilt/<relative>`。
Future<void> _lipo(Directory root, List<String> inputs, String relative) async {
  final dest = File('${root.path}/prebuilt/$relative');
  dest.parent.createSync(recursive: true);
  final r = await Process.run('lipo', <String>[
    '-create',
    ...inputs,
    '-output',
    dest.path,
  ]);
  if (r.exitCode != 0) {
    throw StateError('lipo failed for $relative: ${r.stderr}');
  }
  // `strip -x` drops local symbols from the archive while keeping every global
  // symbol the linker (and -force_load) needs.
  // `strip -x` 去掉归档里的本地符号，保留链接器与 -force_load 需要的全局符号。
  await Process.run('strip', <String>['-x', dest.path]);
  stdout.writeln('  -> prebuilt/$relative (${dest.lengthSync()} bytes)');
}

/// Locates an Android NDK from the usual environment variables.
///
/// 从常见环境变量里定位 Android NDK。
String? _findNdk() {
  for (final key in const [
    'ANDROID_NDK_HOME',
    'ANDROID_NDK_ROOT',
    'NDK_HOME',
  ]) {
    final v = Platform.environment[key];
    if (v != null && v.isNotEmpty && Directory(v).existsSync()) return v;
  }
  final sdk =
      Platform.environment['ANDROID_HOME'] ??
      Platform.environment['ANDROID_SDK_ROOT'];
  if (sdk == null) return null;
  final ndkRoot = Directory('$sdk/ndk');
  if (!ndkRoot.existsSync()) return null;
  final versions = ndkRoot.listSync().whereType<Directory>().toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return versions.isEmpty ? null : versions.last.path;
}

/// NDK prebuilt-toolchain directory name for the current host.
///
/// 当前宿主对应的 NDK 预编译工具链目录名。
String _ndkHostTag(String host) => switch (host) {
  'windows' => 'windows-x86_64',
  'macos' => 'darwin-x86_64',
  _ => 'linux-x86_64',
};

/// NDK clang wrapper prefix for an Android target triple.
///
/// Android 目标三元组对应的 NDK clang 包装器前缀。
///
/// The armv7 triple is the one exception: its clang wrapper is spelled
/// `armv7a-linux-androideabi`, not `armv7-linux-androideabi`.
///
/// armv7 是唯一的例外：它的 clang 包装器叫 `armv7a-linux-androideabi`。
String _androidClangPrefix(String triple) =>
    triple == 'armv7-linux-androideabi' ? 'armv7a-linux-androideabi' : triple;

/// Records the source hash and per-file digests of everything just produced,
/// merging into any manifest entries built on another host.
///
/// 记录刚产出的每个文件的源码哈希与内容摘要，并与其它宿主上生成的清单条目合并。
void _updateManifest(Directory root, List<String> produced, String host) {
  final sourceHash = computeSourceHash(root);
  final existing = readManifest(root);
  final artifacts = <String, dynamic>{
    ...?(existing?['artifacts'] as Map<String, dynamic>?),
  };

  for (final rel in produced) {
    final file = File('${root.path}/prebuilt/$rel');
    artifacts[rel] = <String, dynamic>{
      'sourceHash': sourceHash,
      'sha256': _sha256OfFile(file),
      'bytes': file.lengthSync(),
      'builtOnHost': host,
      'toolchain': kToolchain,
      'builtAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  writeManifest(root, <String, dynamic>{
    'schema': 1,
    // The hash every artifact SHOULD carry. CI compares this against the
    // freshly recomputed hash of rust/** and fails when they diverge, so an
    // edited Rust source with a stale binary cannot pass silently.
    //
    // 每个产物“应当”携带的哈希。CI 会把它与实时重算的 rust/** 哈希比对，
    // 不一致即失败——避免改了 Rust 源码却没重出二进制而静默过关。
    'sourceHash': sourceHash,
    'toolchain': kToolchain,
    'artifacts': artifacts,
  });
  stdout.writeln('\nprebuilt/MANIFEST.json updated (sourceHash=$sourceHash).');
}

/// SHA-256 of a file's bytes, lowercase hex.
///
/// 文件内容的 SHA-256（小写十六进制）。
String _sha256OfFile(File file) => sha256OfBytes(file.readAsBytesSync());
