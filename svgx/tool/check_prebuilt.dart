// Verifies that the binaries committed under `prebuilt/` still match the Rust
// sources in the tree.
//
// 校验 `prebuilt/` 下已提交的二进制是否仍与树内 Rust 源码一致。
//
// This is the safety net that replaces cargokit's content-hash mechanism: once
// consumers stop compiling Rust, "someone edited rust/src/** but did not
// regenerate the binaries" would otherwise fail silently and ship a stale
// library. CI runs this on every push.
//
// 这是取代 cargokit 内容哈希机制的安全网：下游不再编译 Rust 之后，“改了
// rust/src/** 却没重新生成二进制”会静默发布过期库。CI 每次 push 都跑本检查。
//
// Usage / 用法:
//   dart run tool/check_prebuilt.dart                     # full, strict check
//   dart run tool/check_prebuilt.dart --allow-incomplete  # sync-only check
//   dart run tool/check_prebuilt.dart --hash              # print source hash
//
// `--allow-incomplete` downgrades "this platform slice has no artifact yet"
// from an error to a warning, while keeping every staleness check fatal. It
// exists for the migration window in which some slices can only be produced on
// a host that is not yet wired up (Apple slices need macOS). Remove it from CI
// once every slice is committed.
//
// `--allow-incomplete` 把“某个平台 slice 还没有产物”从错误降级为警告，同时保留
// 全部“过期”检查为致命错误。它只服务于迁移窗口期——部分 slice 只能在尚未接入的
// 宿主上产出（Apple 需要 macOS）。所有 slice 都提交之后，就把它从 CI 里去掉。

import 'dart:io';

import 'prebuilt_common.dart';

void main(List<String> args) {
  final root = packageRoot(Platform.script);
  final currentHash = computeSourceHash(root);
  final allowIncomplete = args.contains('--allow-incomplete');

  if (args.contains('--hash')) {
    stdout.writeln(currentHash);
    return;
  }

  final manifest = readManifest(root);
  if (manifest == null) {
    stderr.writeln(
      'FAIL: prebuilt/MANIFEST.json is missing. Run `dart run tool/build_prebuilt.dart`.',
    );
    exitCode = 1;
    return;
  }

  final problems = <String>[];
  final missing = <String>[];

  final manifestHash = manifest['sourceHash'] as String?;
  if (manifestHash != currentHash) {
    problems.add(
      'Rust sources changed since the prebuilt binaries were generated.\n'
      '    manifest sourceHash : $manifestHash\n'
      '    current  sourceHash : $currentHash\n'
      '    -> Rebuild the artifacts (see docs/PRECOMPILED_MIGRATION_PLAN.md) and commit them.',
    );
  }

  final artifacts =
      (manifest['artifacts'] as Map<String, dynamic>?) ?? <String, dynamic>{};

  // Every shippable target must have an entry; a missing one means a platform
  // slice was silently dropped.
  // 每个可分发 target 都必须有条目；缺失即意味着某个平台 slice 被静默砍掉。
  for (final target in kTargets) {
    final rel = target.output;
    if (rel == null) continue;
    if (!artifacts.containsKey(rel)) {
      missing.add('$rel (${target.triple})');
    }
  }
  // Apple artifacts that no single triple owns: the macOS lipo'd archive and
  // the iOS XCFramework (whose two slices are built from three triples).
  //
  // 不属于任何单个三元组的 Apple 产物：macOS 的 lipo 通用归档，以及 iOS 的
  // XCFramework（两个 slice 由三个三元组构建而来）。
  for (final rel in kExtraArtifacts) {
    if (!artifacts.containsKey(rel)) {
      missing.add('$rel (Apple multi-triple artifact)');
    }
  }

  artifacts.forEach((rel, value) {
    final entry = value as Map<String, dynamic>;
    final file = File('${root.path}/prebuilt/$rel');
    if (!file.existsSync()) {
      problems.add('Missing binary: prebuilt/$rel (listed in the manifest).');
      return;
    }
    final actual = sha256OfBytes(file.readAsBytesSync());
    if (actual != entry['sha256']) {
      problems.add(
        'prebuilt/$rel content does not match its manifest sha256 '
        '(expected ${entry['sha256']}, got $actual).',
      );
    }
    if (entry['sourceHash'] != currentHash) {
      problems.add(
        'prebuilt/$rel was built from source hash ${entry['sourceHash']}, '
        'but the tree is now at $currentHash.',
      );
    }
  });

  if (missing.isNotEmpty) {
    final line = missing.map((m) => '  * no artifact yet for $m').join('\n');
    if (allowIncomplete) {
      stdout.writeln(
        'WARNING: ${missing.length} platform slice(s) not built yet '
        '(--allow-incomplete):\n$line\n',
      );
    } else {
      problems.addAll(missing.map((m) => 'Manifest has no entry for $m.'));
    }
  }

  if (problems.isEmpty) {
    stdout.writeln(
      'OK: ${artifacts.length} prebuilt artifact(s) match source hash $currentHash.',
    );
    return;
  }

  stderr.writeln('FAIL: prebuilt artifacts are out of sync.\n');
  for (final p in problems) {
    stderr.writeln('  * $p');
  }
  exitCode = 1;
}
