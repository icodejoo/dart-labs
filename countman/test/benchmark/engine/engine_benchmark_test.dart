@Tags(['benchmark'])
library;

import 'package:countman/countman.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/manual_clock.dart';

/// 每帧间隔，模拟 60Hz。
const _frame = Duration(milliseconds: 16);

/// 预热帧数。
const _warmup = 200;

/// 批数与每批帧数；输出批均值中位数。
const _batches = 9;
const _framesPerBatch = 300;

/// 对 [body] 做批量计时，返回每次调用的中位数微秒。
double _measure(void Function() body, {int frames = _framesPerBatch}) {
  for (var i = 0; i < _warmup; i++) {
    body();
  }
  final samples = <double>[];
  final sw = Stopwatch();
  for (var b = 0; b < _batches; b++) {
    sw.reset();
    sw.start();
    for (var i = 0; i < frames; i++) {
      body();
    }
    sw.stop();
    samples.add(sw.elapsedMicroseconds / frames);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

void _report(String name, double us, {int? n}) {
  final per = n == null
      ? ''
      : ' per-task=${(us / n * 1000).toStringAsFixed(1)}ns';
  // ignore: avoid_print
  print('BENCH $name: median=${us.toStringAsFixed(2)} us/frame$per');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // add() 会登记帧回调；每个用例后清掉全局 ticker，避免互相影响。
  tearDown(Countman.destroy);

  group('引擎 tick（直接驱动插件，不含 widget）', () {
    for (final n in [100, 1000, 10000]) {
      test('Counter tick n=$n', () {
        final p = Counter(name: 'bench-counter-$n');
        for (var i = 0; i < n; i++) {
          p.add(
            CounterOptions(
              to: 1e9,
              duration: const Duration(hours: 10),
              onUpdate: (_) {},
            ),
          );
        }
        var t = Duration.zero;
        final us = _measure(() {
          t += _frame;
          p.tick(t, _frame);
        });
        _report('Counter.tick n=$n', us, n: n);
        p.dispose();
      });
    }

    for (final interval in [1000, 0]) {
      for (final n in [100, 1000, 10000]) {
        test('Countdown tick interval=$interval n=$n', () {
          final clock = installManualClock();
          final p = Countdown(
            name: 'bench-cd-$interval-$n',
            interval: interval,
            clock: clock,
          );
          for (var i = 0; i < n; i++) {
            p.add(
              CountdownOptions(
                duration: const Duration(hours: 10),
                onUpdate: (_) {},
              ),
            );
          }
          var t = Duration.zero;
          final us = _measure(() {
            clock.advance(_frame);
            t += _frame;
            p.tick(t, _frame);
          });
          _report('Countdown.tick interval=$interval n=$n', us, n: n);
          p.dispose();
        });
      }
    }

    for (final n in [100, 1000, 10000]) {
      test('Elapsed tick interval=0 n=$n', () {
        final clock = installManualClock();
        final p = Elapsed(name: 'bench-el-$n', interval: 0, clock: clock);
        for (var i = 0; i < n; i++) {
          p.add(ElapsedOptions(onUpdate: (_) {}));
        }
        var t = Duration.zero;
        final us = _measure(() {
          clock.advance(_frame);
          t += _frame;
          p.tick(t, _frame);
        });
        _report('Elapsed.tick interval=0 n=$n', us, n: n);
        p.dispose();
      });
    }

    for (final n in [1000, 10000]) {
      test('add() 批量创建 n=$n', () {
        final sw = Stopwatch()..start();
        final p = Counter(name: 'bench-add-$n');
        for (var i = 0; i < n; i++) {
          p.add(const CounterOptions(to: 100));
        }
        sw.stop();
        _report(
          'Counter.add x$n total',
          sw.elapsedMicroseconds.toDouble(),
          n: n,
        );
        p.dispose();
      });
    }
  });
}
