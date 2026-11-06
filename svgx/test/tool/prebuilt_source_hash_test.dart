// Source-hash identity must not depend on the checkout's line endings: a
// Windows CRLF checkout and CI's LF checkout have to agree, or MANIFEST.json
// restaged on one is rejected by `check_prebuilt` on the other.
// 源码哈希不能随检出的换行符变化：Windows 的 CRLF 检出与 CI 的 LF 检出必须一致，
// 否则一边 restage 的 MANIFEST.json 会被另一边的 `check_prebuilt` 拒绝。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/prebuilt_common.dart';

/// Writes a minimal `rust/` tree under [root] using [eol] as line ending.
/// 在 [root] 下按 [eol] 换行写出最小的 `rust/` 目录树。
void _writeRustTree(Directory root, String eol) {
  final files = <String, String>{
    'rust/Cargo.toml': '[package]${eol}name = "svgx"$eol',
    'rust/Cargo.lock': 'version = 4$eol',
    'rust/src/lib.rs': 'pub mod api;${eol}fn main() {}$eol',
    'rust/src/api/svg.rs': '// svg$eol',
  };
  files.forEach((path, content) {
    File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  });
}

void main() {
  group('normalizeCrlf', () {
    test('replaces CRLF pairs with LF', () {
      expect(normalizeCrlf([0x61, 0x0d, 0x0a, 0x62]), [0x61, 0x0a, 0x62]);
    });

    test('keeps lone CR and LF untouched', () {
      expect(normalizeCrlf([0x0d, 0x61, 0x0a, 0x0d]), [0x0d, 0x61, 0x0a, 0x0d]);
    });
  });

  test('computeSourceHash is identical for CRLF and LF checkouts', () {
    final lf = Directory.systemTemp.createTempSync('svgx_hash_lf');
    final crlf = Directory.systemTemp.createTempSync('svgx_hash_crlf');
    addTearDown(() {
      lf.deleteSync(recursive: true);
      crlf.deleteSync(recursive: true);
    });
    _writeRustTree(lf, '\n');
    _writeRustTree(crlf, '\r\n');

    expect(computeSourceHash(crlf), computeSourceHash(lf));
  });

  test('computeSourceHash still changes when content changes', () {
    final a = Directory.systemTemp.createTempSync('svgx_hash_a');
    addTearDown(() => a.deleteSync(recursive: true));
    _writeRustTree(a, '\n');
    final before = computeSourceHash(a);
    File('${a.path}/rust/src/api/svg.rs').writeAsStringSync('// changed\n');

    expect(computeSourceHash(a), isNot(before));
  });
}
