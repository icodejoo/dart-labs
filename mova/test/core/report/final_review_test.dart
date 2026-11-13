import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/report/collector.dart';

import '../../support/fake_api.dart';
import '../../support/fake_kernel.dart';

/// Provides deterministic time and synchronous collector input.
///
/// 提供可控时钟与同步收集器输入。
class _Rig {
  /// Creates a session with optional native probe signals.
  ///
  /// 创建会话，可选注入原生探针信号。
  _Rig({bool autoPlay = true, this.probe, IMovaStallPolicy? stallPolicy}) {
    collector = MovaQoeCollector(
      events: events.stream,
      reporter: MovaCallbackReporter(reports.add),
      opts: MovaReportOpts(qoe: true, stallPolicy: stallPolicy),
      probe: probe,
      now: () => clock,
    );
    collector.onOpen(
      const MovaSource('https://host/video'),
      autoPlay: autoPlay,
    );
  }

  final FakeStatsProbe? probe;
  final events = StreamController<MovaEvent>.broadcast(sync: true);
  final reports = <MovaReportEvent>[];
  DateTime clock = DateTime.utc(2026);
  late final MovaQoeCollector collector;

  /// Advances the accounting clock by seconds.
  ///
  /// 按秒推进统计时钟。
  void advance(int seconds) => clock = clock.add(Duration(seconds: seconds));
  void advanceMs(int ms) => clock = clock.add(Duration(milliseconds: ms));

  /// Returns the completed session summary.
  ///
  /// 返回已结束会话的汇总。
  MovaReportEvent get end =>
      reports.lastWhere((r) => r.name == MovaReportName.sessionEnd);

  /// Releases collector and probe subscriptions.
  ///
  /// 释放收集器和探针订阅。
  Future<void> close() async {
    await collector.cancel();
    await events.close();
    await probe?.dispose();
  }
}

/// Covers the final-review QoE error and manual-start regressions.
///
/// 覆盖终审确认的 QoE 错误与手动起播回归。
void main() {
  test('B2 grace first frame lands autoplay with native subscription / 宽限首帧落地自动播放', () async {
    final probe = FakeStatsProbe()..nativeRestartAvailable = true;
    final r = _Rig(probe: probe);
    addTearDown(r.close);
    r.events.add(const MovaPlay());
    r.advance(2);
    r.events.add(const MovaFirstFrame(
      sinceOpen: Duration(seconds: 2), signal: MovaFirstFrameSignal.grace,
    ));
    r.advance(3);
    probe.pushRestart();
    await Future<void>.delayed(Duration.zero);
    r.events.add(const MovaFirstFrame(
      sinceOpen: Duration(seconds: 5), signal: MovaFirstFrameSignal.restart,
    ));
    r.collector.onTeardown();
    expect(r.end.params['watchedMs'], 3000);
    expect(r.end.params['reason'], 'stopped');
    final frames = r.reports.where((e) => e.name == MovaReportName.firstFrame);
    expect(frames, hasLength(1));
    expect(frames.single.params['signal'], 'grace');
    expect(frames.single.params['ttffMs'], 2000);
    expect(r.reports.where((e) => e.name == MovaReportName.startupFail), isEmpty);
  });

  for (final native in [false, true]) {
    test('B2 completion ignores pre-frame residue / 完成率忽略首帧前残留 native=$native', () async {
      final probe = native ? (FakeStatsProbe()..nativeRestartAvailable = true) : null;
      final r = _Rig(probe: probe);
      addTearDown(r.close);
      r.events.add(const MovaDurationChange(Duration(seconds: 10)));
      r.collector.onPosition(const Duration(seconds: 90));
      r.collector.onPosition(Duration.zero);
      if (probe != null) {
        probe.pushRestart();
        await Future<void>.delayed(Duration.zero);
      }
      r.collector.onPosition(const Duration(milliseconds: 100));
      r.collector.onPosition(const Duration(milliseconds: 200));
      r.collector.onPosition(const Duration(seconds: 5));
      r.collector.onTeardown();
      expect(r.end.params['completionPercent'], 50);
    });
  }

  test('B2 zero plus stale position cannot start autoplay / 零位置加残留位置不起播', () async {
    final r = _Rig();
    addTearDown(r.close);
    r.events.add(const MovaPlay());
    r.events.add(const MovaDurationChange(Duration(seconds: 10)));
    r.collector.onPosition(Duration.zero);
    r.advance(1);
    r.collector.onPosition(const Duration(seconds: 90));
    r.advance(3);
    r.collector.onTeardown();
    expect(r.end.params['watchedMs'], 0);
    expect(r.end.params['completionPercent'], 0);
    expect(r.reports.where((e) => e.name == MovaReportName.firstFrame), isEmpty);
    expect(r.reports.where((e) => e.name == MovaReportName.startupFail), hasLength(1));
  });

  for (final native in [false, true]) {
    for (final healsWhilePaused in [false, true]) {
      test('D10 pause excludes idle time, native=$native heal=$healsWhilePaused', () async {
        final probe = native ? FakeStatsProbe() : null;
        final r = _Rig(autoPlay: false, probe: probe);
        r.events.add(const MovaFirstFrame(sinceOpen: Duration.zero,
            signal: MovaFirstFrameSignal.restart));
        r.events.add(const MovaPlay());
        // Feeds either the native probe or the degraded buffering signal.
        //
        // 喂入原生探针或退化缓冲信号。
        Future<void> observe(bool stalled) async {
          if (probe == null) {
            r.events.add(MovaBufferChange(stalled));
          } else {
            probe.pushStalling(stalled);
            await Future<void>.delayed(Duration.zero);
          }
        }
        r.advance(2);
        await observe(true);
        r.advance(1);
        r.events.add(const MovaPause());
        r.advance(60);
        if (healsWhilePaused) await observe(false);
        r.events.add(const MovaPlay());
        r.advance(2);
        await observe(false);
        r.collector.onTeardown();
        expect(r.end.params['stallMs'], healsWhilePaused ? 1000 : 3000);
        expect(r.end.params['stallCount'], healsWhilePaused ? 1 : 2);
        expect(r.end.params['watchedMs'], healsWhilePaused ? 4000 : 2000);
        final durations = r.reports.where((e) => e.name == MovaReportName.rebuffer)
            .map((e) => e.params['durationMs']).toList();
        expect(durations, healsWhilePaused ? [1000] : [1000, 2000]);
        await r.close();
      });
    }
  }

  test('D12 jitter below minStall counts neither a stall nor stallMs', () async {
    final r = _Rig(autoPlay: false, stallPolicy: MovaEdgeStall(minStall: const Duration(seconds: 1)));
    r.events.add(const MovaFirstFrame(sinceOpen: Duration.zero,
        signal: MovaFirstFrameSignal.restart));
    r.events.add(const MovaPlay());
    for (var i = 0; i < 10; i++) {
      r.events.add(const MovaBufferChange(true));
      r.advanceMs(100);
      r.events.add(const MovaBufferChange(false));
      r.advanceMs(100);
    }
    r.collector.onTeardown();
    expect(r.end.params['stallCount'], 0);
    expect(r.end.params['stallMs'], 0);
    await r.close();
  });

  test('D10 teardown while paused excludes the paused stall tail', () async {
    final r = _Rig(autoPlay: false);
    r.events.add(const MovaFirstFrame(sinceOpen: Duration.zero,
        signal: MovaFirstFrameSignal.restart));
    r.events.add(const MovaPlay());
    r.events.add(const MovaBufferChange(true));
    r.advance(1);
    r.events.add(const MovaPause());
    r.advance(60);
    r.collector.onTeardown();
    expect(r.end.params['stallMs'], 1000);
    expect(r.end.params['stallCount'], 1);
    await r.close();
  });

  test('D11 injected edge policy resets on quality changes', () async {
    final r = _Rig(autoPlay: false, stallPolicy: MovaEdgeStall());
    r.events.add(const MovaFirstFrame(sinceOpen: Duration.zero,
        signal: MovaFirstFrameSignal.restart));
    r.events.add(const MovaPlay());
    r.events.add(const MovaBufferChange(true));
    r.advance(1);
    r.events.add(MovaQualityChange(MovaQuality.auto()));
    r.events.add(const MovaBufferChange(false));
    r.advance(60);
    r.events.add(const MovaBufferChange(true));
    r.advance(2);
    r.events.add(const MovaBufferChange(false));
    final stalls = r.reports.where((e) => e.name == MovaReportName.rebuffer).toList();
    expect(stalls, hasLength(1));
    expect(stalls.single.params['durationMs'], 2000);
    expect(stalls.single.params['index'], 1);
    await r.close();
  });

  test('D11 injected edge policy resets at the next session boundary', () async {
    final r = _Rig(autoPlay: false, stallPolicy: MovaEdgeStall());
    r.events.add(const MovaFirstFrame(sinceOpen: Duration.zero,
        signal: MovaFirstFrameSignal.restart));
    r.events.add(const MovaPlay());
    r.events.add(const MovaBufferChange(true));
    r.advance(1);
    r.collector.onTeardown();
    r.advance(60);
    r.collector.onOpen(const MovaSource('https://host/next'), autoPlay: false);
    r.events.add(const MovaFirstFrame(sinceOpen: Duration.zero,
        signal: MovaFirstFrameSignal.restart));
    r.events.add(const MovaPlay());
    r.events.add(const MovaBufferChange(true));
    r.advance(2);
    r.events.add(const MovaBufferChange(false));
    r.collector.onTeardown();
    expect(r.end.params['stallMs'], 2000);
    expect(r.end.params['stallCount'], 1);
    expect(r.reports.singleWhere((e) => e.name == MovaReportName.rebuffer)
        .params['durationMs'], 2000);
    await r.close();
  });

  test(
    'D8 fatal without code keeps severity and fills code from log',
    () async {
      final probe = FakeStatsProbe();
      final r = _Rig(probe: probe);
      probe.pushLog(
        const MovaLogLine(prefix: 'vd', level: 'error', text: 'open failed'),
      );
      await Future<void>.delayed(Duration.zero);
      r.events.add(const MovaErrorEvent.classified('open failed', fatal: true));
      r.collector.onTeardown();
      final error = r.reports.singleWhere(
        (e) => e.name == MovaReportName.error,
      );
      expect(error.params['fatal'], isTrue);
      expect(error.params['code'], 'decode.video');
      expect(error.priority, MovaReportPriority.immediate);
      expect(r.end.params['reason'], 'failed');
      await r.close();
    },
  );

  test('D9 manual playback records valid positions through EOF', () async {
    final r = _Rig(autoPlay: false);
    r.events.add(const MovaDurationChange(Duration(seconds: 100)));
    r.events.add(
      const MovaFirstFrame(
        sinceOpen: Duration.zero,
        signal: MovaFirstFrameSignal.restart,
      ),
    );
    r.events.add(const MovaPlay());
    r.collector.onPosition(const Duration(seconds: 99));
    r.events.add(const MovaDone());
    r.collector.onTeardown();
    expect(r.end.params['reason'], 'ended');
    expect(r.end.params['completionPercent'], 99);
    expect(r.reports.where((e) => e.name == MovaReportName.error), isEmpty);
    await r.close();
  });

  test(
    'D8 classified diagnostic stays nonfatal despite a fatal log prefix',
    () async {
      final probe = FakeStatsProbe();
      final r = _Rig(probe: probe);
      r.events.add(const MovaPlay());
      r.collector.onPosition(const Duration(milliseconds: 100));
      r.collector.onPosition(const Duration(milliseconds: 200));
      probe.pushLog(
        const MovaLogLine(prefix: 'stream', level: 'error', text: 'retry'),
      );
      await Future<void>.delayed(Duration.zero);
      r.events.add(
        const MovaErrorEvent.classified('retry', fatal: false, code: 'network'),
      );
      r.collector.onTeardown();
      final error = r.reports.singleWhere(
        (e) => e.name == MovaReportName.error,
      );
      expect(error.params['fatal'], isFalse);
      expect(error.params['code'], 'network');
      expect(error.priority, MovaReportPriority.batched);
      expect(r.end.params['reason'], 'stopped');
      await r.close();
    },
  );

  test(
    'D8 fatal event without logs preserves player code and fails session',
    () async {
      final r = _Rig();
      r.events.add(
        const MovaErrorEvent.classified(
          'open failed',
          fatal: true,
          code: 'open',
        ),
      );
      r.collector.onTeardown();
      final error = r.reports.singleWhere(
        (e) => e.name == MovaReportName.error,
      );
      expect(error.params['fatal'], isTrue);
      expect(error.params['code'], 'open');
      expect(error.priority, MovaReportPriority.immediate);
      expect(r.end.params['reason'], 'failed');
      expect(
        r.reports
            .singleWhere((e) => e.name == MovaReportName.startupFail)
            .params['reason'],
        'failed',
      );
      await r.close();
    },
  );

  test('D8 paired decoder log cannot downgrade player fatal or code', () async {
    final probe = FakeStatsProbe();
    final r = _Rig(probe: probe);
    probe.pushLog(
      const MovaLogLine(prefix: 'vd', level: 'error', text: 'decoder failed'),
    );
    await Future<void>.delayed(Duration.zero);
    r.events.add(
      const MovaErrorEvent.classified(
        'decoder failed',
        fatal: true,
        code: 'mova.decode',
      ),
    );
    final error = r.reports.singleWhere((e) => e.name == MovaReportName.error);
    expect(error.params['fatal'], isTrue);
    expect(error.params['code'], 'mova.decode');
    await r.close();
  });

  test('D8 logs still fill in missing error codes', () async {
    final probe = FakeStatsProbe();
    final r = _Rig(probe: probe);
    probe.pushLog(
      const MovaLogLine(prefix: 'stream', level: 'error', text: 'not found'),
    );
    await Future<void>.delayed(Duration.zero);
    r.events.add(const MovaErrorEvent('not found'));
    expect(
      r.reports
          .singleWhere((e) => e.name == MovaReportName.error)
          .params['code'],
      'stream',
    );
    await r.close();
  });

  test(
    'D8 kernel open exception reports failed without a matching log',
    () async {
      final kernel = FakeKernel()..openError = StateError('open failed');
      final reports = <MovaReportEvent>[];
      final mova = createMova(
        kernel: kernel,
        pip: MovaNoopPip(),
        orient: MovaNoopOrient(),
        brightness: MovaFallbackBrightness(),
        reporter: MovaCallbackReporter(reports.add),
        options: const MovaOpts(report: MovaReportOpts(qoe: true)),
      );
      await expectLater(
        mova.open(const MovaSource('https://host/video')),
        throwsStateError,
      );
      expect(kernel.calls, contains('open'));
      await Future<void>.delayed(Duration.zero);
      await mova.dispose();
      expect(
        reports
            .singleWhere((e) => e.name == MovaReportName.error)
            .params['fatal'],
        isTrue,
      );
      expect(
        reports
            .singleWhere((e) => e.name == MovaReportName.sessionEnd)
            .params['reason'],
        'failed',
      );
    },
  );

  test(
    'D9 manual play counts watch time and stalls without TTFF or preload time',
    () async {
      final r = _Rig(autoPlay: false);
      r.advance(30);
      r.events.add(
        const MovaFirstFrame(
          sinceOpen: Duration.zero,
          signal: MovaFirstFrameSignal.restart,
        ),
      );
      r.events.add(const MovaPlay());
      r.advance(2);
      r.events.add(const MovaBufferChange(true));
      r.advance(1);
      r.events.add(const MovaBufferChange(false));
      r.advance(3);
      r.events.add(const MovaPause());
      r.advance(10);
      r.collector.onTeardown();
      expect(r.end.params['watchedMs'], 5000);
      expect(r.end.params['stallMs'], 1000);
      expect(r.end.params['stallCount'], 1);
      expect(r.end.params['reason'], 'stopped');
      expect(
        r.reports.where((e) => e.name == MovaReportName.rebuffer),
        hasLength(1),
      );
      expect(
        r.reports.where(
          (e) =>
              e.name == MovaReportName.firstFrame ||
              e.name == MovaReportName.startupFail,
        ),
        isEmpty,
      );
      await r.close();
    },
  );

  test(
    'D9 cold manual play before first frame counts neither watch time nor stalls',
    () async {
      final r = _Rig(autoPlay: false);
      r.events.add(const MovaDurationChange(Duration(seconds: 100)));
      r.events.add(const MovaPlay());
      r.advance(2);
      r.events.add(const MovaBufferChange(true));
      r.advance(3);
      r.events.add(const MovaBufferChange(false));
      r.advance(2);
      r.collector.onTeardown();
      expect(r.end.params['watchedMs'], 0);
      expect(r.end.params['stallMs'], 0);
      expect(r.end.params['stallCount'], 0);
      expect(r.end.params['reason'], 'abandoned');
      expect(
        r.reports.where(
          (e) =>
              e.name == MovaReportName.rebuffer ||
              e.name == MovaReportName.firstFrame ||
              e.name == MovaReportName.startupFail,
        ),
        isEmpty,
      );
      await r.close();
    },
  );

  test(
    'D9 native manual-start path counts watch time and cache stalls',
    () async {
      final probe = FakeStatsProbe()..nativeRestartAvailable = true;
      final r = _Rig(autoPlay: false, probe: probe);
      probe.pushRestart();
      await Future<void>.delayed(Duration.zero);
      r.advance(20);
      r.events.add(const MovaPlay());
      r.advance(2);
      probe.pushStalling(true);
      await Future<void>.delayed(Duration.zero);
      r.advance(1);
      probe.pushStalling(false);
      await Future<void>.delayed(Duration.zero);
      r.collector.onTeardown();
      expect(r.end.params['watchedMs'], 2000);
      expect(r.end.params['stallCount'], 1);
      expect(r.end.params['stallMs'], 1000);
      expect(
        r.reports.where((e) => e.name == MovaReportName.firstFrame),
        isEmpty,
      );
      await r.close();
    },
  );

  test(
    'D9 manual first-frame signal lands without counting paused preload',
    () async {
      final r = _Rig(autoPlay: false);
      r.events.add(
        const MovaFirstFrame(
          sinceOpen: Duration.zero,
          signal: MovaFirstFrameSignal.restart,
        ),
      );
      r.advance(20);
      r.collector.onTeardown();
      expect(r.end.params['reason'], 'stopped');
      expect(r.end.params['watchedMs'], 0);
      expect(
        r.reports.where((e) => e.name == MovaReportName.firstFrame),
        isEmpty,
      );
      await r.close();
    },
  );

  test(
    'D9 unopened manual playback remains abandoned with zero watch time',
    () async {
      final r = _Rig(autoPlay: false);
      r.advance(20);
      r.collector.onTeardown();
      expect(r.end.params['reason'], 'abandoned');
      expect(r.end.params['watchedMs'], 0);
      await r.close();
    },
  );

  test(
    'D9 new autoplay session still waits for first frame and emits TTFF once',
    () async {
      final r = _Rig(autoPlay: false);
      r.events.add(const MovaPlay());
      r.collector.onTeardown();
      r.collector.onOpen(const MovaSource('https://host/next'), autoPlay: true);
      r.events.add(const MovaPlay());
      r.advance(5);
      r.collector.onPosition(const Duration(milliseconds: 100));
      r.collector.onPosition(const Duration(milliseconds: 200));
      r.advance(2);
      r.collector.onPosition(const Duration(seconds: 2));
      r.collector.onTeardown();
      expect(r.end.params['watchedMs'], 2000);
      expect(
        r.reports.where((e) => e.name == MovaReportName.firstFrame),
        hasLength(1),
      );
      expect(
        r.reports
            .singleWhere((e) => e.name == MovaReportName.firstFrame)
            .params['ttffMs'],
        5000,
      );
      await r.close();
    },
  );
}
