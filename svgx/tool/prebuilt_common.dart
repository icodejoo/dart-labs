// Shared definitions for the precompiled-binary pipeline: the target table,
// the on-disk layout under `prebuilt/`, and the source-hash used to prove that
// a committed binary was built from the Rust sources currently in the tree.
//
// 预编译产物流水线的公共定义：目标三元组表、`prebuilt/` 目录布局，以及用来证明
// “已提交的二进制确实由当前 Rust 源码构建”的源码哈希。
//
// Used by `tool/build_prebuilt.dart` (writes MANIFEST.json) and
// `tool/check_prebuilt.dart` (CI verifies MANIFEST.json).
//
// 由 `tool/build_prebuilt.dart`（写 MANIFEST.json）与
// `tool/check_prebuilt.dart`（CI 校验 MANIFEST.json）共同使用。

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Pinned nightly toolchain used for every distributed artifact.
///
/// 所有对外分发产物统一使用的固定 nightly 工具链。
///
/// `-Z build-std=std,panic_abort` plus `-Cpanic=immediate-abort` recompiles std
/// itself and shrinks the native library ~21%. Bumping this must stay in sync
/// with `.github/workflows/svgx-ci.yml`, `README.md` and `CLAUDE.md`.
/// (`rust/build-release.ps1`, the old standalone script this constant used to
/// need to stay in sync with, was deleted 2026-08-26 — fully superseded by
/// `tool/build_prebuilt.dart`.)
const String kToolchain = 'nightly-2026-06-24';

/// RUSTFLAGS applied to every release artifact build.
///
/// 每次 release 产物构建统一使用的 RUSTFLAGS。
///
/// `-Zlocation-detail=none` drops file/line info from `caller_location`
/// (panic messages), `-Zfmt-debug=none` strips `#[derive(Debug)]` bodies.
/// Both are plain rustc `-Z` flags (confirmed via `rustc -Z help`), no extra
/// prerequisite beyond the nightly toolchain already in use. See CLAUDE.md
/// for the measured size delta.
///
/// `-Zlocation-detail=none`去掉 `caller_location`（panic 信息）里的文件/行号，
/// `-Zfmt-debug=none` 精简 `#[derive(Debug)]` 实现。两者都是普通 rustc `-Z`
/// 参数（已用 `rustc -Z help` 确认），除已使用的 nightly 工具链外无额外前提。
/// 实测体积变化见 CLAUDE.md。
const String kBaseRustFlags =
    '-Zunstable-options -Cpanic=immediate-abort '
    '-Zlocation-detail=none -Zfmt-debug=none';

/// Cargo `-Z` flags applied to every release artifact build.
///
/// 每次 release 产物构建统一使用的 cargo `-Z` 参数。
///
/// `-Z build-std=...` without an explicit `-Z build-std-features=...` pulls in
/// std's DEFAULT feature set, which includes `backtrace` and `panic-unwind`
/// (see rust-lang/rust#147257) — dragging gimli/addr2line/miniz_oxide into the
/// binary even though this project never unwinds (`panic_abort` is the only
/// panic runtime linked) or formats backtraces (`-Cpanic=immediate-abort`
/// aborts directly, no panic hook, no backtrace symbolication). The empty
/// `-Z build-std-features=` clears that default set; confirmed via local std
/// source (`std/Cargo.toml`: no `[features] default = [...]` entry — the
/// default is injected by cargo's build-std machinery, not by std itself) and
/// `panic_abort`'s own `Cargo.toml` (only depends on `core`, and `libc`/`alloc`
/// on Android — no dependency on the `backtrace` feature), plus a successful
/// local build with this flag.
///
/// 不带显式 `-Z build-std-features=...` 的 `-Z build-std=...` 会拉入 std 的默认
/// feature 集合，其中包含 `backtrace` 与 `panic-unwind`（见
/// rust-lang/rust#147257）——即便本项目从不 unwind（只链接了 `panic_abort` 这一
/// 个 panic 运行时）也从不格式化 backtrace（`-Cpanic=immediate-abort` 直接
/// abort，没有 panic hook，也不做 backtrace 符号化），仍会把 gimli/addr2line/
/// miniz_oxide 带进二进制。空的 `-Z build-std-features=` 清空该默认集合；已通过
/// 本地 std 源码确认（`std/Cargo.toml` 里没有 `[features] default = [...]`
/// 条目——默认集合是 cargo 的 build-std 机制自己注入的，不是 std 声明的），
/// 也确认了 `panic_abort` 自身的 `Cargo.toml`（只依赖 `core`，Android 上额外依赖
/// `libc`/`alloc`——与 `backtrace` feature 无关），并已用该参数本地构建验证通过。
const List<String> kBuildStdFlags = <String>[
  '-Z',
  'build-std=std,panic_abort',
  '-Z',
  'build-std-features=optimize_for_size',
];

/// Android `minSdkVersion` the `.so` artifacts are linked against.
///
/// Android `.so` 产物链接时使用的 `minSdkVersion`。
///
/// NDK r28 no longer ships sysroots below API 21, so 21 is the floor. A Rust
/// `.so` linked at API 21 simply will not load on API 19/20 devices — which
/// matches what cargokit already produced, since it clamped the same way.
/// `android/build.gradle`'s `minSdkVersion` was corrected from the stale `19`
/// to an explicit `21` to match this (2026-08-26).
///
/// NDK r28 已不再提供 API 21 以下的 sysroot，所以实际下限是 21。这与 cargokit
/// 之前的行为一致。`android/build.gradle` 的 `minSdkVersion` 已从虚标的 `19`
/// 改为显式的 `21`，与此保持一致（2026-08-26）。
const int kAndroidApiLevel = 21;

/// One buildable native artifact: a Rust target triple plus where its output
/// lands under `prebuilt/`.
///
/// 一个可构建的原生产物：Rust 目标三元组 + 它在 `prebuilt/` 下的落点。
class PrebuiltTarget {
  /// Rust target triple, e.g. `aarch64-linux-android`.
  ///
  /// Rust 目标三元组，例如 `aarch64-linux-android`。
  final String triple;

  /// Logical platform group used by `--group`: android/ios/macos/windows/linux.
  ///
  /// `--group` 使用的逻辑平台分组：android/ios/macos/windows/linux。
  final String group;

  /// Path of the produced file relative to `prebuilt/`, or `null` when this
  /// target is only an input to a `lipo` merge and is never shipped alone.
  ///
  /// 产物相对 `prebuilt/` 的路径；若该 target 只是 `lipo` 合并的输入、不单独
  /// 分发，则为 `null`。
  final String? output;

  /// Filename cargo emits in `target/<triple>/release/`.
  ///
  /// cargo 在 `target/<triple>/release/` 下产出的文件名。
  final String cargoArtifact;

  /// Host OS that can build this target: `windows`, `linux`, `macos`, or
  /// `null` when any host with the right toolchain works.
  ///
  /// 能构建该 target 的宿主系统；`null` 表示任何装好工具链的宿主都可以。
  final String? requiresHost;

  const PrebuiltTarget({
    required this.triple,
    required this.group,
    required this.cargoArtifact,
    this.output,
    this.requiresHost,
  });
}

/// Every native slice svgx distributes.
///
/// svgx 分发的全部原生 slice。
///
/// 13 slices in total. Windows-arm64 and Linux-arm64 are deliberately kept:
/// the previous cargokit source build compiled for whatever the consumer's
/// machine was, so dropping them would be a silent compatibility regression.
///
/// 共 13 个 slice。刻意保留 Windows-arm64 与 Linux-arm64：此前 cargokit 是在
/// 用户机器上现编的，砍掉它们等于静默的兼容性回退。
const List<PrebuiltTarget> kTargets = <PrebuiltTarget>[
  // --- Android: dynamic libraries loaded by DynamicLibrary.open. ---
  PrebuiltTarget(
    triple: 'aarch64-linux-android',
    group: 'android',
    cargoArtifact: 'libsvgx.so',
    output: 'android/jniLibs/arm64-v8a/libsvgx.so',
  ),
  PrebuiltTarget(
    triple: 'armv7-linux-androideabi',
    group: 'android',
    cargoArtifact: 'libsvgx.so',
    output: 'android/jniLibs/armeabi-v7a/libsvgx.so',
  ),
  PrebuiltTarget(
    triple: 'x86_64-linux-android',
    group: 'android',
    cargoArtifact: 'libsvgx.so',
    output: 'android/jniLibs/x86_64/libsvgx.so',
  ),
  PrebuiltTarget(
    triple: 'i686-linux-android',
    group: 'android',
    cargoArtifact: 'libsvgx.so',
    output: 'android/jniLibs/x86/libsvgx.so',
  ),

  // --- iOS: static archives, force_load'd by the podspec. ---
  // Device and simulator are both arm64, so `lipo` physically cannot merge
  // them into one archive; the podspec branches on `[sdk=...]` instead.
  //
  // device 与 simulator 同为 arm64，`lipo` 物理上无法合并成一个归档，podspec 改用
  // `[sdk=...]` 条件分支二选一。
  PrebuiltTarget(
    triple: 'aarch64-apple-ios',
    group: 'ios',
    cargoArtifact: 'libsvgx.a',
    output: 'ios/device/libsvgx.a',
    requiresHost: 'macos',
  ),
  PrebuiltTarget(
    triple: 'aarch64-apple-ios-sim',
    group: 'ios',
    cargoArtifact: 'libsvgx.a',
    requiresHost: 'macos',
  ),
  PrebuiltTarget(
    triple: 'x86_64-apple-ios',
    group: 'ios',
    cargoArtifact: 'libsvgx.a',
    requiresHost: 'macos',
  ),

  // --- macOS: one universal static archive. ---
  PrebuiltTarget(
    triple: 'aarch64-apple-darwin',
    group: 'macos',
    cargoArtifact: 'libsvgx.a',
    requiresHost: 'macos',
  ),
  PrebuiltTarget(
    triple: 'x86_64-apple-darwin',
    group: 'macos',
    cargoArtifact: 'libsvgx.a',
    requiresHost: 'macos',
  ),

  // --- Windows: dynamic libraries. ---
  PrebuiltTarget(
    triple: 'x86_64-pc-windows-msvc',
    group: 'windows',
    cargoArtifact: 'svgx.dll',
    output: 'windows/x64/svgx.dll',
    requiresHost: 'windows',
  ),
  PrebuiltTarget(
    triple: 'aarch64-pc-windows-msvc',
    group: 'windows',
    cargoArtifact: 'svgx.dll',
    output: 'windows/arm64/svgx.dll',
    requiresHost: 'windows',
  ),

  // --- Linux: glibc. musl was evaluated and is NOT usable here. ---
  //
  // musl was the preferred option on paper (fully static, no glibc floor), but
  // it does not work for this artifact, verified by building it:
  //
  //   1. `cargo build --target x86_64-unknown-linux-musl` emits
  //      "dropping unsupported crate type `cdylib`" and produces no .so at
  //      all — the musl target defaults to `crt-static`, and Rust refuses to
  //      build a cdylib against a statically linked CRT.
  //   2. Re-running with `-Ctarget-feature=-crt-static` then fails at link
  //      time ("cannot find libgcc_s.so.1").
  //   3. Even if it linked, the result would be worse: a musl-libc .so cannot
  //      be dlopen'd into a Flutter Linux desktop process, which is a glibc
  //      process. Mixing two libcs in one address space does not work.
  //
  // So Linux stays on glibc. Measured floor: an artifact built on Ubuntu 24.04
  // (glibc 2.39) requires at most GLIBC_2.34, i.e. it runs on RHEL 9 / Debian 12
  // / Ubuntu 22.04 and newer. Building on the ubuntu-22.04 runner lowers that
  // floor further; see docs/PRECOMPILED_MIGRATION_PLAN.md.
  //
  // musl 纸面上更优（全静态、无 glibc 下限），但实测不可用：
  //   1. musl target 默认 `crt-static`，Rust 直接丢弃 `cdylib`，根本不产出 .so；
  //   2. 加 `-Ctarget-feature=-crt-static` 后链接失败（找不到 libgcc_s.so.1）；
  //   3. 即便链接成功也没用——musl libc 的 .so 无法被 dlopen 进 glibc 的
  //      Flutter Linux 桌面进程，一个地址空间里混两套 libc 行不通。
  // 因此 Linux 保持 glibc。实测下限：在 Ubuntu 24.04（glibc 2.39）上构建的产物
  // 最高只需要 GLIBC_2.34。
  PrebuiltTarget(
    triple: 'x86_64-unknown-linux-gnu',
    group: 'linux',
    cargoArtifact: 'libsvgx.so',
    output: 'linux/x64/libsvgx.so',
    requiresHost: 'linux',
  ),
  PrebuiltTarget(
    triple: 'aarch64-unknown-linux-gnu',
    group: 'linux',
    cargoArtifact: 'libsvgx.so',
    output: 'linux/arm64/libsvgx.so',
    requiresHost: 'linux',
  ),
];

/// Absolute path to the svgx package root, derived from this script's location.
///
/// 由本脚本所在位置推导出的 svgx 包根目录绝对路径。
///
/// Example / 示例:
/// ```dart
/// final root = packageRoot(Platform.script);
/// ```
Directory packageRoot(Uri scriptUri) =>
    Directory(File.fromUri(scriptUri).parent.parent.path);

/// Computes the SHA-256 identity of the Rust sources that a binary must have
/// been built from.
///
/// 计算“二进制必须由之”构建的 Rust 源码的 SHA-256 身份哈希。
///
/// Covers `rust/Cargo.lock`, `rust/Cargo.toml` and every file under
/// `rust/src/**`, hashed as sorted `relative-path\n<sha256-of-bytes>\n` lines
/// so the result is independent of filesystem ordering and line endings of the
/// listing itself.
///
/// 覆盖 `rust/Cargo.lock`、`rust/Cargo.toml` 和 `rust/src/**` 下的每个文件，按
/// 排序后的 `相对路径\n<内容 sha256>\n` 形式汇总，结果与文件系统枚举顺序无关。
///
/// [root] is the svgx package root directory.
///
/// Returns the lowercase hex digest.
///
/// Example / 示例:
/// ```dart
/// final hash = computeSourceHash(Directory('C:/workspace/dart-labs/svgx'));
/// print(hash); // 3f2a...
/// ```
String computeSourceHash(Directory root) {
  final rustDir = Directory('${root.path}/rust');
  final entries = <String, List<int>>{};

  for (final name in const ['Cargo.lock', 'Cargo.toml']) {
    final file = File('${rustDir.path}/$name');
    if (!file.existsSync()) {
      throw StateError('Missing ${file.path} — cannot compute source hash.');
    }
    entries['rust/$name'] = file.readAsBytesSync();
  }

  final srcDir = Directory('${rustDir.path}/src');
  if (!srcDir.existsSync()) {
    throw StateError('Missing ${srcDir.path} — cannot compute source hash.');
  }
  for (final entity in srcDir.listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = entity.path
        .substring(root.path.length + 1)
        .replaceAll(r'\', '/');
    entries[rel] = entity.readAsBytesSync();
  }

  final keys = entries.keys.toList()..sort();
  final listing = StringBuffer();
  for (final key in keys) {
    listing.writeln(key);
    listing.writeln(sha256.convert(entries[key]!).toString());
  }
  return sha256.convert(utf8.encode(listing.toString())).toString();
}

/// SHA-256 of arbitrary bytes, as a lowercase hex string.
///
/// 任意字节的 SHA-256，返回小写十六进制字符串。
///
/// Example / 示例:
/// ```dart
/// sha256OfBytes(File('a.so').readAsBytesSync()); // "9f86d0..."
/// ```
String sha256OfBytes(List<int> bytes) => sha256.convert(bytes).toString();

/// Path of the manifest that records which source hash each binary came from.
///
/// 记录“每个二进制出自哪个源码哈希”的清单文件路径。
File manifestFile(Directory root) =>
    File('${root.path}/prebuilt/MANIFEST.json');

/// Reads `prebuilt/MANIFEST.json`, or `null` when it does not exist.
///
/// 读取 `prebuilt/MANIFEST.json`；不存在时返回 `null`。
Map<String, dynamic>? readManifest(Directory root) {
  final file = manifestFile(root);
  if (!file.existsSync()) return null;
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Writes [manifest] to `prebuilt/MANIFEST.json` with stable 2-space
/// indentation so diffs stay reviewable.
///
/// 以固定 2 空格缩进写入 `prebuilt/MANIFEST.json`，保证 diff 可读。
void writeManifest(Directory root, Map<String, dynamic> manifest) {
  final file = manifestFile(root);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
}
