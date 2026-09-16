import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart' as barrel;
import 'package:mova/src/core/ad/ad_controller.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/state/progress.dart';
import 'package:mova/src/core/swap/plan.dart';
import 'package:mova/src/core/swap/trigger.dart';
import 'package:mova/src/core/swap/warm.dart';

import '../support/fake_api.dart';

const _content = MovaSource('https://host/content.m3u8');

const _mid = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/mid.mp4'),
  offset: Duration(seconds: 30),
);

/// Builds a fake api + controller over [breaks] with [ads] as the ad section.
///
/// 用 [ads] 作为广告配置节、基于 [breaks] 构造假 api + 控制器。
(FakeMovaApi, MovaAdCtrl) build(MovaAdConfig ads, {FakeSwapCtl? swap}) {
  final api = FakeMovaApi(options: MovaOpts(ads: ads));
  return (api, MovaAdCtrl(api, swap: swap));
}

/// Lets the controller's async chains settle inside a [fakeAsync] zone.
///
/// 在 [fakeAsync] 区域内让控制器的异步链结算完毕。
void flush(FakeAsync async) => async.elapse(const Duration(milliseconds: 1));

void main() {
  group('ad-orchestration openness contract — every row needs default + knob + injection', () {
    test('whether an ad waits for readiness: per-kind defaults are pre no / mid yes / post no', () {
      const p = MovaAdWaitByKind();
      expect(p.pre, isFalse);
      expect(p.mid, isTrue);
      expect(p.post, isFalse);
      expect(const MovaAdConfig().waitForAdReady, isA<MovaAdWaitByKind>());
    });

    test('whether an ad waits for readiness: all three override layers actually bite', () {
      // Layer 3 — the per-kind default.
      expect(const MovaAdConfig().waitsFor(_mid), isTrue);

      // Layer 2 — the injected policy replaces the per-kind default.
      final injected = _RecordingWait(answer: false);
      expect(MovaAdConfig(waitForAdReady: injected).waitsFor(_mid), isFalse);
      expect(injected.calls, 1, reason: 'the injected policy must really be consulted');

      // Layer 1 — the break itself beats both.
      const forced = MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: MovaSource('https://host/mid.mp4'),
        waitForReady: false,
      );
      expect(const MovaAdConfig().waitsFor(forced), isFalse);
      final ignored = _RecordingWait(answer: false);
      const forcedOn = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: MovaSource('https://host/pre.mp4'),
        waitForReady: true,
      );
      expect(MovaAdConfig(waitForAdReady: ignored).waitsFor(forcedOn), isTrue);
      expect(ignored.calls, 0, reason: 'the break answered, so the policy is not asked');
    });

    test('how long to wait for readiness: 5s default, adReadyTimeout knob, policy injection', () {
      expect(const MovaAdConfig().adReadyTimeout, const Duration(seconds: 5));
      const c = MovaAdConfig(adReadyTimeout: Duration(seconds: 2));
      expect(c.adReadyTimeout, const Duration(seconds: 2));
      expect((c.effectiveWarmPlan.policy! as MovaBufferWarm).timeout, const Duration(seconds: 2));

      final custom = MovaBufferWarm(timeout: const Duration(seconds: 9));
      final injected = MovaAdConfig(adWarmPlan: MovaWarmPlan(policy: custom));
      expect(injected.effectiveWarmPlan.policy, same(custom));
    });

    test('when the ad warm-up starts: eager by default, trigger injection via adWarmPlan', () {
      expect(const MovaAdConfig().effectiveWarmPlan.trigger, isA<MovaEagerWarm>());
      const custom = MovaLeadWarm(lead: Duration(seconds: 1), minDuration: Duration(seconds: 2));
      const injected = MovaAdConfig(adWarmPlan: MovaWarmPlan(trigger: custom));
      expect(injected.effectiveWarmPlan.trigger, same(custom));
    });

    test('what to do when readiness never came: hardCut default, notReadyAction knob', () {
      expect(const MovaAdConfig().notReadyAction, MovaAdNotReady.hardCut);
      expect(
        const MovaAdConfig(notReadyAction: MovaAdNotReady.dropBreak).notReadyAction,
        MovaAdNotReady.dropBreak,
      );
      // The enum is exhaustive by construction: cut in anyway, or do not.
      expect(MovaAdNotReady.values, hasLength(2));
    });

    test('what to do when an ad will not load: skip-after-zero-retries default, failPolicy injection', () {
      expect(const MovaAdConfig().effectiveFailPolicy, isA<MovaAdRetrySkip>());
      expect(const MovaAdRetrySkip().maxRetries, 0);
      expect(const MovaAdConfig(failPolicy: MovaAdAbandonPod()).effectiveFailPolicy,
          isA<MovaAdAbandonPod>());

      // And the injected policy is really the one MovaAdCtrl consults.
      fakeAsync((async) {
        final policy = _RecordingFail();
        final (api, c) = build(MovaAdConfig(
          enabled: true,
          breaks: const [
            MovaAdBreak(kind: MovaAdBreakKind.pre, source: MovaSource('https://host/pre.mp4')),
          ],
          failPolicy: policy,
        ));
        api.openThrows = StateError('404');
        api.openThrowsFor = 'https://host/pre.mp4';
        c.load(_content);
        flush(async);
        expect(policy.seen, hasLength(1));
      });
    });

    test('how long with no first frame counts as a load failure: 8s default, loadTimeout knob', () {
      expect(const MovaAdConfig().loadTimeout, const Duration(seconds: 8));
      expect(const MovaAdConfig(loadTimeout: Duration(seconds: 3)).loadTimeout,
          const Duration(seconds: 3));
      // The failure kind is handed to the policy, which decides per kind.
      fakeAsync((async) {
        final policy = _RecordingFail();
        final (api, c) = build(MovaAdConfig(
          enabled: true,
          breaks: const [
            MovaAdBreak(kind: MovaAdBreakKind.pre, source: MovaSource('https://host/pre.mp4')),
          ],
          failPolicy: policy,
          loadTimeout: const Duration(seconds: 3),
        ));
        c.load(_content);
        flush(async);
        async.elapse(const Duration(seconds: 3));
        flush(async);
        expect(policy.seen.single.kind, MovaAdFailKind.loadTimeout);
      });
    });

    test('when the slot clock starts: first frame by default, durationFromFirstFrame knob', () {
      expect(const MovaAdConfig().durationFromFirstFrame, isTrue);
      expect(const MovaAdConfig(durationFromFirstFrame: false).durationFromFirstFrame, isFalse);
    });

    test(
      'whether a warmed ad holds at frame zero: ALWAYS true, deliberately no knob — '
      'this is a correctness invariant of ad delivery, not a matter of taste',
      () {
        expect(
          const MovaAdConfig().effectiveWarmPlan.pauseWhenReady,
          isTrue,
          reason: 'An ad that quietly played its first seconds inside the shadow engine is '
              'delivered with its head missing, and those seconds count towards no defensible '
              'impression measure. The openness contract — every decision gets a default, a '
              'knob and an injection point — yields to correctness here, and this test is where '
              'that exception is recorded rather than silently omitted. '
              '一条在影子引擎里已经悄悄播了两秒的广告，交付出去就是缺头的，且那两秒计不进任何'
              '合理的曝光口径。"每个决策都要有默认值+配置项+可注入策略"的开放性契约在此让位于'
              '正确性，这条测试就是该例外的留痕，而不是把它悄悄省掉。',
        );
        // A host that injects a whole plan still owns the field; what has no
        // knob is the *default*, which never silently drops the hold.
        expect(
          const MovaAdConfig(adWarmPlan: MovaWarmPlan()).effectiveWarmPlan.pauseWhenReady,
          isFalse,
          reason: 'wholesale plan injection remains possible and is the escape hatch',
        );
      },
    );

    test('the controller really uses the resolved plan for the content→ad direction', () {
      fakeAsync((async) {
        final swap = FakeSwapCtl();
        final (api, c) = build(
          const MovaAdConfig(enabled: true, breaks: [_mid]),
          swap: swap,
        );
        c.load(_content);
        flush(async);
        api.pushProgress(const MovaProg(position: Duration(seconds: 31)));
        flush(async);
        expect(swap.calls, contains('prepare'));
        expect(swap.lastPlan!.pauseWhenReady, isTrue);
        expect(swap.lastPlan!.trigger, isA<MovaEagerWarm>());
      });
    });
  });

  group('barrel visibility — the 0.5.0 public surface is reachable from package:mova/mova.dart', () {
    test('MovaWarmPlan is exported', () {
      const plan = barrel.MovaWarmPlan(pauseWhenReady: true);
      expect(plan.pauseWhenReady, isTrue);
    });

    test('MovaAdFailPolicy and its built-ins are exported', () {
      const barrel.MovaAdFailPolicy policy = barrel.MovaAdRetrySkip(maxRetries: 1);
      expect(policy, isA<barrel.MovaAdFailPolicy>());
      expect(const barrel.MovaAdAbandonPod(), isA<barrel.MovaAdFailPolicy>());
      expect(barrel.MovaAdFailKind.values, isNotEmpty);
      expect(barrel.MovaAdFailAction.values, isNotEmpty);
    });

    test('MovaAdNotReady, MovaAdWaitPolicy and MovaSourceResolver are exported', () {
      expect(barrel.MovaAdNotReady.dropBreak, isA<barrel.MovaAdNotReady>());
      const barrel.MovaAdWaitPolicy wait = barrel.MovaAdWaitByKind();
      expect(wait.waitFor(_mid), isTrue);
      Future<barrel.MovaSource> resolve() async =>
          const barrel.MovaSource('https://host/x.mp4');
      const barrel.MovaSourceResolver? unset = null;
      expect(resolve, isA<barrel.MovaSourceResolver>());
      expect(unset, isNull);
    });
  });
}

/// Records how often the controller consulted this wait policy.
///
/// 记录控制器咨询本等待策略的次数。
class _RecordingWait implements MovaAdWaitPolicy {
  /// What [waitFor] answers.
  ///
  /// [waitFor] 的回答。
  final bool answer;

  /// How many times [waitFor] was called.
  ///
  /// [waitFor] 被调用的次数。
  int calls = 0;

  /// Creates a recording wait policy answering [answer].
  ///
  /// 创建一个回答 [answer] 的记录型等待策略。
  _RecordingWait({required this.answer});

  @override
  bool waitFor(MovaAdBreak adBreak) {
    calls++;
    return answer;
  }
}

/// Records every failure the controller reported to this policy.
///
/// 记录控制器上报给本策略的所有失败。
class _RecordingFail implements MovaAdFailPolicy {
  /// Every failure passed to [onFailure], in order.
  ///
  /// 依次传给 [onFailure] 的所有失败记录。
  final List<MovaAdFail> seen = <MovaAdFail>[];

  @override
  MovaAdFailAction onFailure(MovaAdFail failure) {
    seen.add(failure);
    return MovaAdFailAction.skipBreak;
  }
}
