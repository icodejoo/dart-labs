/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as path;

import 'util.dart';

class _Toolchain {
  _Toolchain(
    this.name,
    this.targets,
  );

  final String name;
  final List<String> targets;
}

class Rustup {
  List<String>? installedTargets(String toolchain) {
    final targets = _installedTargets(toolchain);
    return targets != null ? List.unmodifiable(targets) : null;
  }

  void installToolchain(String toolchain) {
    log.info("Installing Rust toolchain: $toolchain");
    runCommand("rustup", ['toolchain', 'install', toolchain]);
    _installedToolchains
        .add(_Toolchain(toolchain, _getInstalledTargets(toolchain)));
  }

  void installTarget(
    String target, {
    required String toolchain,
  }) {
    log.info("Installing Rust target: $target");
    runCommand("rustup", ['target', 'add', '--toolchain', toolchain, target]);
    _installedTargets(toolchain)?.add(target);
  }

  bool _didInstallZigBuild = false;

  void installZigBuild(String toolchain) {
    if (_didInstallZigBuild) {
      return;
    }

    log.info("Installing Zig build");
    runCommand("rustup", [
      'run',
      toolchain,
      'cargo',
      'install',
      '--locked',
      'cargo-zigbuild',
    ]);
    _didInstallZigBuild = true;
  }

  final List<_Toolchain> _installedToolchains;

  Rustup() : _installedToolchains = _getInstalledToolchains();

  List<String>? _installedTargets(String toolchain) => _installedToolchains
      .firstWhereOrNull(
          (e) => e.name == toolchain || e.name.startsWith('$toolchain-'))
      ?.targets;

  static List<_Toolchain> _getInstalledToolchains() {
    String extractToolchainName(String line) {
      // ignore (default) after toolchain name
      final parts = line.split(' ');
      return parts[0];
    }

    final res = runCommand("rustup", ['toolchain', 'list']);

    // To list all non-custom toolchains, we need to filter out lines that
    // don't start with "stable", "beta", or "nightly".
    Pattern nonCustom = RegExp(r"^(stable|beta|nightly)");
    final lines = res.stdout
        .toString()
        .split('\n')
        .where((e) => e.isNotEmpty && e.startsWith(nonCustom))
        .map(extractToolchainName)
        .toList(growable: true);

    return lines
        .map(
          (name) => _Toolchain(
            name,
            _getInstalledTargets(name),
          ),
        )
        .toList(growable: true);
  }

  static List<String> _getInstalledTargets(String toolchain) {
    final res = runCommand("rustup", [
      'target',
      'list',
      '--toolchain',
      toolchain,
      '--installed',
    ]);
    final lines = res.stdout
        .toString()
        .split('\n')
        .where((e) => e.isNotEmpty)
        .toList(growable: true);
    return lines;
  }

  bool _didInstallRustSrcForNightly = false;

  /// SVGX-LOCAL MODIFICATION of upstream cargokit: upstream hardcodes the
  /// literal `'nightly'` toolchain name here, which breaks for a pinned
  /// dated nightly like `nightly-2026-06-24` (installing `rust-src` on the
  /// wrong toolchain). Takes the actual [toolchain] string instead.
  ///
  /// SVGX-LOCAL 对上游 cargokit 的修改：上游这里硬编码字面量 `'nightly'`
  /// 工具链名，对 `nightly-2026-06-24` 这种带日期的固定 nightly 会装错工具链
  /// 的 `rust-src`。改为接受实际的 [toolchain] 字符串。
  void installRustSrcForNightly(String toolchain) {
    if (_didInstallRustSrcForNightly) {
      return;
    }
    // Useful for -Z build-std
    runCommand(
      "rustup",
      ['component', 'add', 'rust-src', '--toolchain', toolchain],
    );
    _didInstallRustSrcForNightly = true;
  }

  static String? executablePath() {
    final envPath = Platform.environment['PATH'];
    final envPathSeparator = Platform.isWindows ? ';' : ':';
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    final paths = [
      if (home != null) path.join(home, '.cargo', 'bin'),
      if (envPath != null) ...envPath.split(envPathSeparator),
    ];
    for (final p in paths) {
      final rustup = Platform.isWindows ? 'rustup.exe' : 'rustup';
      final rustupPath = path.join(p, rustup);
      if (File(rustupPath).existsSync()) {
        return rustupPath;
      }
    }
    return null;
  }
}
