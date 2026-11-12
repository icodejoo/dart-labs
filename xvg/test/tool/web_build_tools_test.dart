import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_web.dart' as build;
import '../../tool/check_web_bridge.dart' as bridge;
import '../../tool/generate_web_bridge.dart' as generator;

/// 验证版本锁定与桥接覆盖防护，避免错误工具链产出可部署文件。
void main() {
  test('codegen preserves LF and CRLF destination line endings', () {
    final root = Directory.systemTemp.createTempSync('xvg_codegen_eol_');
    addTearDown(() => root.deleteSync(recursive: true));
    final source = File('${root.path}/source')
      ..writeAsStringSync('new\r\ncode\n');
    final destination = File('${root.path}/destination');
    for (final eol in [bridge.bridgeLf, bridge.bridgeCrlf]) {
      destination.writeAsStringSync('old$eol');
      generator.copyGenerated(source, destination);
      expect(destination.readAsStringSync(), 'new${eol}code$eol');
    }
  });

  test('codegen requires one init marker', () {
    const marker = 'frb(init)';
    const replacement = 'frb(init, sync)';
    expect(bridge.replaceRequired(marker, marker, replacement), replacement);
    for (final source in ['', '$marker $marker']) {
      expect(
        () => bridge.replaceRequired(source, marker, replacement),
        throwsStateError,
      );
    }
  });

  test('locked wasm-bindgen version ignores similarly named packages', () {
    const package = '[[package]]';
    const version = '0.2.130';
    const lock =
        '$package\nname = "wasm-bindgen-shared"\nversion = "1.0.0"\n'
        '$package\nname = "wasm-bindgen"\nversion = "$version"\n';
    expect(build.wasmBindgenVersion(lock), version);
    expect(build.wasmBindgenVersion(lock.replaceAll('\n', '\r\n')), version);
    expect(() => build.wasmBindgenVersion(''), throwsStateError);
    expect(() => build.wasmBindgenVersion('$lock$lock'), throwsStateError);
  });

  test(
    'bridge check rejects overwritten entry and drift in either variant',
    () {
      final root = Directory.systemTemp.createTempSync('xvg_bridge_test_');
      addTearDown(() => root.deleteSync(recursive: true));
      final directory = Directory('${root.path}/lib/src/rust')
        ..createSync(recursive: true);
      final source = File('lib/src/rust/frb_generated.native.dart')
          .readAsStringSync();
      final forwarder = File('${directory.path}/frb_generated.dart');
      final native = File('${directory.path}/frb_generated.native.dart');
      final web = File('${directory.path}/frb_generated.web_init.dart');
      forwarder.writeAsStringSync(bridge.bridgeForwarder);
      native.writeAsStringSync(source);
      final expected = bridge.expectedWebBridge(source);
      web.writeAsStringSync(expected);
      bridge.checkWebBridge(root);
      forwarder.writeAsStringSync(source);
      expect(() => bridge.checkWebBridge(root), throwsStateError);
      forwarder.writeAsStringSync(bridge.bridgeForwarder);
      web.writeAsStringSync('$expected// stale API\n');
      expect(() => bridge.checkWebBridge(root), throwsStateError);
      web.writeAsStringSync(expected);
      native.writeAsStringSync('$source// changed API\n');
      expect(() => bridge.checkWebBridge(root), throwsStateError);
    },
  );

  test('demo bootstrap stays in example and is not publicly exported', () {
    expect(File('lib/src/rust/web_bootstrap.dart').existsSync(), isFalse);
    expect(File('example/lib/web_bootstrap.dart').existsSync(), isTrue);
    expect(
      File('lib/xvg.dart').readAsStringSync(),
      isNot(contains('bootstrap')),
    );
    expect(
      File('example/lib/main.dart').readAsStringSync(),
      contains("'web_bootstrap.dart'"),
    );
  });
}
