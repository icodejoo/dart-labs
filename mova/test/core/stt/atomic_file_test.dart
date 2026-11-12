import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/stt/atomic_file.dart';

/// Fails while the file writer reads the payload.
///
/// 文件写入器读取内容时抛错。
class _BrokenBytes extends ListBase<int> {
  @override
  int get length => 3;

  @override
  set length(int value) => throw UnsupportedError('fixed');

  @override
  int operator [](int index) => throw StateError('interrupted payload');

  @override
  void operator []=(int index, int value) => throw UnsupportedError('fixed');
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('mova_stt_atomic_');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('D13 D14 failed staging write preserves old bytes and cleans staging', () async {
    final target = File('${root.path}${Platform.pathSeparator}cache');
    await target.writeAsBytes([7, 8, 9]);
    await expectLater(writeSttCacheFile(target, _BrokenBytes()), throwsStateError);
    expect(await target.readAsBytes(), [7, 8, 9]);
    expect(root.listSync().map((e) => e.path), [target.path]);
    await writeSttCacheFile(target, [1, 2, 3]);
    expect(await target.readAsBytes(), [1, 2, 3]);
    expect(root.listSync().map((e) => e.path), [target.path]);
  });

  test('D13 D14 concurrent replacements publish a complete payload', () async {
    final target = File('${root.path}${Platform.pathSeparator}cache');
    final a = List<int>.filled(8192, 1);
    final b = List<int>.filled(4096, 2);
    await Future.wait([writeSttCacheFile(target, a), writeSttCacheFile(target, b)]);
    expect(await target.readAsBytes(), anyOf(equals(a), equals(b)));
    expect(root.listSync().map((e) => e.path), [target.path]);
  });
}
