import 'dart:async';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova/src/core/session/transition.dart';
import '../../support/fake_api.dart';
import '../../support/gated.dart';
import '../ads_interleaving_test.dart' show AdOperationRig;
import '../ads_open_failure_test.dart' show RecordingAdPolicy;
import '../cutover/cutover_operation_test.dart' show settleOperations;
import 'session_test.dart' show a, b, done;

const first = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/pod1.mp4'),
);
const second = MovaAdBreak(
  kind: MovaAdBreakKind.mid,
  source: MovaSource('https://host/pod2.mp4'),
);
const waitingPre = MovaAdBreak(
  kind: MovaAdBreakKind.pre,
  source: MovaSource('https://host/pre.mp4'),
  waitForReady: true,
);

Future<void> enterPod(AdOperationRig rig) async {
  await rig.ads.load(a);
  rig.engines.first.pushProgress(
    const MovaProg(position: Duration(seconds: 1)),
  );
  await settleOperations();
  await rig.ready(rig.engines.last);
}

void main() {
  test('中插 pod 每条预热提交，渲染纪元各增一次', () async {
    final rig = AdOperationRig(breaks: [first, second]);
    addTearDown(rig.dispose);
    await enterPod(rig);
    expect(rig.api.state.renderEpoch, 1);
    final old = rig.api.active as FakeMovaApi;
    await done(old);
    final next = rig.engines.last;
    expect(next, isNot(same(old)));
    await rig.ready(next);
    expect(rig.api.state.renderEpoch, 2);
    expect(next.source, second.source);
    expect(next.calls, containsAllInOrder(['pause', 'seek', 'play']));
  });
  test('等待型前贴片 pod 每条换指，默认不等待仍直接打开', () async {
    for (final wait in [true, false]) {
      final ads = [
        MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: waitingPre.source,
          waitForReady: wait ? true : null,
        ),
        MovaAdBreak(
          kind: MovaAdBreakKind.pre,
          source: b,
          waitForReady: wait ? true : null,
        ),
      ];
      final rig = AdOperationRig(breaks: ads);
      addTearDown(rig.dispose);
      final loading = rig.ads.load(a);
      await settleOperations();
      if (wait) await rig.ready(rig.engines.last);
      expect(await loading, isTrue);
      await done(rig.api.active as FakeMovaApi);
      if (wait) await rig.ready(rig.engines.last);
      expect(rig.api.state.renderEpoch, wait ? 2 : 0);
      expect((rig.api.active as FakeMovaApi).source, b);
      expect(rig.ads.currentBreak, same(ads[1]));
      if (wait) {
        expect((rig.api.active as FakeMovaApi).calls,
          containsAllInOrder(['pause', 'seek', 'play']));
      }
    }
  });
  test('一次性广告计划使用 1x 停首帧，真实就绪期限取广告期限', () {
    fakeAsync((clock) {
      final engines = <FakeMovaApi>[];
      final api = MovaCutoverEngine(
        engineFactory: () {
          final e = FakeMovaApi(
            options: const MovaOpts(
              cutover: MovaCutoverConfig(enabled: true),
              ads: MovaAdConfig(
                enabled: true,
                breaks: [waitingPre],
                adReadyTimeout: Duration(seconds: 2),
              ),
            ),
          );
          engines.add(e);
          return e;
        },
      );
      final ads = MovaAds(api, cutover: api);
      var accepted = false;
      unawaited(
        ads.load(a).then((v) {
          accepted = v;
        }),
      );
      clock.flushMicrotasks();
      expect(engines, hasLength(2));
      clock.elapse(const Duration(milliseconds: 1999));
      expect(accepted, isFalse);
      clock.elapse(const Duration(milliseconds: 1));
      clock.flushMicrotasks();
      expect(accepted, isTrue);
      expect(engines.first.source, waitingPre.source);
      final plain = FakeMovaApi(options: const MovaOpts(ads: MovaAdConfig(
        enabled: true, breaks: [waitingPre], adReadyTimeout: Duration(seconds: 2))));
      final ctl = FakeCutoverCtl()..commitResult = true;
      final adapter = MovaAds(plain, cutover: ctl);
      unawaited(adapter.load(a)); clock.flushMicrotasks();
      expect(ctl.lastPlan?.rate, 1.0);
      expect(ctl.lastPlan?.pauseWhenReady, isTrue);
      expect((ctl.lastPlan?.policy as MovaBufferWarm).timeout, const Duration(seconds: 2));
      unawaited(adapter.dispose()); clock.flushMicrotasks();
      unawaited(plain.dispose()); clock.flushMicrotasks();
      unawaited(ctl.dispose()); clock.flushMicrotasks();
      final plan = movaAdWarmPlan(const MovaAdConfig());
      expect(plan.rate, 1.0);
      expect(plan.pauseWhenReady, isTrue);
      expect(
        (plan.policy as MovaBufferWarm).timeout,
        const Duration(seconds: 5),
      );
      final custom = movaAdWarmPlan(
        const MovaAdConfig(adWarmPlan: MovaWarmPlan(pauseWhenReady: true)),
      );
      expect(custom.rate, 1.0);
      unawaited(ads.dispose());
      clock.flushMicrotasks();
      unawaited(api.dispose());
      clock.flushMicrotasks();
    });
  });
  test('第二条落地窗口丢弃旧广告 Done 错误与进度', () async {
    final policy = RecordingAdPolicy();
    final api = FakeMovaApi(
      options: MovaOpts(
        ads: MovaAdConfig(
          enabled: true,
          breaks: const [waitingPre, waitingPre],
          failPolicy: policy,
        ),
      ),
    );
    final cutover = FakeCutoverCtl()..commitResult = true;
    final ads = MovaAds(api, cutover: cutover);
    addTearDown(() async {
      await ads.dispose();
      await api.dispose();
      await cutover.dispose();
    });
    final events = <MovaSessionEvent>[];
    ads.session.events.listen(events.add);
    await ads.load(a);
    final gate = cutover.commitGate = Completer<void>();
    await done(api);
    api.pushEvent(const MovaDone());
    api.pushEvent(const MovaErrorEvent('old'));
    api.pushProgress(const MovaProg(position: Duration(seconds: 8)));
    await settleOperations();
    expect(policy.failures, isEmpty);
    expect(events.whereType<MovaNodeEnd>(), hasLength(1));
    expect(ads.adPosition, Duration.zero);
    gate.complete();
    await settleOperations();
    expect(ads.session.cursor.node?.ordinal, 1);
  });
  test('prepare 期间槽被换走只硬切目标广告，不提交宿主影子', () async {
    final gate = Completer<void>();
    final rig = AdOperationRig(breaks: [first], gateShadow: gate);
    addTearDown(rig.dispose);
    await rig.ads.load(a);
    rig.engines.first.pushProgress(
      const MovaProg(position: Duration(seconds: 1)),
    );
    await settleOperations();
    rig.gateShadow = null;
    await rig.api.prepare(
      b,
      plan: const MovaWarmPlan(trigger: MovaEagerWarm()),
    );
    final hostShadow = rig.engines.last;
    await settleOperations();
    // Cancellation now ends preparation without waiting for the old open hook.
    //
    // 取消现在会直接结束预热，不再等待旧 open 钩子返回。
    expect(gate.isCompleted, isFalse);
    expect(rig.engines.first.source, first.source);
    expect(hostShadow.disposeCount, 1);
    gate.complete();
    await settleOperations();
    expect(rig.api.active, same(rig.engines.first));
    expect(rig.engines.first.source, first.source);
    expect(hostShadow.disposeCount, 1);
  });
  test('宿主在广告提交窗口直接 open，不回落抢源', () async {
    final rig = AdOperationRig(breaks: [waitingPre]);
    addTearDown(rig.dispose);
    final loading = rig.ads.load(a);
    await settleOperations();
    final gate = rig.engines.first.pauseGate = Completer<void>();
    await rig.ready(rig.engines.last);
    await rig.api.open(b);
    gate.complete();
    expect(await loading, isFalse);
    await settleOperations();
    expect((rig.api.active as FakeMovaApi).source, b);
    expect(rig.engines.first.openedUris, [b.uri]);
    expect(rig.ads.session.cursor.phase, MovaSessionPhase.idle);
  });
  test('回正片凭据提交被宿主取代不回落 open', () async {
    final rig = AdOperationRig();
    addTearDown(rig.dispose);
    await rig.ads.load(a);
    final shadow = await rig.warmContent();
    final ad = rig.engines.first;
    final gate = ad.pauseGate = Completer<void>();
    await done(ad);
    expect(rig.engines.last, same(shadow));
    await rig.api.open(b);
    gate.complete();
    await settleOperations();
    expect(ad.openedUris.last, b.uri);
    expect(ad.openedUris.where((uri) => uri == a.uri), hasLength(1));
    expect(rig.ads.session.cursor.phase, MovaSessionPhase.idle);
  });
  test('正片预热用素材与广告位较小剩余，未知时长不负数', () {
    fakeAsync((clock) {
      const ad = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: b,
        duration: Duration(seconds: 15),
      );
      final factory = GatedEngineFactory();
      final api = MovaCutoverEngine(
        engineFactory: () {
          final e = FakeMovaApi(
            options: const MovaOpts(
              cutover: MovaCutoverConfig(
                enabled: true,
                trigger: MovaLeadWarm(
                  lead: Duration(seconds: 2),
                  minDuration: Duration.zero,
                ),
              ),
              ads: MovaAdConfig(enabled: true, breaks: [ad]),
            ),
          );
          factory.engines.add(e);
          return e;
        },
      );
      final session = MovaSession(api)
        ..debugClock = () => DateTime.utc(2026).add(clock.elapsed);
      unawaited(session.load(a));
      clock.flushMicrotasks();
      final active = factory.engines.first;
      active.push(active.state.copyWith(duration: const Duration(seconds: 30)));
      active.pushEvent(
        const MovaFirstFrame(
          sinceOpen: Duration.zero,
          signal: MovaFirstFrameSignal.restart,
        ),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 12));
      active.pushProgress(const MovaProg(position: Duration(seconds: 12)));
      clock.flushMicrotasks();
      expect(factory.engines, hasLength(1));
      clock.elapse(const Duration(seconds: 1));
      active.pushProgress(const MovaProg(position: Duration(seconds: 13)));
      clock.flushMicrotasks();
      expect(factory.engines, hasLength(2));
      expect(factory.engines.last.source, a);
      expect(
        movaContentWarmCue(
          mediaDuration: Duration.zero,
          adPosition: const Duration(seconds: 99),
        ).remaining,
        isNull,
      );
      expect(
        movaContentWarmCue(
          mediaDuration: const Duration(seconds: 1),
          adPosition: const Duration(seconds: 2),
        ).remaining,
        Duration.zero,
      );
      unawaited(session.dispose());
      clock.flushMicrotasks();
      unawaited(api.dispose());
      clock.flushMicrotasks();
    });
  });
}
