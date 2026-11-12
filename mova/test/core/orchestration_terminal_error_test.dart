import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import '../support/fake_api.dart';

/// 等待广告与切换的异步动作完成，不推进墙钟超时。
Future<void> _settle() async => pumpEventQueue();

/// 广告失败策略的观察替身，不复用或修改生产尝试结算逻辑。
class _Policy implements MovaAdFailPolicy {
  /// 收到的广告失败。
  final failures = <MovaAdFail>[];
  /// 记录 [fail] 并跳过此广告位。
  @override
  MovaAdFailAction onFailure(MovaAdFail fail) {
    failures.add(fail);
    return MovaAdFailAction.skipBreak;
  }
}

/// 运行广告与预热终结错误的回归。
void main() {
  for (final firstFrame in [false, true]) {
    test('A15 ad firstFrame=$firstFrame ignores diagnostic then settles terminal error once', () async {
      final policy = _Policy();
      const ad = MovaAdBreak(kind: MovaAdBreakKind.pre, source: MovaSource('https://h/ad.mp4'));
      final api = FakeMovaApi(options: MovaOpts(ads: MovaAdConfig(
        enabled: true, breaks: const [ad], failPolicy: policy,
      )));
      final ads = MovaAds(api);
      await ads.load(const MovaSource('https://h/content.mp4'));
      await _settle();
      if (firstFrame) {
        api.pushEvent(const MovaFirstFrame(sinceOpen: Duration.zero, signal: MovaFirstFrameSignal.restart));
        await _settle();
      }
      final opens = api.calls.where((v) => v == 'open').length;
      api.pushEvent(const MovaErrorEvent.classified('damaged frame', fatal: false));
      await _settle();
      expect(ads.isShowingAd, isTrue);
      expect(policy.failures, isEmpty);
      expect(api.calls.where((v) => v == 'open'), hasLength(opens));
      api.pushEvent(const MovaErrorEvent.classified('terminal', fatal: true));
      api.pushEvent(const MovaErrorEvent.classified('duplicate terminal', fatal: true));
      await _settle();
      expect(policy.failures, hasLength(1));
      expect(policy.failures.single.kind, MovaAdFailKind.playerError);
      expect(api.source?.uri, 'https://h/content.mp4');
      await ads.dispose();
      await api.dispose();
    });
  }

  for (final fatal in [false, true]) {
    test('A15 shadow fatal=$fatal only terminal abandons an awaiting commit without public error', () async {
      final engines = <FakeMovaApi>[];
      final proxy = MovaCutoverEngine(engineFactory: () {
        final e = FakeMovaApi(options: const MovaOpts(cutover: MovaCutoverConfig(enabled: true)));
        engines.add(e);
        return e;
      });
      final errors = <MovaErrorEvent>[];
      final sub = proxy.events.where((v) => v is MovaErrorEvent).cast<MovaErrorEvent>().listen(errors.add);
      await proxy.prepare(const MovaSource('https://h/next.mp4'),
        plan: MovaWarmPlan(trigger: const MovaEagerWarm(), policy: MovaBufferWarm(stableTicks: 1)));
      final shadow = engines.last;
      bool? result;
      final commit = proxy.commit(waitForReady: true).then((value) => result = value);
      await _settle();
      shadow.pushEvent(MovaErrorEvent.classified('diagnostic', fatal: fatal));
      await _settle();
      if (fatal) {
        expect(result, isFalse);
        expect(shadow.calls, contains('dispose'));
        expect(proxy.active, same(engines.first));
      } else {
        expect(result, isNull, reason: '非终结日志不解除就绪等待');
        expect(shadow.calls, isNot(contains('dispose')));
        shadow.pushProgress(const MovaProg(position: Duration.zero, buffer: Duration(seconds: 10)));
        await _settle();
        expect(await commit, isTrue);
        expect(proxy.active, same(shadow));
      }
      await commit;
      expect(errors, isEmpty, reason: '影子错误不冒成在屏错误');
      await sub.cancel();
      await proxy.dispose();
    });
  }
}
