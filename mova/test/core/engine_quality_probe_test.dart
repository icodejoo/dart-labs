import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/testing.dart';
import 'package:mova/src/testing/hooks.dart';

import '../support/fake_kernel.dart';
import '../support/gated.dart';

/// 内存 master，不依赖任何网络响应。
final _master = Uint8List.fromList(utf8.encode(
  '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720\n720.m3u8\n',
));

/// 用户手选档，必须在探测返回后保持。
const _manual = MovaQuality(label: '720p', uri: 'https://h/720.m3u8');

/// 可逐次门控请求的 HTTP 端口。
class _Fetch implements MovaHttpFetch {
  /// 实际请求的 master 地址。
  final urls = <Uri>[];

  /// 每次请求独立的应答门。
  final replies = <Completer<Uint8List?>>[];

  @override
  Future<Uint8List?> get(Uri url) {
    urls.add(url);
    final reply = Completer<Uint8List?>();
    replies.add(reply);
    return reply.future;
  }

  @override
  Future<void> close() async {}
}

/// 带请求门控、事件记录和真实引擎的探测夹具。
class _Rig {
  /// [probe] 控制是否就绪后自动探测。
  _Rig(this.clock, {bool probe = true, bool recovery = false, int retries = 0}) {
    e = createMovaEngine(
      kernel: k,
      fetcher: fetch,
      brightness: MovaFallbackBrightnessPort(),
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
      options: MovaOpts(
        abr: MovaAbrConfig(probeVariants: probe),
        controls: const MovaCtrlsConfig(autoHide: false),
        recovery: MovaRecoveryConfig(
          enabled: recovery,
          policy: MovaRetryThenFailover(maxRetries: retries, retryDelay: Duration.zero),
        ),
      ),
    );
    e.events.listen(events.add);
  }

  /// 虚拟时钟。
  final FakeAsync clock;

  /// 可注入播放信号的内核。
  final k = FakeStatsKernel();

  /// 独立控制每次探测返回的 fetcher。
  final fetch = _Fetch();

  /// 被测真实引擎。
  late final MovaEngine e;

  /// 收集全部事件以检测迟到档位切换。
  final events = <MovaEvent>[];

  /// 严格记录两个会话应答的先后顺序。
  final log = CommandLog();

  /// 打开 [uri] 并排空可完成的微任务。
  void open([String uri = 'https://h/master.m3u8']) {
    e.open(MovaSource(uri));
    clock.flushMicrotasks();
  }

  /// 回答第 [index] 个请求。
  void reply(int index, Uint8List? bytes) {
    log.record(index, 'reply');
    fetch.replies[index].complete(bytes);
    clock.flushMicrotasks();
  }

  /// 销毁并验证没有遗留计时器。
  void close() {
    e.dispose();
    clock.flushMicrotasks();
    expect(clock.pendingTimers, isEmpty);
  }
}

void main() {
  for (final completed in [false, true]) {
    test('F-F failover probes new address after ${completed ? "completed" : "pending"} old probe', () {
      fakeAsync((clock) {
        final r = _Rig(clock, recovery: true);
        r.e.open(const MovaSource('https://h/a.m3u8', alternatives: ['https://h/b.m3u8']));
        clock.flushMicrotasks();
        final old = r.e.loadQualities();
        if (completed) r.reply(0, _master);
        r.k.emitEndFile(MovaEndFileReason.error);
        clock.flushMicrotasks();
        clock.elapse(Duration.zero);
        expect(r.e.state.sourceIndex, 1);
        final next = r.e.loadQualities();
        clock.flushMicrotasks();
        expect(identical(old, next), isFalse);
        expect(r.fetch.urls.map((u) => u.toString()), ['https://h/a.m3u8', 'https://h/b.m3u8']);
        r.reply(1, _master);
        final count = r.events.whereType<MovaQualityListChange>().length;
        if (!completed) r.reply(0, null);
        expect(r.e.state.qualities.last.uri, 'https://h/720.m3u8');
        expect(r.e.state.qualities, hasLength(2));
        expect(r.events.whereType<MovaQualityListChange>(), hasLength(count));
        expect(identical(next, r.e.loadQualities()), isTrue);
        r.close();
      });
    });
  }

  test('F-F same address quality switch and recovery retry reuse probe', () {
    fakeAsync((clock) {
      final r = _Rig(clock, recovery: true, retries: 1)..open();
      final pending = r.e.loadQualities();
      r.e.switchQuality(_manual);
      clock.flushMicrotasks();
      r.k.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      clock.elapse(Duration.zero);
      expect(r.k.lastUri, _manual.uri);
      expect(r.e.state.sourceIndex, 0);
      expect(identical(pending, r.e.loadQualities()), isTrue);
      r.reply(0, _master);
      expect(identical(pending, r.e.loadQualities()), isTrue);
      expect(r.fetch.urls, hasLength(1));
      r.close();
    });
  });

  test('A12 imperative open probes by default without a mounted player', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open();
      expect(r.fetch.replies, hasLength(1));
      r.reply(0, _master);
      expect(r.e.state.qualities.map((q) => q.label), ['自动', '720p']);
      expect(r.e.state.currentQuality!.isAuto, isTrue);
      expect(r.events.whereType<MovaQualityListChange>(), hasLength(1));
      expect(const MovaAbrConfig().probeVariants, isTrue);
      expect(const MovaAbrConfig(), isNot(const MovaAbrConfig(probeVariants: false)));
      expect(const MovaAbrConfig().hashCode,
          isNot(const MovaAbrConfig(probeVariants: false).hashCode));
      r.close();
    });
  });

  test('A12 in flight probe publishes list without overwriting manual quality', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open();
      r.e.switchQuality(_manual);
      clock.flushMicrotasks();
      r.reply(0, _master);
      expect(r.e.state.currentQuality, _manual);
      expect(r.e.state.qualities, hasLength(2));
      expect(r.events.whereType<MovaQualityChange>().map((v) => v.quality), [_manual]);
      expect(r.k.lastUri, _manual.uri);
      r.close();
    });
  });

  test('A12 null and throwing probes preserve manual selection too', () {
    for (final throws in [false, true]) {
      fakeAsync((clock) {
        final r = _Rig(clock)..open();
        r.e.switchQuality(_manual);
        clock.flushMicrotasks();
        if (throws) {
          r.fetch.replies.single.completeError(StateError('fetch failed'));
          clock.flushMicrotasks();
        } else {
          r.reply(0, null);
        }
        expect(r.e.state.currentQuality, _manual);
        expect(r.e.state.qualities, isEmpty);
        r.close();
      });
    }
  });

  test('A12 automatic and explicit probes share one task per session', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open();
      final one = r.e.loadQualities();
      final two = r.e.loadQualities();
      expect(identical(one, two), isTrue);
      expect(r.fetch.replies, hasLength(1));
      r.reply(0, _master);
      r.e.loadQualities();
      r.e.switchQuality(_manual);
      clock.flushMicrotasks();
      r.e.loadQualities();
      clock.flushMicrotasks();
      expect(r.fetch.replies, hasLength(1));
      r.open();
      expect(r.fetch.replies, hasLength(2));
      r.reply(1, _master);
      expect(r.e.state.currentQuality!.isAuto, isTrue);
      r.close();
    });
  });

  test('A12 old probe cannot mutate the new session or publish stale events', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open();
      r.open('https://h/new.m3u8');
      r.reply(1, _master);
      r.e.switchQuality(_manual);
      clock.flushMicrotasks();
      final count = r.events.whereType<MovaQualityListChange>().length;
      r.reply(0, null);
      expect(r.log.entries.map((v) => v.instance), [1, 0]);
      expect(r.e.state.currentQuality, _manual);
      expect(r.e.state.qualities, hasLength(2));
      expect(r.events.whereType<MovaQualityListChange>(), hasLength(count));
      r.close();
    });
  });

  test('A12 disabled probing stays explicit and test seam defaults to noop HTTP', () {
    fakeAsync((clock) {
      final r = _Rig(clock, probe: false)..open();
      expect(r.fetch.replies, isEmpty);
      r.e.switchQuality(_manual);
      clock.flushMicrotasks();
      r.e.loadQualities();
      clock.flushMicrotasks();
      r.reply(0, _master);
      expect(r.e.state.currentQuality, _manual);
      r.close();
      MovaTesting.useTestKernels();
      final e = createMovaEngine(options: const MovaOpts(
        controls: MovaCtrlsConfig(autoHide: false),
      ));
      e.open(const MovaSource('https://h/test.m3u8'));
      clock.flushMicrotasks();
      expect(e.state.qualities, isEmpty);
      expect(clock.pendingTimers, isEmpty);
      e.dispose();
      const noop = MovaTestHttpFetch();
      noop.get(Uri.parse('https://h/noop.m3u8')).then((v) => expect(v, isNull));
      noop.close();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
      MovaTesting.reset();
    });
  });
}
