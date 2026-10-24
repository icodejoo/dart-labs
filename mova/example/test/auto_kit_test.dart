import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova_example/verify_auto/auto_kit.dart';

void main() {
  group('Stats', () {
    test('odd count: median is the middle sample', () {
      final s = Stats([30, 10, 20]);
      expect((s.n, s.min, s.max, s.avg, s.median), (3, 10.0, 30.0, 20.0, 20.0));
    });

    test('even count: median averages the two middle samples', () {
      expect(Stats([1, 2, 3, 10]).median, 2.5);
    });
  });

  test('Samples summary lists raw values then statistics per series', () {
    final s = Samples()
      ..add('a', 100)
      ..add('a', 300)
      ..add('b', 5);
    expect(s.values('a'), [100.0, 300.0]);
    expect(s.values('none'), isEmpty);
    expect(s.summary(), [
      'a values=[100,300] n=2 min=100 max=300 avg=200.0 median=200.0',
      'b values=[5] n=1 min=5 max=5 avg=5.0 median=5.0',
    ]);
  });

  group('resolveLogPath / parseOnly', () {
    test('define wins over env, env is the fallback, none gives empty', () {
      expect(resolveLogPath(define: 'a.log', env: {'MOVA_LOG': 'b.log'}), 'a.log');
      expect(resolveLogPath(define: '', env: {'MOVA_LOG': 'b.log'}), 'b.log');
      expect(resolveLogPath(define: '', env: {}), '');
    });

    test('autoRuns: define wins, then MOVA_RUNS, then the default; bad values are ignored', () {
      expect(autoRuns(define: 5, env: {'MOVA_RUNS': '2'}), 5);
      expect(autoRuns(define: 0, env: {'MOVA_RUNS': '2'}), 2);
      expect(autoRuns(define: 0, env: {'MOVA_RUNS': 'x'}), kDefaultRuns);
      expect(autoRuns(define: 0, env: {'MOVA_RUNS': '0'}), kDefaultRuns);
      expect(autoRuns(define: 0, env: {}), kDefaultRuns);
    });

    test('autoOnlyRaw: define wins over MOVA_ONLY', () {
      expect(autoOnlyRaw(define: 'V1', env: {'MOVA_ONLY': 'V2'}), 'V1');
      expect(autoOnlyRaw(define: '', env: {'MOVA_ONLY': 'V2'}), 'V2');
      expect(autoOnlyRaw(define: '', env: {}), '');
    });

    test('parseOnly trims, upper-cases and drops blanks', () {
      expect(parseOnly(' v5, s1 ,,'), {'V5', 'S1'});
      expect(parseOnly(''), isEmpty);
    });
  });

  test('AutoLog appends tagged lines to the file', () {
    final dir = Directory.systemTemp.createTempSync('autolog');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = '${dir.path}/x.log';
    AutoLog('[T]', path: f)
      ..line('one')
      ..line('two');
    expect(File(f).readAsLinesSync(), ['[T] one', '[T] two']);
  });

  test('AutoLog creates a missing parent directory', () {
    final dir = Directory.systemTemp.createTempSync('autolog');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = '${dir.path}/a/b/x.log';
    AutoLog('[T]', path: f).line('nested');
    expect(File(f).readAsLinesSync(), ['[T] nested']);
  });

  group('EventRecorder', () {
    test('wait finds an already recorded event and a later one', () async {
      final c = StreamController<String>.broadcast();
      final rec = EventRecorder<String>(c.stream);
      c.add('x');
      await Future<void>.delayed(Duration.zero);
      expect((await rec.wait<String>(where: (e) => e == 'x'))?.event, 'x');
      final m = rec.mark;
      final pending = rec.wait<String>(from: m, where: (e) => e == 'y');
      c.add('y');
      expect((await pending)?.event, 'y');
      await rec.dispose();
      await c.close();
    });

    test('wait times out with null and from skips older events', () async {
      final c = StreamController<String>.broadcast();
      final rec = EventRecorder<String>(c.stream);
      c.add('old');
      await Future<void>.delayed(Duration.zero);
      final got = await rec.wait<String>(from: rec.mark, timeout: const Duration(milliseconds: 30));
      expect(got, isNull);
      expect(rec.all<String>().map((s) => s.event), ['old']);
      await rec.dispose();
      await c.close();
    });

    test('dispose releases pending waiters with null', () async {
      final c = StreamController<int>.broadcast();
      final rec = EventRecorder<int>(c.stream);
      final pending = rec.wait<int>(timeout: const Duration(seconds: 5));
      await rec.dispose();
      expect(await pending, isNull);
      await c.close();
    });
  });
}
