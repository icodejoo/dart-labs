import 'package:mova/mova.dart' show MovaRecoveryOpts, MovaPlayFailure, MovaPlayFail, MovaPlayFailKind, MovaRecoveryAction, MovaErrorEvent;
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ads.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/cutover/cutover.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';

import '../support/fake_api.dart';
import '../support/gated.dart';
import 'ads_open_failure_test.dart' show RecordingAdPolicy;
import 'cutover/cutover_operation_test.dart' show settleOperations;

/// 测试正片，保持 rendered 状态以暴露拒绝后误认旧画面的错误。
const _content = MovaSource('https://host/content.mp4');

/// 验证 content 与 idle 相位的即时插播探针。
const _probe = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/probe.mp4'),
  waitForReady: false,
);

/// 用真实 cutover 和共享门控日志执行 pod，不替换广告控制逻辑。
class PodFailureRig {
  /// 第二条广告注入 [fault]，其余广告按真实编排推进。
  PodFailureRig({
    this.kind = MovaAdBreakKind.pre,
    this.fault = 'reject',
    MovaAdFailAction action = MovaAdFailAction.skipBreak,
    this.contentUnavailable = false,
    bool third = true,
    Duration? firstDuration,
  }) : policy = RecordingAdPolicy(action) {
    breaks = [
      for (var i = 1; i <= (third ? 3 : 2); i++)
        MovaAdBreak(
          kind: kind,
          source: MovaSource('https://host/ad$i.mp4'),
          offset: const Duration(seconds: 1),
          waitForReady: i == 2 && ['cutoverThrow', 'warmReject', 'fallbackReject'].contains(fault),
          duration: i == 1 ? firstDuration : null,
        ),
    ];
    api = MovaCutover(
      movaFactory: () {
        final mova = PodFaultApi(
          this,
          options: MovaOpts(
            cutover: const MovaCutoverOpts(enabled: true, readyTimeout: Duration(hours: 1)),
            recovery: MovaRecoveryOpts(enabled: fault == 'giveUpReturn'),
            ads: MovaAdOpts(
              enabled: true,
              breaks: breaks,
              failPolicy: policy,
              durationFromFirstFrame: false,
              onAdEvent: events.add,
            ),
          ),
          commandLog: factory.log,
        );
        factory.movas.add(mova);
        return mova;
      },
    );
    ads = MovaAds(api, cutover: api);
    endSub = ads.contentEnded.listen((_) => ended++);
  }

  /// 本例的广告类型。
  final MovaAdBreakKind kind;

  /// 注入的故障名称。
  final String fault;

  /// 回正片时由宿主拒绝，用来验证可到达 idle。
  final bool contentUnavailable;

  /// 失败策略记录。
  final RecordingAdPolicy policy;

  /// 广告生命周期记录。
  final List<MovaAdEvent> events = [];

  /// 共享日志与底层播放器集合。
  final GatedMovaFactory factory = GatedMovaFactory();

  /// 每次真实进入 open 的源，包含被拒和抛错的调用。
  final List<String> opens = [];

  /// 本例 pod 的广告位。
  late final List<MovaAdBreak> breaks;

  /// 被测的真实切换代理。
  late final MovaCutover api;

  /// 被测的广告编排对象（MovaAds）。
  late final MovaAds ads;

  /// 正片结束计数订阅。
  late final StreamSubscription<void> endSub;

  /// 正片结束事件的实际次数。
  int ended = 0;

  /// 第二条广告的打开次数，用于重复失败与重试隔离。
  int secondOpens = 0;

  /// 第一次错误在抛出前的门闩。
  final Completer<void> firstErrorGate = Completer<void>();

  /// 第二次尝试打开门闩，确保迟到错误不会打断它。
  final Completer<void> retryGate = Completer<void>();

  /// 第二条广告是否已被调度。
  bool get secondStarted =>
      events.any((e) => e.type == MovaAdEventType.started && identical(e.adBreak, breaks[1]));

  /// 当前生效的底层门控播放器。
  PodFaultApi get active => api.active as PodFaultApi;

  /// 只给影子发送就绪信号，不把广告进度伪装成正片进度。
  Future<void> drain() async {
    for (var i = 0; i < 8; i++) {
      await settleOperations();
      for (final mova in factory.movas.toList()) {
        if (!mova.disposed && !identical(mova, api.active)) {
          mova.pushProgress(
            const MovaProg(position: Duration(seconds: 1), buffer: Duration(seconds: 10)),
          );
        }
      }
    }
    await settleOperations();
  }

  /// 加载并触发前、中、后对应 pod 的第一条广告。
  Future<void> start() async {
    await ads.load(_content);
    await settleOperations();
    if (kind == MovaAdBreakKind.mid) {
      active.pushProgress(const MovaProg(position: Duration(seconds: 2)));
    } else if (kind == MovaAdBreakKind.post) {
      active.emitDone();
    }
    await drain();
    expect(ads.currentBreak, same(breaks.first));
  }

  /// 清理门闩、MovaAds、代理和所有流。
  Future<void> dispose() async {
    if (!firstErrorGate.isCompleted) firstErrorGate.complete();
    if (!retryGate.isCompleted) retryGate.complete();
    for (final mova in factory.movas) {
      final gate = mova.openGate;
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await drain();
    await endSub.cancel();
    await ads.dispose();
    await api.dispose();
  }
}

/// 仅在底层媒体动词注入故障；保留真实代理的所有换指与订阅行为。
class PodFaultApi extends FakeMovaApi {
  /// 关联本次 pod 并复用 S01 命令日志与门闩。
  PodFaultApi(this.rig, {super.options, super.commandLog}) {
    pushPlayingOnVerbs = true;
  }

  /// 本例的故障与记录。
  final PodFailureRig rig;

  /// 对第二条广告按源注入拒绝、抛错或事件与抛错交错。
  @override
  Future<bool> open(MovaSource source, {bool autoPlay = true}) async {
    rig.opens.add(source.uri);
    final second = source.uri == rig.breaks[1].source.uri;
    final shadow = !identical(this, rig.factory.movas.first);
    if (second) {
      rig.secondOpens++;
      if (rig.fault == 'giveUpReturn') {
        if (rig.secondOpens == 1) {
          pushEvent(MovaPlayFailure(MovaPlayFail(
            kind: MovaPlayFailKind.openThrew, sourceIndex: 0,
            uri: source.uri, sourceCount: 1, attempt: 1, streak: 1,
            error: 'giveUp before open returns',
          ), MovaRecoveryAction.giveUp));
          pushEvent(MovaErrorEvent.classified('duplicate fatal', fatal: true, source: source));
          await rig.firstErrorGate.future;
          return true;
        }
        await rig.retryGate.future;
      }
      if (rig.fault == 'eventAndThrow') {
        if (rig.secondOpens == 1) {
          emitError(StateError('event failed'));
          await rig.firstErrorGate.future;
          throw StateError('same attempt threw');
        }
        await rig.retryGate.future;
      }
      acceptOpens =
          !['reject', 'warmReject'].contains(rig.fault) &&
          !(rig.fault == 'fallbackReject' && !shadow);
      openThrows = rig.fault == 'openThrow' || (rig.fault == 'fallbackReject' && shadow)
          ? StateError('open failed')
          : null;
    } else {
      acceptOpens = !(source.sameAs(_content) && rig.contentUnavailable && rig.secondStarted);
      openThrows = null;
    }
    final accepted = await super.open(source, autoPlay: autoPlay);
    if (accepted) push(state.copyWith(rendered: true, playing: autoPlay));
    return accepted;
  }

  /// 在影子 ready 之后让真实 cutoverTo 的提交抛错。
  @override
  Future<void> play() async {
    if (rig.fault == 'cutoverThrow' && source?.uri == rig.breaks[1].source.uri) {
      throw StateError('cutover play failed');
    }
    await super.play();
  }
}

/// 按源拒绝广告，模拟真实宿主 beforeOpen，其他源仍可打开。
class HostRefusalApi extends FakeMovaApi {
  /// 复用测试配置。
  HostRefusalApi({super.options});

  /// 只拒绝测试广告源，保留真实异步门闩。
  @override
  Future<bool> open(MovaSource source, {bool autoPlay = true}) async {
    acceptOpens = !source.uri.endsWith('/rejected.mp4');
    return super.open(source, autoPlay: autoPlay);
  }
}

/// 覆盖真实 cutover 下的 pod 同步失败、拒绝与单次尝试结算。
void main() {
  for (final kind in MovaAdBreakKind.values) {
    for (final fault in ['reject', 'openThrow', 'cutoverThrow']) {
      for (final action in [MovaAdFailAction.skipBreak, MovaAdFailAction.abandonPod]) {
        for (final unavailable in kind == MovaAdBreakKind.post ? [false] : [false, true]) {
          test('F2 $kind pod 第二条 $fault / $action / 正片不可用=$unavailable 继续推进', () async {
            final rig = PodFailureRig(
              kind: kind,
              fault: fault,
              action: action,
              contentUnavailable: unavailable,
            );
            addTearDown(rig.dispose);
            await rig.start();
            rig.active.emitDone();
            await rig.drain();
            final continuesPod = fault == 'reject' || action == MovaAdFailAction.skipBreak;
            if (continuesPod) {
              expect(rig.ads.currentBreak, same(rig.breaks[2]));
              rig.active.emitDone();
              await rig.drain();
            }
            expect(rig.ads.isShowingAd, isFalse);
            expect(rig.ads.isAdPending, isFalse);
            expect(rig.events.where((e) => e.type == MovaAdEventType.failed), hasLength(1));
            expect(rig.policy.failures, hasLength(fault == 'reject' ? 0 : 1));
            expect(rig.ended, kind == MovaAdBreakKind.post ? 1 : 0);
            if (kind != MovaAdBreakKind.post && !unavailable) {
              expect(rig.active.source, same(_content));
            }
            await rig.ads.playAdNow(_probe);
            expect(
              rig.ads.isShowingAd,
              kind != MovaAdBreakKind.post && !unavailable,
              reason: '即时插播只在 content 相位可用，验证正片或 idle 已真正到达',
            );
          });
        }
      }
    }
  }

  for (final kind in MovaAdBreakKind.values) {
    for (final fault in ['warmReject', 'fallbackReject']) {
      test('F4 $kind cutover $fault 拒绝不重试、不把旧正片认作广告', () async {
        final rig = PodFailureRig(
          kind: kind,
          fault: fault,
          action: MovaAdFailAction.retry,
          third: false,
        );
        addTearDown(rig.dispose);
        await rig.start();
        rig.active.emitDone();
        await rig.drain();
        expect(rig.ads.isShowingAd, isFalse);
        expect(rig.policy.failures, isEmpty);
        expect(rig.events.where((e) => e.type == MovaAdEventType.failed), hasLength(1));
        expect(
          rig.events.where(
            (e) => e.type == MovaAdEventType.completed && identical(e.adBreak, rig.breaks[1]),
          ),
          isEmpty,
        );
        expect(rig.secondOpens, fault == 'warmReject' ? 1 : 2);
        expect(rig.factory.movas.skip(1).every((e) => e.disposed), isTrue);
        if (kind != MovaAdBreakKind.post) expect(rig.active.source, same(_content));
        expect(rig.ended, kind == MovaAdBreakKind.post ? 1 : 0);
      });
    }
  }

  test('F4 pending 广告预热被拒立即跳过，不等 readyTimeout 或调用失败策略', () async {
    final rig = PodFailureRig(fault: 'warmReject', action: MovaAdFailAction.retry, third: false);
    addTearDown(rig.dispose);
    await rig.ads.load(_content);
    // 先结束未被拒的前贴片，再以即时中插触发 prepare/commit 路径。
    rig.active.emitDone();
    await rig.drain();
    final pending = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: rig.breaks[1].source,
      waitForReady: true,
    );
    final before = rig.secondOpens;
    await rig.ads.playAdNow(pending);
    await rig.drain();
    expect(rig.ads.isShowingAd, isFalse);
    expect(rig.ads.isAdPending, isFalse);
    expect(rig.secondOpens, before + 1);
    expect(rig.policy.failures, isEmpty);
    expect(rig.active.source, same(_content));
  });

  for (final fault in ['eventAndThrow', 'giveUpReturn']) {
  test('F5 $fault 落地窗口忽略旧 ErrorEvent，open 落定只结算一次后 retry', () async {
    final rig = PodFailureRig(fault: fault, action: MovaAdFailAction.retry, third: false);
    addTearDown(rig.dispose);
    await rig.start();
    rig.active.emitDone();
    await rig.drain();
    expect(rig.secondOpens, 1);
    expect(rig.policy.failures, isEmpty);
    rig.firstErrorGate.complete();
    await rig.drain();
    expect(rig.secondOpens, 2);
    expect(rig.policy.failures.map((e) => e.attempt), [1]);
    expect(rig.ads.currentBreak, same(rig.breaks[1]));
    rig.retryGate.complete();
    await rig.drain();
    expect(rig.ads.isShowingAd, isTrue);
    rig.active.emitDone();
    await rig.drain();
    expect(rig.active.source, same(_content));
    expect(rig.events.where((e) => e.type == MovaAdEventType.failed), hasLength(1));
  });

  for (final action in [MovaAdFailAction.skipBreak, MovaAdFailAction.abandonPod]) {
    test('F5 $fault $action 落地窗口旧错误不结算，open 落定后续播下一条或正片', () async {
      final rig = PodFailureRig(fault: fault, action: action);
      addTearDown(rig.dispose);
      await rig.start();
      rig.active.emitDone();
      await rig.drain();
      expect(rig.policy.failures, isEmpty);
      expect(rig.ads.currentBreak, same(rig.breaks[1]));
      rig.firstErrorGate.complete();
      await rig.drain();
      expect(rig.policy.failures, hasLength(1));
      expect(rig.events.where((e) => e.type == MovaAdEventType.failed), hasLength(1));
      if (action == MovaAdFailAction.skipBreak) {
        expect(rig.ads.currentBreak, same(rig.breaks[2]));
        rig.active.emitDone();
        await rig.drain();
      }
      expect(rig.ads.isShowingAd, isFalse);
      expect(rig.active.source, same(_content));
    });
  }

  }

  testWidgets('F4 旧正片仍 rendered 和出进度时不启动广告计时，影子拒绝立即回正片', (tester) async {
    const ad = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/rejected.mp4'),
      waitForReady: true,
      duration: Duration(seconds: 1),
    );
    final policy = RecordingAdPolicy(MovaAdFailAction.retry);
    final events = <MovaAdEvent>[];
    final movas = <HostRefusalApi>[];
    final gate = Completer<void>();
    final api = MovaCutover(
      movaFactory: () {
        final mova = HostRefusalApi(
          options: MovaOpts(
            cutover: const MovaCutoverOpts(enabled: true, readyTimeout: Duration(hours: 1)),
            ads: MovaAdOpts(
              enabled: true,
              breaks: const [ad],
              failPolicy: policy,
              onAdEvent: events.add,
            ),
          ),
        );
        if (movas.isNotEmpty) mova.openGate = gate;
        movas.add(mova);
        return mova;
      },
    );
    await api.open(_content);
    movas.first.push(movas.first.state.copyWith(rendered: true, playing: true));
    await tester.pump();
    final ads = MovaAds(api, cutover: api);
    final loading = ads.load(_content);
    await tester.pump();
    movas.first.pushProgress(const MovaProg(position: Duration(seconds: 5)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(
      events.where((e) => e.type == MovaAdEventType.completed),
      isEmpty,
      reason: '旧正片的 rendered 不能让未接受的广告起表',
    );
    expect(movas.first.source, same(_content));
    var settled = false;
    unawaited(loading.then((_) { settled = true; }));
    gate.complete();
    // 订阅取消与控制器 close 跨真实/fakeAsync 两个队列，按加载结算条件推进。
    // 上限只用于让真实挂起快速报错，不以固定 pump 轮数推断加载已完成。
    for (var turn = 0; !settled && turn < 20; turn++) {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(settled, isTrue, reason: '拒绝后正片已接受，加载必须结算');
    await loading;
    expect(ads.isShowingAd, isFalse);
    expect(policy.failures, isEmpty);
    expect(events.where((e) => e.type == MovaAdEventType.failed), hasLength(1));
    expect(movas.last.disposeCount, 1);
    expect(movas.last.openCalls, 1);
    expect(api.active, same(movas.first));
    expect(movas.first.source, same(_content));
    await tester.runAsync(() async {
      await ads.dispose();
      await api.dispose();
    });
  });

  testWidgets('F2 同一广告 Timer 与 MovaDone 只续播一次，下一条尚在 open 仍保留', (tester) async {
    final rig = PodFailureRig(
      fault: 'none',
      third: false,
      firstDuration: const Duration(seconds: 1),
    );
    // fakeAsync 中不用真实事件循环门控，逐次 pump 推进。
    final loading = rig.ads.load(_content);
    await tester.pump();
    await loading;
    final gate = rig.active.openGate = Completer<void>();
    await tester.pump(const Duration(seconds: 1));
    rig.active.emitDone();
    await tester.pump();
    expect(rig.secondOpens, 1);
    expect(rig.ads.currentBreak, same(rig.breaks[1]));
    gate.complete();
    await tester.pump();
    expect(rig.ads.currentBreak, same(rig.breaks[1]));
    expect(rig.opens.where((s) => s == _content.uri), isEmpty);
    rig.active.openGate = null;
    rig.active.emitDone();
    await tester.pump();
    expect(rig.opens.where((s) => s == _content.uri), hasLength(1));
    expect(
      rig.events.where(
        (e) => e.type == MovaAdEventType.completed && identical(e.adBreak, rig.breaks.first),
      ),
      hasLength(1),
    );
    await tester.runAsync(() async {
      await rig.endSub.cancel();
      await rig.ads.dispose();
      await rig.api.dispose();
    });
  });
}
