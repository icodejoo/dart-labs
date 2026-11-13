import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/report/collector.dart';
import 'package:mova/src/core/report/translator.dart';

import '../../support/fake_api.dart';
import '../../support/fake_kernel.dart';

/// 加载门闩与真实加载状态的采样替身。
class _LoadingKernel extends FakeKernel with StatsProbeStub {
  /// 放行内核加载。
  final loaded = Completer<void>();

  /// 等待加载门闩后记录打开。
  @override
  Future<void> open(String uri, {bool play = true}) async {
    await loaded.future;
    await super.open(uri, play: play);
  }

  /// 采样时把加载状态作为媒体信息返回。
  @override
  Future<MovaStatsSnapshot?> sample() async =>
      MovaStatsSnapshot(fileFormat: loaded.isCompleted ? 'loaded' : 'stale');
}

/// 可挂起单次采样的探针，重现跨会话返回。
class _GatedProbe extends FakeStatsProbe {
  /// 下一次采样的门闩，未设置时沿用替身默认行为。
  Completer<MovaStatsSnapshot?>? gate;

  /// 消费单次门闩并返回采样结果。
  @override
  Future<MovaStatsSnapshot?> sample() {
    final pending = gate;
    gate = null;
    return pending?.future ?? super.sample();
  }
}

/// 收集器测试环境，使用可控时钟和同步事件流。
class _Rig {
  /// 创建测试环境，可选注入探针。
  _Rig({this.probe}) {
    collector = MovaQoeCollector(
      events: events.stream,
      reporter: MovaCallbackReporter(reports.add),
      opts: const MovaReportOpts(qoe: true, heartbeat: Duration(seconds: 1)),
      probe: probe,
      now: () => clock,
    );
    open();
  }

  /// 可选探针。
  final _GatedProbe? probe;

  /// 同步事件输入。
  final events = StreamController<MovaEvent>.broadcast(sync: true);

  /// 已收到的报告。
  final reports = <MovaReportEvent>[];

  /// 当前测试时间。
  DateTime clock = DateTime.utc(2026);

  /// 被测收集器。
  late final MovaQoeCollector collector;

  /// 开始一次独立会话。
  void open() => collector.onOpen(const MovaSource('https://host/a.mp4'), autoPlay: true);

  /// 落地首帧并开始累计观看。
  void land() {
    events.add(const MovaPlay());
    collector.onPosition(const Duration(milliseconds: 100));
    collector.onPosition(const Duration(milliseconds: 200));
  }

  /// 释放测试资源。
  Future<void> close() async {
    await collector.cancel();
    await events.close();
    await probe?.dispose();
  }
}

/// B05 的会话、计时与恢复回归。
void main() {
  test('恒速播放心跳在快照前结算观看时长', () {
    fakeAsync((async) {
      final r = _Rig()..land();
      r.clock = r.clock.add(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
      r.clock = r.clock.add(const Duration(seconds: 1));
      async.elapse(const Duration(seconds: 1));
      final beats = r.reports.where((e) => e.name == MovaReportName.heartbeat).toList();
      expect(beats.map((e) => e.params['watchedMs']), [1000, 2000]);
      unawaited(r.close());
    });
  });

  test('404 后恢复清除 fatal 和原生错误结束标记', () async {
    final p = _GatedProbe();
    final r = _Rig(probe: p)..land();
    p.pushEndFile(MovaEndFileReason.error);
    r.events.add(const MovaErrorEvent('HTTP error 404 Not Found'));
    await Future<void>.delayed(Duration.zero);
    r.events.add(const MovaRecovered(1));
    r.collector.onTeardown();
    expect(r.reports.last.params['reason'], 'stopped');
    await r.close();
  });

  test('旧会话心跳的迟到采样不发出', () {
    fakeAsync((async) {
      final p = _GatedProbe();
      final r = _Rig(probe: p)..land();
      async.flushMicrotasks();
      final gate = Completer<MovaStatsSnapshot?>();
      p.gate = gate;
      async.elapse(const Duration(seconds: 1));
      r.collector.onTeardown();
      r.open();
      gate.complete(const MovaStatsSnapshot(videoBps: 999));
      async.flushMicrotasks();
      expect(r.reports.where((e) => e.name == MovaReportName.heartbeat), isEmpty);
      unawaited(r.close());
    });
  });

  test('旧会话换档采样不污染新会话码率基线', () async {
    final p = _GatedProbe();
    final r = _Rig(probe: p);
    final gate = Completer<MovaStatsSnapshot?>();
    p.gate = gate;
    r.events.add(const MovaQualityChange(MovaQuality(label: 'A', uri: 'https://a')));
    r.collector.onTeardown();
    r.open();
    gate.complete(const MovaStatsSnapshot(videoBps: 999));
    await Future<void>.delayed(Duration.zero);
    p.sampleResult = const MovaStatsSnapshot(videoBps: 100);
    r.events.add(const MovaQualityChange(MovaQuality(label: 'B', uri: 'https://b')));
    await Future<void>.delayed(Duration.zero);
    final q = r.reports.where((e) => e.name == MovaReportName.qualityChange).toList();
    expect(q, hasLength(1));
    expect(q.single.params.containsKey('fromBps'), isFalse);
    expect(q.single.params['toBps'], 100);
    await r.close();
  });

  test('新会话清除已完成采样的码率基线', () async {
    final p = _GatedProbe()..sampleResult = const MovaStatsSnapshot(videoBps: 999);
    final r = _Rig(probe: p);
    r.events.add(const MovaQualityChange(MovaQuality(label: 'A', uri: 'https://a')));
    await Future<void>.delayed(Duration.zero);
    r.collector.onTeardown();
    r.open();
    r.events.add(const MovaQualityChange(MovaQuality(label: 'B', uri: 'https://b')));
    await Future<void>.delayed(Duration.zero);
    expect(r.reports.last.params.containsKey('fromBps'), isFalse);
    await r.close();
  });

  test('seek 缓冲不计 rebuffer，随后真实卡顿照常计数', () async {
    final r = _Rig()..land();
    r.events.add(const MovaSeek(Duration(seconds: 30)));
    r.events.add(const MovaBufferChange(true));
    r.clock = r.clock.add(const Duration(seconds: 2));
    r.events.add(const MovaSeeked(Duration(seconds: 30)));
    r.events.add(const MovaBufferChange(false));
    expect(r.reports.where((e) => e.name == MovaReportName.rebuffer), isEmpty);
    r.events.add(const MovaBufferChange(true));
    r.clock = r.clock.add(const Duration(seconds: 1));
    r.events.add(const MovaBufferChange(false));
    expect(r.reports.where((e) => e.name == MovaReportName.rebuffer), hasLength(1));
    await r.close();
  });

  test('sessionStart 延后至内核加载完成且只采样一次', () async {
    final k = _LoadingKernel();
    final reports = <MovaReportEvent>[];
    final e = createMova(
      kernel: k,
      pip: MovaNoopPip(),
      orient: MovaNoopOrient(),
      brightness: MovaFallbackBrightness(),
      reporter: MovaCallbackReporter(reports.add),
      options: const MovaOpts(report: MovaReportOpts(qoe: true)),
    );
    final opening = e.open(const MovaSource('https://host/a.mp4'));
    expect(reports.where((e) => e.name == MovaReportName.sessionStart), isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(reports.where((e) => e.name == MovaReportName.sessionStart), isEmpty);
    k.loaded.complete();
    await opening;
    await Future<void>.delayed(Duration.zero);
    expect(k.calls, contains('open'));
    expect(reports.singleWhere((e) => e.name == MovaReportName.sessionStart).params['fileFormat'], 'loaded');
    expect(reports.where((e) => e.name == MovaReportName.sessionStart), hasLength(1));
    await e.dispose();
  });

  test('重试决策上报动作及尝试次数', () {
    const fail = MovaPlayFail(
      kind: MovaPlayFailKind.openThrew,
      sourceIndex: 0,
      uri: 'https://a',
      sourceCount: 2,
      attempt: 2,
      streak: 2,
    );
    final report = translateMovaEvent(const MovaPlayFailure(fail, MovaRecoveryAction.retry))!;
    expect(report.name, MovaReportName.playFailure);
    expect(report.params, {'action': 'retry', 'kind': 'openThrew', 'attempt': 2, 'sourceIndex': 0});
  });

  test('备选地址切换上报前后下标', () {
    final report = translateMovaEvent(const MovaFailover(from: 0, to: 1, uri: 'https://b'))!;
    expect(report.name, MovaReportName.failover);
    expect(report.params, {'from': 0, 'to': 1});
  });

  test('恢复成功上报连续失败次数', () {
    final report = translateMovaEvent(const MovaRecovered(3))!;
    expect(report.name, MovaReportName.recovered);
    expect(report.params, {'attempts': 3});
  });
}
