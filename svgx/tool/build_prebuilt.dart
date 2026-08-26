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
    // The iOS XCFramework has to live in the pod root instead of under
    // `prebuilt/` (see kIosXcframework), so it needs its own walk.
    //
    // iOS XCFramework 必须放在 pod 根目录而非 `prebuilt/` 下（见
    // kIosXcframework），因此要单独枚举。
    found.addAll(iosXcframeworkFiles(root));
    // Same for the macOS framework bundle (see kMacosFramework).
    // macOS framework bundle 同理（见 kMacosFramework）。
    found.addAll(macosFrameworkFiles(root));
    found.sort();
    // Restage rebuilds the picture from disk, so entries whose file is gone
    // (an artifact layout change, e.g. iOS `.a` -> `.xcframework`) must be
    // pruned rather than merged forward as dangling references.
    //
    // restage 以磁盘现状为准，因此文件已不存在的条目（产物布局变更，例如 iOS 从
    // `.a` 改为 `.xcframework`）必须剔除，不能作为悬空引用继续保留。
    _updateManifest(root, found, _hostName(), prune: true);
    for (final f in found) {
      // `../ios/...` keys already point outside `prebuilt/`; print them as the
      // package-relative path they actually are.
      // `../ios/...` 这类键本就指向 `prebuilt/` 之外，直接按其真实的包内相对路径打印。
      stdout.writeln(
        '  staged ${f.startsWith('../') ? f.substring(3) : 'prebuilt/$f'}',
      );
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

  // Apple framework packaging: the iOS XCFramework (device slice + a lipo'd
  // simulator slice) and the single universal macOS framework.
  //
  // Apple 侧 framework 打包：iOS 的 XCFramework（device slice + lipo 合并的模拟器
  // slice），以及 macOS 单个通用 framework。
  if (host == 'macos') {
    if (built.containsKey('aarch64-apple-ios') &&
        built.containsKey('aarch64-apple-ios-sim') &&
        built.containsKey('x86_64-apple-ios')) {
      produced.addAll(
        await _buildIosXcframework(
          root,
          device: built['aarch64-apple-ios']!,
          simulator: <String>[
            built['aarch64-apple-ios-sim']!,
            built['x86_64-apple-ios']!,
          ],
        ),
      );
    }
    if (built.containsKey('aarch64-apple-darwin') &&
        built.containsKey('x86_64-apple-darwin')) {
      produced.addAll(
        await _buildMacosFramework(root, <String>[
          built['aarch64-apple-darwin']!,
          built['x86_64-apple-darwin']!,
        ]),
      );
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

  // Pin the iOS deployment target so the shipped binary's LC_BUILD_VERSION and
  // the framework's Info.plist MinimumOSVersion always agree, whatever the
  // current rustc happens to default to.
  //
  // 固定 iOS 部署目标，使产物的 LC_BUILD_VERSION 与 framework Info.plist 的
  // MinimumOSVersion 始终一致，不受 rustc 默认值变动影响。
  if (target.group == 'ios') {
    env['IPHONEOS_DEPLOYMENT_TARGET'] = kIosDeploymentTarget;
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

/// Packages the macOS `cdylib` slices into `macos/svgx.framework` and returns
/// the produced file paths as manifest keys.
///
/// 把 macOS 的 cdylib 各架构打包成 `macos/svgx.framework`，返回清单键形式的产物列表。
///
/// [dylibs] are the per-architecture cdylibs (`arm64`, `x86_64`) to `lipo` into
/// one fat binary.
///
/// macOS has a single platform variant, so unlike iOS there is nothing for an
/// XCFramework to disambiguate — one universal `.framework` is the whole story
/// and `xcodebuild -create-xcframework` would only add a wrapper layer.
/// Unlike iOS, the bundle must be *versioned* (`Versions/A/...` plus three
/// symlinks): `codesign` rejects a flat framework on macOS with "bundle format
/// unrecognized, invalid, or unsuitable", and Xcode signs every embedded
/// framework at "Embed & Sign" time.
///
/// macOS 只有一个平台变体，不像 iOS 需要 XCFramework 去区分 slice——一个通用
/// `.framework` 就是全部，再套 `xcodebuild -create-xcframework` 只是多一层包装。
/// 与 iOS 不同的是 bundle 必须是*版本化*的（`Versions/A/...` 加三个符号链接）：
/// macOS 的 `codesign` 会以 “bundle format unrecognized, invalid, or unsuitable”
/// 拒绝扁平 framework，而 Xcode 在 “Embed & Sign” 阶段会给每个嵌入的 framework 签名。
Future<List<String>> _buildMacosFramework(
  Directory root,
  List<String> dylibs,
) async {
  final staging = File('${root.path}/rust/target/macos-fat/libsvgx.dylib');
  staging.parent.createSync(recursive: true);
  await _exec('lipo', <String>[
    '-create',
    ...dylibs,
    '-output',
    staging.path,
  ]);

  // The old static layout (`prebuilt/macos/libsvgx.a`) must not survive next to
  // the new bundle, and a stale bundle must not be merged into.
  //
  // 旧的静态布局（`prebuilt/macos/libsvgx.a`）不能与新 bundle 并存，陈旧的 bundle
  // 也不能被增量合并。
  final bundle = Directory('${root.path}/prebuilt/$kMacosFramework');
  for (final stale in <Directory>[
    bundle,
    Directory('${root.path}/prebuilt/macos'),
  ]) {
    if (stale.existsSync()) stale.deleteSync(recursive: true);
  }

  final versionA = Directory('${bundle.path}/Versions/A');
  Directory('${versionA.path}/Resources').createSync(recursive: true);

  final binary = File('${versionA.path}/$kMacosFrameworkName');
  staging.copySync(binary.path);

  // rustc writes an absolute install_name; dyld must resolve it through the
  // embedding app's @rpath instead. The path includes `Versions/A` because
  // that is where the real binary lives in a versioned bundle.
  //
  // rustc 写的是绝对路径 install_name；dyld 必须改为经宿主 App 的 @rpath 解析。路径
  // 里带 `Versions/A`，因为版本化 bundle 的真实二进制就在那里。
  await _exec('install_name_tool', <String>[
    '-id',
    '@rpath/$kMacosFrameworkName.framework/Versions/A/$kMacosFrameworkName',
    binary.path,
  ]);
  // `-x` drops local symbols, `-S` debug symbols; the `#[no_mangle]` exports
  // Dart looks up stay in the dynamic symbol table.
  //
  // `-x` 去局部符号，`-S` 去调试符号；Dart 要查的 `#[no_mangle]` 导出留在动态
  // 符号表里。
  await _exec('strip', <String>['-x', '-S', binary.path]);

  File('${versionA.path}/Resources/Info.plist').writeAsStringSync(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n'
    '<dict>\n'
    '\t<key>CFBundleDevelopmentRegion</key>\n\t<string>en</string>\n'
    '\t<key>CFBundleExecutable</key>\n\t<string>$kMacosFrameworkName</string>\n'
    '\t<key>CFBundleIdentifier</key>\n\t<string>com.example.svgx</string>\n'
    '\t<key>CFBundleInfoDictionaryVersion</key>\n\t<string>6.0</string>\n'
    '\t<key>CFBundleName</key>\n\t<string>$kMacosFrameworkName</string>\n'
    '\t<key>CFBundlePackageType</key>\n\t<string>FMWK</string>\n'
    '\t<key>CFBundleShortVersionString</key>\n\t<string>1.0</string>\n'
    '\t<key>CFBundleVersion</key>\n\t<string>1</string>\n'
    '\t<key>CFBundleSupportedPlatforms</key>\n'
    '\t<array>\n\t\t<string>MacOSX</string>\n\t</array>\n'
    '\t<key>LSMinimumSystemVersion</key>\n'
    '\t<string>$kMacosDeploymentTarget</string>\n'
    '</dict>\n'
    '</plist>\n',
  );

  // The three symlinks that make this a versioned bundle. Without
  // `Versions/Current` neither CFBundle nor codesign recognises the layout.
  //
  // 让它成为版本化 bundle 的三个符号链接。缺了 `Versions/Current`，CFBundle 与
  // codesign 都认不出这个布局。
  Link('${bundle.path}/Versions/Current').createSync('A');
  Link(
    '${bundle.path}/$kMacosFrameworkName',
  ).createSync('Versions/Current/$kMacosFrameworkName');
  Link('${bundle.path}/Resources').createSync('Versions/Current/Resources');

  final produced = macosFrameworkFiles(root);
  final total = produced.fold<int>(
    0,
    (sum, rel) => sum + File('${root.path}/prebuilt/$rel').lengthSync(),
  );
  stdout.writeln(
    '  -> $kMacosFramework (${produced.length} files, $total bytes)',
  );
  return produced;
}

/// Packages the iOS `cdylib` slices into `prebuilt/ios/svgx.xcframework` and
/// returns the produced file paths, relative to `prebuilt/`.
///
/// 把 iOS 的 cdylib 各 slice 打包成 `prebuilt/ios/svgx.xcframework`，返回相对
/// `prebuilt/` 的产物文件列表。
///
/// [device] is the `aarch64-apple-ios` dylib; [simulator] are the simulator
/// dylibs to `lipo` into one fat slice.
///
/// A bare `.dylib` cannot be shipped this way: iOS only loads dynamic libraries
/// that live inside a `.framework` bundle, and CocoaPods only embeds and
/// codesigns `vendored_frameworks`. So each slice is wrapped in a real bundle
/// first, and `xcodebuild -create-xcframework` is fed `-framework`, not
/// `-library`.
///
/// 裸 `.dylib` 无法这样分发：iOS 只加载位于 `.framework` 包内的动态库，而
/// CocoaPods 也只会嵌入并签名 `vendored_frameworks`。因此先把每个 slice 包成真正的
/// bundle，再用 `xcodebuild -create-xcframework` 的 `-framework`（而非 `-library`）。
Future<List<String>> _buildIosXcframework(
  Directory root, {
  required String device,
  required List<String> simulator,
}) async {
  final staging = Directory('${root.path}/rust/target/ios-xcframework');
  if (staging.existsSync()) staging.deleteSync(recursive: true);

  final deviceFramework = await _makeIosFramework(
    Directory('${staging.path}/device'),
    device,
    platform: 'iPhoneOS',
  );
  final simFat = File('${staging.path}/simulator-fat/libsvgx.dylib');
  simFat.parent.createSync(recursive: true);
  await _exec('lipo', <String>[
    '-create',
    ...simulator,
    '-output',
    simFat.path,
  ]);
  final simFramework = await _makeIosFramework(
    Directory('${staging.path}/simulator'),
    simFat.path,
    platform: 'iPhoneSimulator',
  );

  // `-create-xcframework` refuses to write over an existing output, and the
  // old static layout (`prebuilt/ios/device`, `prebuilt/ios/simulator`) must
  // not survive alongside the new one.
  //
  // `-create-xcframework` 不覆盖已存在的输出，且旧的静态库布局
  // （`prebuilt/ios/device`、`prebuilt/ios/simulator`）不能与新产物并存。
  final out = '${root.path}/prebuilt/$kIosXcframework';
  for (final stale in <Directory>[
    Directory(out),
    Directory('${root.path}/prebuilt/ios'),
  ]) {
    if (stale.existsSync()) stale.deleteSync(recursive: true);
  }
  Directory(out).parent.createSync(recursive: true);

  await _exec('xcodebuild', <String>[
    '-create-xcframework',
    '-framework',
    deviceFramework.path,
    '-framework',
    simFramework.path,
    '-output',
    out,
  ]);

  final produced = iosXcframeworkFiles(root);
  final total = produced.fold<int>(
    0,
    (sum, rel) => sum + File('${root.path}/prebuilt/$rel').lengthSync(),
  );
  stdout.writeln(
    '  -> $kIosXcframework (${produced.length} files, $total bytes)',
  );
  return produced;
}

/// Wraps one iOS `cdylib` in a `<name>.framework` bundle under [dir] and
/// returns the bundle directory.
///
/// 把一个 iOS cdylib 包成 [dir] 下的 `<name>.framework` bundle，返回该 bundle 目录。
///
/// [platform] is the `CFBundleSupportedPlatforms` entry: `iPhoneOS` or
/// `iPhoneSimulator`.
Future<Directory> _makeIosFramework(
  Directory dir,
  String dylib, {
  required String platform,
}) async {
  final bundle = Directory('${dir.path}/$kIosFrameworkName.framework');
  bundle.createSync(recursive: true);
  final binary = File('${bundle.path}/$kIosFrameworkName');
  File(dylib).copySync(binary.path);

  // Rust links a cdylib with an absolute install_name; dyld must instead
  // resolve it through the embedding app's @rpath (`@executable_path/
  // Frameworks`, which CocoaPods sets up).
  //
  // rustc 给 cdylib 写的是绝对路径 install_name；dyld 必须改为经宿主 App 的
  // @rpath（CocoaPods 会配置 `@executable_path/Frameworks`）解析。
  await _exec('install_name_tool', <String>[
    '-id',
    '@rpath/$kIosFrameworkName.framework/$kIosFrameworkName',
    binary.path,
  ]);
  // `-x` drops local symbols, `-S` debug symbols; the `#[no_mangle]` exports
  // Dart looks up stay in the dynamic symbol table.
  //
  // `-x` 去局部符号，`-S` 去调试符号；Dart 要查的 `#[no_mangle]` 导出留在动态
  // 符号表里。
  await _exec('strip', <String>['-x', '-S', binary.path]);

  File('${bundle.path}/Info.plist').writeAsStringSync(
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n'
    '<dict>\n'
    '\t<key>CFBundleDevelopmentRegion</key>\n\t<string>en</string>\n'
    '\t<key>CFBundleExecutable</key>\n\t<string>$kIosFrameworkName</string>\n'
    '\t<key>CFBundleIdentifier</key>\n\t<string>com.example.svgx</string>\n'
    '\t<key>CFBundleInfoDictionaryVersion</key>\n\t<string>6.0</string>\n'
    '\t<key>CFBundleName</key>\n\t<string>$kIosFrameworkName</string>\n'
    '\t<key>CFBundlePackageType</key>\n\t<string>FMWK</string>\n'
    '\t<key>CFBundleShortVersionString</key>\n\t<string>1.0</string>\n'
    '\t<key>CFBundleVersion</key>\n\t<string>1</string>\n'
    '\t<key>CFBundleSupportedPlatforms</key>\n'
    '\t<array>\n\t\t<string>$platform</string>\n\t</array>\n'
    '\t<key>MinimumOSVersion</key>\n'
    '\t<string>$kIosDeploymentTarget</string>\n'
    '</dict>\n'
    '</plist>\n',
  );
  return bundle;
}

/// Runs [exe] with [args], throwing when it fails.
///
/// 执行 [exe]，失败时抛异常。
Future<void> _exec(String exe, List<String> args) async {
  final r = await Process.run(exe, args);
  if (r.exitCode != 0) {
    throw StateError(
      '$exe ${args.join(' ')} failed (${r.exitCode}):\n${r.stdout}\n${r.stderr}',
    );
  }
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
///
/// [prune] drops pre-existing entries not in [produced]; pass it only when
/// [produced] is a complete listing of `prebuilt/` (i.e. from `--restage`).
///
/// [prune] 会剔除不在 [produced] 里的旧条目；仅当 [produced] 是 `prebuilt/` 的
/// 完整清单时（即来自 `--restage`）才可传 true。
void _updateManifest(
  Directory root,
  List<String> produced,
  String host, {
  bool prune = false,
}) {
  final sourceHash = computeSourceHash(root);
  final existing = readManifest(root);
  final artifacts = <String, dynamic>{
    if (!prune) ...?(existing?['artifacts'] as Map<String, dynamic>?),
  };

  final previous =
      (existing?['artifacts'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  for (final rel in produced) {
    final file = File('${root.path}/prebuilt/$rel');
    final digest = _sha256OfFile(file);
    // A byte-identical artifact was not rebuilt, so its provenance still holds.
    // Re-stamping it would falsely claim the restaging host built it and churn
    // `builtAt` on every run.
    //
    // 内容完全一致说明该产物没有被重建，原有溯源信息依然成立。重新打戳会谎称
    // 是 restage 所在宿主构建的，还会让 `builtAt` 每次都变。
    final prior = previous[rel] as Map<String, dynamic>?;
    if (prior != null &&
        prior['sha256'] == digest &&
        prior['sourceHash'] == sourceHash) {
      artifacts[rel] = prior;
      continue;
    }
    artifacts[rel] = <String, dynamic>{
      'sourceHash': sourceHash,
      'sha256': digest,
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
