import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/engine/load_spec.dart';

import '../support/fake_kernel.dart';
import '../support/gated.dart';

/// 每条用例共享的手选档。
const _q = MovaQuality(label: '720p', uri: 'https://h/720.m3u8');

/// 连续换档的后一个目标档。
const _q2 = MovaQuality(label: '480p', uri: 'https://h/480.m3u8');

/// 用内存 master 构造真实清晰度列表，避免网络计时器。
class _Fetch implements MovaHttpFetch {
  @override
  Future<Uint8List?> get(Uri url) async => Uint8List.fromList(utf8.encode(
    '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720\n720.m3u8\n'
    '#EXT-X-STREAM-INF:BANDWIDTH=500000,RESOLUTION=854x480\n480.m3u8\n',
  ));

  @override
  Future<void> close() async {}
}

/// 加载规格回归夹具，记录真实引擎事件及门控动作顺序。
class _Rig {
  /// 用 [clock] 驱动时间，[live] 指定直播配置，[retries] 控制故障切换。
  /// [kernel] 可注入待机内核，默认使用具备原生错误流的假内核。
  _Rig(this.clock, {MovaLiveConfig live = const MovaLiveConfig(), int retries = 1,
    FakeStatsKernel? kernel,
  }) : k = kernel ?? FakeStatsKernel() {
    e = createMovaEngine(
      kernel: k,
      pip: MovaNoopPipPort(),
      orientation: MovaNoopOrientationPort(),
      brightness: MovaFallbackBrightnessPort(),
      fetcher: _Fetch(),
      options: MovaOpts(
        controls: const MovaCtrlsConfig(autoHide: false),
        live: live,
        recovery: MovaRecoveryConfig(
          enabled: true,
          policy: MovaRetryThenFailover(maxRetries: retries, retryDelay: const Duration(milliseconds: 10)),
        ),
      ),
    );
    e.events.listen(events.add);
  }

  /// 用例的虚拟时钟。
  final FakeAsync clock;

  /// 可门控加载并推原生错误的内核。
  final FakeStatsKernel k;

  /// 经公开工厂创建的被测引擎。
  late final MovaEngine e;

  /// 全部事件，核对内部加载不增加会话公告。
  final events = <MovaEvent>[];

  /// 交错命令严格顺序。
  final log = CommandLog();

  /// 打开 [live] 指定类型的 master，并探测内存清晰度。
  void open({bool live = false}) {
    e.open(MovaSource('https://h/master.m3u8',
      type: live ? MovaStreamType.live : MovaStreamType.vod,
      alternatives: const ['https://h/backup.m3u8'],
    ));
    clock.flushMicrotasks();
    e.loadQualities();
    clock.flushMicrotasks();
  }

  /// 报告时长和 42 秒位置，使初始点播呈现。
  void position() {
    k.emitDuration(const Duration(minutes: 5));
    k.emitPosition(const Duration(seconds: 41));
    k.emitPosition(const Duration(seconds: 42));
    clock.flushMicrotasks();
  }

  /// 切到 [q] 并排空当前可完成的微任务，网络闸门仍可挂起。
  void quality(MovaQuality q) {
    e.switchQuality(q).then((_) => log.record(0, q.label));
    clock.flushMicrotasks();
  }

  /// 通过真实原生错误入口触发恢复及其退避。
  void fail() {
    k.emitEndFile(MovaEndFileReason.error);
    clock.flushMicrotasks();
    clock.elapse(const Duration(milliseconds: 10));
    clock.flushMicrotasks();
  }

  /// 报时长及首帧，使寄存的续播目标生效。
  void land() {
    k.emitDuration(const Duration(minutes: 5));
    k.emitBuffering(true);
    k.emitBuffering(false);
    clock.flushMicrotasks();
  }

  /// 检查同一 open 中的 SourceChange/Ready 均只发一次。
  void oneSession() {
    expect(events.whereType<MovaSourceChange>(), hasLength(1));
    expect(events.whereType<MovaReady>(), hasLength(1));
  }

  /// 销毁并清理全部计时器和流。
  void close() {
    e.dispose();
    clock.flushMicrotasks();
  }
}

void main() {
  test('A10 selected 720p retry keeps effective URI list and failure position', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open()..position()..quality(_q)..land();
      r.k.emitPosition(const Duration(seconds: 42));
      clock.flushMicrotasks();
      final list = r.e.state.qualities;
      r.fail();
      expect(r.k.lastUri, _q.uri);
      expect(r.e.state.currentQuality, _q);
      expect(r.e.state.qualities, list);
      expect(r.e.state.duration, Duration.zero);
      expect(r.e.progressValue.position, Duration.zero);
      expect(r.e.debugCurrentLoad!.reason, LoadReason.retry);
      r.oneSession();
      r.land();
      expect(r.k.lastSeek, const Duration(seconds: 42));
      // 再次换档在 open 期间失败时，规格里的续播点同样不能丢失。
      final gate = r.k.openGate = Completer<void>();
      r.quality(_q2);
      r.k.emitEndFile(MovaEndFileReason.error);
      clock.flushMicrotasks();
      r.k.openGate = null;
      gate.complete();
      clock.flushMicrotasks();
      clock.elapse(const Duration(milliseconds: 10));
      clock.flushMicrotasks();
      expect(r.k.lastUri, _q2.uri);
      r.land();
      expect(r.k.lastSeek, const Duration(seconds: 42));
      r.close();
    });
  });

  test('A10 timeshift retry rebuilds URL from fixed lag despite later ticks', () {
    fakeAsync((clock) {
      final requests = <({String uri, Duration behind, DateTime now})>[];
      final r = _Rig(clock, live: MovaLiveConfig(
        seekMode: MovaLiveSeekMode.timeshift,
        dvrWindow: const Duration(minutes: 10),
        urlBuilder: (uri, behind, now) {
          requests.add((uri: uri, behind: behind, now: now));
          return '$uri?behind=${behind.inSeconds}&request=${requests.length}';
        },
      ))..open(live: true);
      r.e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      r.k.emitPosition(const Duration(seconds: 1));
      clock.flushMicrotasks();
      r.fail();
      expect(requests, hasLength(2));
      expect(requests.last.behind, const Duration(minutes: 3));
      expect(requests.last.uri, requests.first.uri);
      expect(r.k.lastUri, endsWith('behind=180&request=2'));
      expect(r.e.state.timeshiftBehind, const Duration(minutes: 3));
      expect(r.e.debugCurrentLoad!.timeshiftBehind, const Duration(minutes: 3));
      r.oneSession();
      r.close();
    });
  });

  test('A10 failover clears old quality list and timeshift without new session', () {
    fakeAsync((clock) {
      final r = _Rig(clock, retries: 0, live: MovaLiveConfig(
        seekMode: MovaLiveSeekMode.timeshift,
        dvrWindow: const Duration(minutes: 10),
        urlBuilder: (uri, behind, now) => '$uri?behind=${behind.inSeconds}',
      ))..open(live: true)..quality(_q);
      r.k.emitDuration(const Duration(minutes: 5));
      clock.flushMicrotasks();
      r.e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      r.fail();
      expect(r.k.lastUri, 'https://h/backup.m3u8');
      expect(r.e.state.sourceIndex, 1);
      expect(r.e.state.currentQuality, isNull);
      expect(r.e.state.qualities, isEmpty);
      expect(r.e.state.timeshiftBehind, isNull);
      expect(r.e.state.duration, Duration.zero);
      expect(r.e.progressValue.position, Duration.zero);
      expect(r.e.debugCurrentLoad!.reason, LoadReason.failover);
      r.oneSession();
      r.close();
    });
  });

  test('A10 live edge replays selected quality and preserves duration and list', () {
    fakeAsync((clock) {
      final r = _Rig(clock, live: const MovaLiveConfig(backToLive: MovaBackToLive.reopen))
        ..open(live: true)..quality(_q);
      r.k.emitDuration(const Duration(minutes: 5));
      clock.flushMicrotasks();
      final list = r.e.state.qualities;
      r.e.backToLiveEdge();
      clock.flushMicrotasks();
      expect(r.k.lastUri, _q.uri);
      expect(r.e.state.currentQuality, _q);
      expect(r.e.state.qualities, list);
      expect(r.e.state.duration, const Duration(minutes: 5));
      expect(r.e.state.timeshiftBehind, isNull);
      expect(r.e.debugCurrentLoad!.reason, LoadReason.liveEdge);
      expect(r.k.calls, contains('play'));
      r.oneSession();
      r.close();
      // 待机因结束而重开，同属 liveEdge：保留档位并退出时移。
      final held = FakeKeepAliveStatsKernel();
      final wake = _Rig(clock, kernel: held, live: MovaLiveConfig(
        seekMode: MovaLiveSeekMode.timeshift,
        dvrWindow: const Duration(minutes: 10),
        urlBuilder: (uri, behind, now) => '$uri?behind=${behind.inSeconds}',
      ))..open(live: true)..quality(_q);
      held.emitDuration(const Duration(minutes: 5));
      wake.e.seek(const Duration(minutes: 7));
      clock.flushMicrotasks();
      expect(wake.e.state.timeshiftBehind, const Duration(minutes: 3));
      wake.e.setKeepAlive(true);
      clock.flushMicrotasks();
      held.emitCompleted(true);
      clock.flushMicrotasks();
      expect(wake.e.state.keepAlivePhase, MovaKeepAlivePhase.fallback);
      wake.e.setKeepAlive(false);
      clock.flushMicrotasks();
      expect(held.lastUri, _q.uri);
      expect(wake.e.state.currentQuality, _q);
      expect(wake.e.state.timeshiftBehind, isNull);
      expect(wake.e.state.duration, const Duration(minutes: 5));
      wake.oneSession();
      wake.close();
    });
  });

  test('A10 pause during non keepAlive live edge prevents late playback', () {
    fakeAsync((clock) {
      final r = _Rig(clock, live: const MovaLiveConfig(backToLive: MovaBackToLive.reopen))
        ..open(live: true)..quality(_q);
      final gate = r.k.openGate = Completer<void>();
      r.e.backToLiveEdge();
      clock.flushMicrotasks();
      r.e.pause();
      clock.flushMicrotasks();
      final plays = r.k.calls.where((v) => v == 'play').length;
      gate.complete();
      clock.flushMicrotasks();
      expect(r.k.lastUri, _q.uri);
      expect(r.k.calls.where((v) => v == 'play').length, plays);
      expect(r.k.calls.last, 'pause');
      // 另一次重开被新会话取代后，不得替新会话发布回边缘事件。
      final obsolete = r.k.openGate = Completer<void>();
      r.e.backToLiveEdge();
      clock.flushMicrotasks();
      r.k.openGate = null;
      r.e.open(const MovaSource('https://h/new.mp4'));
      clock.flushMicrotasks();
      final edges = r.events.whereType<MovaLiveEdgeReach>().length;
      obsolete.complete();
      clock.flushMicrotasks();
      expect(r.events.whereType<MovaLiveEdgeReach>().length, edges);
      expect(r.k.lastUri, 'https://h/new.mp4');
      r.close();
    });
  });

  test('A10 overlapping quality loads inherit previous unlanded target', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open()..position();
      final first = r.k.openGate = Completer<void>();
      r.quality(_q);
      final second = r.k.openGate = Completer<void>();
      r.quality(_q2);
      second.complete();
      clock.flushMicrotasks();
      expect(r.e.debugCurrentLoad!.resumeAt, const Duration(seconds: 42));
      expect(r.log.entries.single.verb, _q2.label);
      first.complete();
      clock.flushMicrotasks();
      r.land();
      expect(r.k.lastSeek, const Duration(seconds: 42));
      expect(r.e.state.currentQuality, _q2);
      r.oneSession();
      r.close();
    });
  });

  test('A10 second quality prefers the user parked target over prior spec', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open()..position();
      final first = r.k.openGate = Completer<void>();
      r.quality(_q);
      r.e.seek(const Duration(seconds: 80));
      clock.flushMicrotasks();
      r.k.openGate = null;
      r.quality(_q2);
      first.complete();
      clock.flushMicrotasks();
      r.land();
      expect(r.k.lastSeek, const Duration(seconds: 80));
      expect(r.e.debugCurrentLoad!.resumeAt, const Duration(seconds: 80));
      r.close();
    });
  });

  test('A10 late failure of first quality does not lose second resume position', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open()..position();
      final first = r.k.openGate = Completer<void>();
      r.quality(_q);
      r.k.openGate = null;
      r.quality(_q2);
      r.k.openError = StateError('first load failed late');
      first.complete();
      clock.flushMicrotasks();
      r.k.openError = null;
      r.land();
      expect(r.k.lastSeek, const Duration(seconds: 42));
      expect(r.e.state.currentQuality, _q2);
      expect(r.events.whereType<MovaPlayFailure>(), isEmpty);
      r.close();
    });
  });

  test('A10 user seek during recovery network replaces failure resume point', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open()..position();
      final gate = r.k.openGate = Completer<void>();
      r.fail();
      r.e.seek(const Duration(seconds: 80));
      clock.flushMicrotasks();
      gate.complete();
      clock.flushMicrotasks();
      r.land();
      expect(r.k.lastSeek, const Duration(seconds: 80));
      expect(r.e.progressValue.position, const Duration(seconds: 80));
      r.oneSession();
      r.close();
    });
  });

  test('A10 public reload stays a new open resetting duration and reprobes qualities', () {
    fakeAsync((clock) {
      final r = _Rig(clock)..open()..position()..quality(_q)..land();
      r.e.reload();
      clock.flushMicrotasks();
      expect(r.k.lastUri, 'https://h/master.m3u8');
      expect(r.e.debugCurrentLoad!.reason, LoadReason.open);
      expect(r.e.state.currentQuality!.isAuto, isTrue);
      expect(r.e.state.qualities, hasLength(3));
      expect(r.e.state.duration, Duration.zero);
      expect(r.e.progressValue.position, Duration.zero);
      expect(r.events.whereType<MovaSourceChange>(), hasLength(2));
      expect(r.events.whereType<MovaReady>(), hasLength(2));
      r.close();
    });
  });
}
