import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/ads.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/cutover/plan.dart';
import 'package:mova/src/core/cutover/trigger.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';

import '../support/fake_api.dart';
import 'cutover/cutover_operation_test.dart' show settleOperations;

/// 记录广告失败裁决；可要求重试以确认拒绝路径不会调用策略。
class RecordingAdPolicy implements MovaAdFailPolicy {
  /// 创建返回 [action] 的记录策略。
  RecordingAdPolicy([this.action = MovaAdFailAction.skipBreak]);

  /// 每次失败的裁决。
  final MovaAdFailAction action;

  /// 策略实际收到的失败。
  final List<MovaAdFail> failures = [];

  /// 记录 [failure] 并返回固定裁决。
  @override
  MovaAdFailAction onFailure(MovaAdFail failure) {
    failures.add(failure);
    return action;
  }
}

/// 在指定广告切换动词上只抛一次，覆盖调用方的异常汇流。
class ThrowingAdCutover extends FakeCutoverCtl {
  /// [stage] 选择 prepare、commit 或 cutoverTo。
  ThrowingAdCutover(this.stage);

  /// 被注入异常的动词。
  final String stage;

  /// 是否已启用异常注入。
  bool armed = false;

  /// 剩余异常次数，首次抛出后允许重试成功。
  int remaining = 1;

  /// 在目标动词首次进入时抛出固定异常。
  void _maybeThrow(String verb) {
    if (armed && verb == stage && remaining > 0) {
      remaining--;
      throw StateError('ad $verb failed');
    }
  }

  /// 按 [stage] 注入预热异常，否则保留父类记录与门控。
  @override
  Future<void> prepare(
    MovaSource source, {
    Duration at = Duration.zero,
    MovaWarmCue cue = const MovaWarmCue(),
    MovaWarmPlan plan = const MovaWarmPlan(),
  }) async {
    _maybeThrow('prepare');
    await super.prepare(source, at: at, cue: cue, plan: plan);
  }

  /// 按 [stage] 注入提交异常，否则返回父类结果。
  @override
  Future<bool> commit({bool waitForReady = false}) async {
    _maybeThrow('commit');
    return super.commit(waitForReady: waitForReady);
  }

  /// 按 [stage] 注入一次性切换异常，保留调用次数用于重试断言。
  @override
  Future<bool> cutoverTo(MovaSource source, {Duration at = Duration.zero, double? rate}) async {
    calls.add('cutoverTo');
    _maybeThrow('cutoverTo');
    return false;
  }
}

/// 广告打开、拒绝与正片打开异常的契约回归。
void main() {
  const content = MovaSource('https://host/content.mp4');
  const next = MovaSource('https://host/next.mp4');
  const mid = MovaAdBreak(
    kind: MovaAdBreakKind.mid,
    source: MovaSource('https://host/mid.mp4'),
    offset: Duration(seconds: 1),
  );

  test('广告 cutoverTo/prepare/commit 异常均交给失败策略并回正片', () async {
    for (final stage in ['cutoverTo', 'prepare', 'commit']) {
      final policy = RecordingAdPolicy();
      final cutover = ThrowingAdCutover(stage);
      final ad = MovaAdBreak(
        kind: stage == 'cutoverTo' ? MovaAdBreakKind.pre : MovaAdBreakKind.mid,
        source: const MovaSource('https://host/ad.mp4'),
        waitForReady: true,
        offset: const Duration(seconds: 1),
      );
      final api = FakeMovaApi(
        options: MovaOpts(
          ads: MovaAdConfig(enabled: true, breaks: [ad], failPolicy: policy),
        ),
      );
      final ads = MovaAds(api, cutover: cutover);
      if (stage == 'cutoverTo') cutover.armed = true;
      await ads.load(content);
      if (stage != 'cutoverTo') {
        cutover.armed = true;
        api.pushProgress(const MovaProg(position: Duration(seconds: 2)));
      }
      await settleOperations();
      expect(policy.failures, hasLength(1), reason: stage);
      expect(policy.failures.single.kind, MovaAdFailKind.openThrew);
      expect(api.source, same(content));
      expect(ads.isShowingAd, isFalse);
      expect(ads.isAdPending, isFalse);
      await ads.dispose();
      await api.dispose();
      await cutover.dispose();
    }
  });

  test('一次性切换异常遵守 retry 策略，随后成功进入广告', () async {
    final policy = RecordingAdPolicy(MovaAdFailAction.retry);
    final cutover = ThrowingAdCutover('cutoverTo')..armed = true;
    const ad = MovaAdBreak(
      kind: MovaAdBreakKind.pre,
      source: MovaSource('https://host/ad.mp4'),
      waitForReady: true,
    );
    final api = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdConfig(enabled: true, breaks: const [ad], failPolicy: policy),
      ),
    );
    final ads = MovaAds(api, cutover: cutover);
    await ads.load(content);
    expect(policy.failures, hasLength(1));
    expect(cutover.calls.where((call) => call == 'cutoverTo'), hasLength(2));
    expect(ads.currentBreak, same(ad));
    expect(ads.isShowingAd, isTrue);
    await ads.dispose();
    await api.dispose();
    await cutover.dispose();
  });

  test('广告 open 被宿主拒绝时跳过，即使失败策略要求 retry 也不重试', () async {
    final policy = RecordingAdPolicy(MovaAdFailAction.retry);
    final events = <MovaAdEvent>[];
    const ad = MovaAdBreak(kind: MovaAdBreakKind.pre, source: MovaSource('https://host/ad.mp4'));
    late FakeMovaApi api;
    api = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdConfig(
          enabled: true,
          breaks: const [ad],
          failPolicy: policy,
          onAdEvent: (event) {
            events.add(event);
            // 仅拒绝广告，随后允许正片打开。
            if (event.type == MovaAdEventType.failed) api.acceptOpens = true;
          },
        ),
      ),
    )..acceptOpens = false;
    final ads = MovaAds(api);
    await ads.load(content);
    expect(policy.failures, isEmpty);
    expect(api.openCalls, 2, reason: '广告被拒后仅打开一次正片，广告没有重试');
    expect(api.source, same(content));
    expect(events.where((e) => e.type == MovaAdEventType.failed), hasLength(1));
    expect(ads.isShowingAd, isFalse);
    await ads.dispose();
    await api.dispose();
  });

  test('正片 open 抛出经 contentError 上报并 idle，不触发后续中插或 contentEnded', () async {
    final boom = StateError('content failed');
    final api = FakeMovaApi(
      options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [mid])),
    )..openThrows = boom;
    final ads = MovaAds(api);
    final errors = <Object>[];
    var ended = 0;
    final sub = ads.contentError.listen(errors.add);
    final endSub = ads.contentEnded.listen((_) => ended++);
    await ads.load(content);
    await settleOperations();
    expect(errors, [same(boom)]);
    api.pushProgress(const MovaProg(position: Duration(seconds: 20)));
    await settleOperations();
    expect(api.openCalls, 1);
    expect(ended, 0);
    await sub.cancel();
    await endSub.cancel();
    await ads.dispose();
    await api.dispose();
  });

  test('正片被宿主拒绝不报错且进入 idle', () async {
    final api = FakeMovaApi(
      options: const MovaOpts(ads: MovaAdConfig(enabled: true, breaks: [mid])),
    )..acceptOpens = false;
    final ads = MovaAds(api);
    final errors = <Object>[];
    final sub = ads.contentError.listen(errors.add);
    await ads.load(content);
    api.pushProgress(const MovaProg(position: Duration(seconds: 20)));
    await settleOperations();
    expect(errors, isEmpty);
    expect(api.openCalls, 1);
    expect(ads.isAdPending, isFalse);
    await sub.cancel();
    await ads.dispose();
    await api.dispose();
  });

  test('旧正片 open 迟到异常不发 contentError，也不把新正片变回 idle', () async {
    final gate = Completer<void>();
    final api = FakeMovaApi()
      ..openGate = gate
      ..openThrows = StateError('old content failed')
      ..openThrowsFor = content.uri;
    final ads = MovaAds(api);
    final errors = <Object>[];
    final sub = ads.contentError.listen(errors.add);
    final loading = ads.load(content);
    await settleOperations();
    api.openGate = null;
    await ads.load(next);
    gate.complete();
    await loading;
    await settleOperations();
    expect(errors, isEmpty);
    expect(api.source, same(next));
    await ads.playAdNow(mid);
    expect(ads.isShowingAd, isTrue, reason: "旧异常未把新正片变回 idle");
    await sub.cancel();
    await ads.dispose();
    await api.dispose();
  });
}
