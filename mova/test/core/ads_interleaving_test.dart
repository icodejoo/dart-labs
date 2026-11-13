import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ads.dart';
import 'package:mova/src/core/cutover/cutover.dart';
import 'package:mova/src/core/cutover/api.dart';
import 'package:mova/src/core/cutover/plan.dart';
import 'package:mova/src/core/cutover/trigger.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';

import '../support/fake_api.dart';
import '../support/gated.dart';
import 'cutover/cutover_operation_test.dart' show settleOperations;

/// 两集测试正片与可立即插播的广告。
const _a = MovaSource('https://host/A.mp4');

/// 换集后的新正片。
const _b = MovaSource('https://host/B.mp4');

/// 立即打断正片、无需等待预热的中插。
const _instant = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/ad.mp4'),
  waitForReady: false,
);

/// 真实切换代理与 MovaAds 共用 S01 门控工厂和命令日志。
class AdOperationRig {
  /// [breaks] 决定本例排期；[gateShadow] 门控下一次影子的 open。
  AdOperationRig({List<MovaAdBreak> breaks = const [], this.gateShadow}) {
    api = MovaCutover(
      movaFactory: () {
        final mova = FakeMovaApi(
          options: MovaOpts(
            cutover: const MovaCutoverOpts(enabled: true, trigger: MovaEagerWarm()),
            ads: MovaAdOpts(enabled: true, breaks: breaks, durationFromFirstFrame: false),
          ),
          commandLog: factory.log,
        );
        if (factory.movas.isNotEmpty) mova.openGate = gateShadow;
        factory.movas.add(mova);
        return mova;
      },
    );
    ads = MovaAds(api, cutover: api);
  }

  /// S01 播放器记录与跨实例日志。
  final GatedMovaFactory factory = GatedMovaFactory();

  /// 后续影子的可选门闩。
  Completer<void>? gateShadow;

  /// 被测切换代理。
  late final MovaCutover api;

  /// 被测广告编排。
  late final MovaAds ads;

  /// 已创建的全部底层播放器。
  List<FakeMovaApi> get movas => factory.movas;

  /// 推两次有效缓冲信号，达到真实就绪判据。
  Future<void> ready(FakeMovaApi shadow) async {
    const tick = MovaProg(position: Duration(seconds: 1), buffer: Duration(seconds: 10));
    shadow.pushProgress(tick);
    await settleOperations();
    shadow.pushProgress(tick);
    await settleOperations();
  }

  /// 让当前广告触发正片预热，并返回实际影子。
  Future<FakeMovaApi> warmContent({bool readyNow = true}) async {
    await ads.playAdNow(_instant);
    movas.first.pushProgress(const MovaProg(position: Duration(milliseconds: 100)));
    await settleOperations();
    final shadow = movas.last;
    expect(shadow, isNot(same(movas.first)));
    if (readyNow) await ready(shadow);
    return shadow;
  }

  /// 先释放编排订阅与计时器，再释放代理拥有的播放器。
  Future<void> dispose() async {
    await ads.dispose();
    await api.dispose();
    await settleOperations();
  }
}

/// P0-2 三种触发与广告异步返回的加载代际隔离。
void main() {
  test('F-N 首次等待型前贴片把显式起播意图传给真实切换代理', () async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
      waitForReady: true,
      duration: Duration(seconds: 10),
    );
    final rig = AdOperationRig(breaks: [pre]);
    addTearDown(rig.dispose);
    expect(rig.api.state.playbackIntent, isFalse);
    final loading = rig.ads.load(_a);
    await settleOperations();
    final shadow = rig.movas.last;
    await rig.ready(shadow);
    await loading;
    expect(rig.api.active, same(shadow));
    expect(shadow.calls, contains('play'));
    expect(shadow.calls, containsAllInOrder(['pause', 'seek', 'play']));
    expect(shadow.state.playbackIntent, isTrue);
    expect(rig.ads.isShowingAd, isTrue);
  });

  test('F-N 等待型前贴片的显式起播让位于等待期间的用户暂停', () async {
    const pre = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/pre.mp4'),
      waitForReady: true,
    );
    final rig = AdOperationRig(breaks: [pre]);
    addTearDown(rig.dispose);
    final loading = rig.ads.load(_a);
    await settleOperations();
    final shadow = rig.movas.last;
    await rig.api.pause();
    await rig.ready(shadow);
    await loading;
    expect(rig.api.active, same(shadow));
    expect(shadow.calls, isNot(contains('play')));
    expect(shadow.state.playbackIntent, isFalse);
  });

  for (final readyNow in [false, true]) {
    test('正片预热${readyNow ? 'ready' : 'warming'}时 load B 不提交 A', () async {
      final rig = AdOperationRig();
      addTearDown(rig.dispose);
      await rig.ads.load(_a);
      final shadow = await rig.warmContent(readyNow: readyNow);
      await rig.ads.load(_b);
      await settleOperations();
      expect(rig.movas.first.source, same(_b));
      expect(rig.api.active, same(rig.movas.first));
      expect(shadow.disposeCount, 1);
      expect(rig.ads.isShowingAd, isFalse);
    });
  }

  test('正片影子 open 挂起时换集，迟到预热不再占槽', () async {
    final gate = Completer<void>();
    final rig = AdOperationRig(gateShadow: gate);
    addTearDown(rig.dispose);
    await rig.ads.load(_a);
    final shadow = await rig.warmContent(readyNow: false);
    await rig.ads.load(_b);
    gate.complete();
    await settleOperations();
    expect(shadow.disposeCount, 1);
    expect(rig.api.cutoverPhase, MovaCutoverPhase.idle);
    expect(rig.movas.first.source, same(_b));
  });

  test('中插倒计时 pending 的 ready 广告影子不会被 B 当正片提交', () async {
    const ad = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/pending.mp4'),
      offset: Duration(seconds: 1),
      delay: Duration(hours: 1),
    );
    final rig = AdOperationRig(breaks: [ad]);
    addTearDown(rig.dispose);
    await rig.ads.load(_a);
    rig.movas.first.pushProgress(const MovaProg(position: Duration(seconds: 2)));
    await settleOperations();
    rig.movas.first.pushProgress(const MovaProg(position: Duration(seconds: 3)));
    await settleOperations();
    final shadow = rig.movas.last;
    await rig.ready(shadow);
    expect(rig.ads.isAdPending, isTrue);
    await rig.ads.load(_b);
    await settleOperations();
    expect(rig.movas.first.source, same(_b));
    expect(rig.ads.isAdPending, isFalse);
    expect(shadow.disposeCount, 1);
  });

  test('中插 pending 等待 commit 时 load B，不回落硬切旧广告', () async {
    const ad = MovaAdBreak(
      kind: MovaAdBreakKind.mid,
      source: MovaSource('https://host/pending.mp4'),
      offset: Duration(seconds: 1),
    );
    final rig = AdOperationRig(breaks: [ad]);
    addTearDown(rig.dispose);
    await rig.ads.load(_a);
    rig.movas.first.pushProgress(const MovaProg(position: Duration(seconds: 2)));
    await settleOperations();
    final shadow = rig.movas.last;
    expect(rig.ads.isAdPending, isTrue);
    await rig.ads.load(_b);
    await settleOperations();
    expect(rig.movas.first.source, same(_b));
    expect(rig.movas.first.openedUris, [_a.uri, _b.uri]);
    expect(shadow.disposeCount, 1);
  });

  for (final residual in [false, true]) {
    test('后贴片结束再 load B：${residual ? 'idle 清理额外影子' : '后贴片不预热正片'}', () async {
      const post = MovaAdBreak(
        kind: MovaAdBreakKind.post,
        source: MovaSource('https://host/post.mp4'),
      );
      final rig = AdOperationRig(breaks: [post]);
      addTearDown(rig.dispose);
      await rig.ads.load(_a);
      rig.movas.first.emitDone();
      await settleOperations();
      expect(rig.ads.currentBreak, same(post));
      rig.movas.first.pushProgress(const MovaProg(position: Duration(seconds: 1)));
      await settleOperations();
      expect(rig.movas, hasLength(1), reason: '后贴片之后没有正片，不应创建正片影子');
      FakeMovaApi? extra;
      if (residual) {
        await rig.api.prepare(_a, plan: const MovaWarmPlan(trigger: MovaEagerWarm()));
        extra = rig.movas.last;
      }
      rig.movas.first.emitDone();
      await settleOperations();
      expect(rig.api.cutoverPhase, MovaCutoverPhase.idle);
      if (extra != null) expect(extra.disposeCount, 1);
      await rig.ads.load(_b);
      expect(rig.movas.first.source, same(_b));
    });
  }

  for (final disposing in [false, true]) {
    test('一次性广告切换 open 挂起时${disposing ? '销毁' : '换集'}不复活旧广告', () async {
      final gate = Completer<void>();
      final rig = AdOperationRig(gateShadow: gate);
      await rig.ads.load(_a);
      const ad = MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: MovaSource('https://host/oneshot.mp4'),
        waitForReady: true,
        duration: Duration(milliseconds: 1),
      );
      final playing = rig.ads.playAdNow(ad);
      await settleOperations();
      final shadow = rig.movas.last;
      if (disposing) {
        await rig.ads.dispose();
      } else {
        await rig.ads.load(_b);
      }
      await rig.api.setRate(2);
      rig.movas.first.push(rig.movas.first.state.copyWith(rate: 2));
      await settleOperations();
      gate.complete();
      await playing;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(shadow.disposeCount, 1);
      expect(rig.movas.first.lastRate, 2, reason: '迟到广告操作不得把新倍速复位为 1');
      if (!disposing) {
        expect(rig.movas.first.openedUris, [_a.uri, _b.uri]);
        expect(rig.ads.isShowingAd, isFalse);
        await rig.ads.dispose();
      }
      await rig.api.dispose();
    });
  }

  test('回正片 commit 暂停中换集，不恢复旧正片及倍速', () async {
    final rig = AdOperationRig();
    addTearDown(rig.dispose);
    await rig.ads.load(_a);
    await rig.api.setRate(2);
    final shadow = await rig.warmContent();
    final active = rig.movas.first;
    active.pauseGate = Completer<void>();
    active.emitDone();
    await settleOperations();
    await rig.ads.load(_b);
    active.pauseGate!.complete();
    await settleOperations();
    expect(shadow.disposeCount, 1);
    expect(active.openedUris.last, _b.uri);
    expect(active.openedUris.where((uri) => uri == _a.uri), hasLength(1));
  });
}
