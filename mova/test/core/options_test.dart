import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/ad/fail.dart';
import 'package:mova/src/core/model/ad.dart';
import 'package:mova/src/core/model/danmaku.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/mini/placement.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/core/preview/platform_kind.dart';
import 'package:mova/src/core/state/state.dart';
import 'package:mova/src/core/swap/plan.dart';
import 'package:mova/src/core/swap/trigger.dart';
import 'package:mova/src/core/swap/warm.dart';

void main() {
  test('MovaOpts gesture defaults follow the mainstream side↔action mapping', () {
    const o = MovaOpts();
    expect(o.gesture.leftVertical, MovaGestAction.brightness);
    expect(o.gesture.rightVertical, MovaGestAction.volume);
    expect(o.gesture.horizontal, MovaGestAction.seek);
    expect(o.gesture.hSeekSpanPerScreen, const Duration(seconds: 90));
    expect(o.gesture.doubleTapStep, const Duration(seconds: 10));
    expect(o.abr.stallThreshold, 3);
    expect(o.controls.autoHideDelay, const Duration(seconds: 3));
    expect(o.live.seekMode, MovaLiveSeekMode.off);
  });

  test('MovaStrs.fitLabel covers every MovaFit value', () {
    const s = MovaStrs();
    for (final f in MovaFit.values) {
      expect(s.fitLabel(f), isNotEmpty);
    }
    expect(s.fitLabel(MovaFit.contain), '适应');
  });

  test('MovaStrs can be replaced wholesale for localisation', () {
    const s = MovaStrs(fitContain: 'Fit', live: 'ON AIR');
    expect(s.fitLabel(MovaFit.contain), 'Fit');
    expect(s.live, 'ON AIR');
  });

  test('MovaOpts.copyWith replaces one section only', () {
    const o = MovaOpts();
    final n = o.copyWith(controls: const MovaCtrlsConfig(autoHide: false));
    expect(n.controls.autoHide, isFalse);
    expect(n.gesture, o.gesture);
  });

  test('MovaPrevConfig defaults match DESIGN section 6.1', () {
    const p = MovaPrevConfig();
    expect(p.enabled, isTrue);
    expect(p.network, MovaPrevNet.wifiOnly);
    expect(p.onBlocked, isNull);
    expect(p.sources, isNull, reason: 'null means the built-in [vtt, extract] chain');
    expect(p.vttEnabled, isTrue);
    expect(p.vttUrl, isNull);
    expect(p.vttUrlResolver, isNull);
    expect(p.extractFallback, isTrue);
    expect(p.extractPlatforms, MovaPlatKind.values.toSet());
    expect(p.frameWidth, 160);
    expect(p.bucket, const Duration(seconds: 10));
    expect(p.hwdec, isFalse);
    expect(p.memMaxEntries, 40);
    expect(p.diskMaxBytes, 64 * 1024 * 1024);
    expect(p.diskDir, isNull);
    expect(p.cacheKeyBuilder, isNull);
    expect(p.clearOnDispose, isTrue);
    expect(p.debounce, const Duration(milliseconds: 120));
    expect(p.probe, isNull);
    expect(p.cache, isNull);
    expect(p.extractor, isNull);
  });

  test('MovaOpts exposes a preview section that defaults to MovaPrevConfig', () {
    const o = MovaOpts();
    expect(o.preview, const MovaPrevConfig());
  });

  test('MovaOpts.copyWith replaces only the preview section', () {
    const o = MovaOpts();
    final n = o.copyWith(preview: const MovaPrevConfig(frameWidth: 320));
    expect(n.preview.frameWidth, 320);
    expect(n.gesture, o.gesture);
    expect(n.controls, o.controls);
    expect(n, isNot(o));
  });

  test('MovaPrevConfig.copyWith replaces one knob and compares by value', () {
    const p = MovaPrevConfig();
    final n = p.copyWith(network: MovaPrevNet.never);
    expect(n.network, MovaPrevNet.never);
    expect(n.frameWidth, p.frameWidth);
    expect(n, isNot(p));
    expect(p.copyWith(), p);
  });

  test('every MovaPrevConfig injection point accepts a custom strategy', () {
    final p = MovaPrevConfig(
      probe: AlwaysAllowNetProbe(),
      cacheKeyBuilder: (s, b, w) => 'custom',
      vttUrlResolver: (s) => Uri.parse('https://cdn/t.vtt'),
      onBlocked: (_) {},
      extractPlatforms: const {MovaPlatKind.windows},
    );
    expect(p.probe, isA<MovaNetProbe>());
    expect(p.cacheKeyBuilder!('a', 1, 2), 'custom');
    expect(p.vttUrlResolver!(const MovaSource('x')), Uri.parse('https://cdn/t.vtt'));
    expect(p.onBlocked, isNotNull);
    expect(p.extractPlatforms, {MovaPlatKind.windows});
  });

  test('MovaLiveConfig defaults keep 0.1.0 behaviour and add the new knobs off', () {
    const c = MovaLiveConfig();
    expect(c.seekMode, MovaLiveSeekMode.off);
    expect(c.dvrWindow, isNull);
    expect(c.edgeThreshold, const Duration(seconds: 10));
    expect(c.urlBuilder, isNull);
    expect(c.backToLive, isNull);
    expect(c.autoBackToLiveOnStall, isFalse);
    expect(c.windowResolver, isNull);
  });

  test('effectiveBackToLive derives from seekMode when not configured', () {
    expect(const MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr).effectiveBackToLive,
        MovaBackToLive.seekEnd);
    expect(const MovaLiveConfig(seekMode: MovaLiveSeekMode.timeshift).effectiveBackToLive,
        MovaBackToLive.reopen);
    expect(const MovaLiveConfig().effectiveBackToLive, MovaBackToLive.seekEnd);
  });

  test('an explicit backToLive overrides the derived default', () {
    const c = MovaLiveConfig(
      seekMode: MovaLiveSeekMode.timeshift,
      backToLive: MovaBackToLive.seekEnd,
    );
    expect(c.effectiveBackToLive, MovaBackToLive.seekEnd);
  });

  test('urlBuilder and windowResolver are injectable strategies', () {
    final c = MovaLiveConfig(
      seekMode: MovaLiveSeekMode.timeshift,
      urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
      windowResolver: (s) => const Duration(minutes: 30),
    );
    expect(
      c.urlBuilder!('https://h/l.m3u8', const Duration(seconds: 60), DateTime(2026)),
      'https://h/l.m3u8?behind=60',
    );
    expect(c.windowResolver!(const MovaState()), const Duration(minutes: 30));
  });

  test('MovaLiveConfig.copyWith replaces one field only', () {
    const c = MovaLiveConfig(seekMode: MovaLiveSeekMode.dvr);
    final n = c.copyWith(autoBackToLiveOnStall: true);
    expect(n.autoBackToLiveOnStall, isTrue);
    expect(n.seekMode, MovaLiveSeekMode.dvr);
    expect(n.edgeThreshold, c.edgeThreshold);
  });

  test('MovaDanmakuConfig defaults to disabled and empty', () {
    const d = MovaDanmakuConfig();
    expect(d.enabled, isFalse);
    expect(d.items, isEmpty);
    expect(d.trackCount, 4);
    expect(d.crossDuration, const Duration(seconds: 8));
  });

  test('MovaDanmakuConfig.copyWith replaces one field and compares by value', () {
    const d = MovaDanmakuConfig();
    final n = d.copyWith(enabled: true, items: const [MovaDanmakuItem(text: 'hi', time: Duration.zero)]);
    expect(n.enabled, isTrue);
    expect(n.items, hasLength(1));
    expect(n.trackCount, d.trackCount);
    expect(n, isNot(d));
  });

  test('MovaOpts exposes a danmaku section that defaults to MovaDanmakuConfig', () {
    const o = MovaOpts();
    expect(o.danmaku, const MovaDanmakuConfig());
  });

  test('MovaOpts.copyWith replaces only the danmaku section', () {
    const o = MovaOpts();
    final n = o.copyWith(danmaku: const MovaDanmakuConfig(enabled: true));
    expect(n.danmaku.enabled, isTrue);
    expect(n.gesture, o.gesture);
    expect(n, isNot(o));
  });

  test('MovaSwapConfig defaults are off with the documented tuning values', () {
    const c = MovaSwapConfig();
    expect(c.enabled, isFalse);
    expect(c.leadTime, const Duration(seconds: 2));
    expect(c.minWarmDuration, const Duration(seconds: 5));
    expect(c.readyTimeout, const Duration(seconds: 8));
    expect(c.muteWhileWarm, isTrue);
    expect(c.trigger, isNull);
    expect(c.readyPolicy, isNull);
  });

  test('MovaSwapConfig.effectiveTrigger falls back to a seeded MovaLeadWarm, or returns the injected one', () {
    const c = MovaSwapConfig(leadTime: Duration(seconds: 3), minWarmDuration: Duration(seconds: 6));
    final t = c.effectiveTrigger;
    expect(t, isA<MovaLeadWarm>());
    expect((t as MovaLeadWarm).lead, const Duration(seconds: 3));
    expect(t.minDuration, const Duration(seconds: 6));

    const injected = MovaEagerWarm();
    const c2 = MovaSwapConfig(trigger: injected);
    expect(c2.effectiveTrigger, same(injected));
  });

  test('MovaSwapConfig.newReadyPolicy returns a fresh instance each call, or the injected one', () {
    const c = MovaSwapConfig();
    final a = c.newReadyPolicy();
    final b = c.newReadyPolicy();
    expect(identical(a, b), isFalse);

    final injected = MovaBufferWarm();
    final c2 = MovaSwapConfig(readyPolicy: injected);
    expect(c2.newReadyPolicy(), same(injected));
  });

  test('MovaSwapConfig.copyWith replaces one field only', () {
    const c = MovaSwapConfig();
    final n = c.copyWith(enabled: true);
    expect(n.enabled, isTrue);
    expect(n.leadTime, c.leadTime);
    expect(n.muteWhileWarm, c.muteWhileWarm);
  });

  test('MovaOpts exposes a swap section that defaults to MovaSwapConfig and is independently replaceable', () {
    const o = MovaOpts();
    expect(o.swap, const MovaSwapConfig());
    final n = o.copyWith(swap: const MovaSwapConfig(enabled: true));
    expect(n.swap.enabled, isTrue);
    expect(n.gesture, o.gesture);
  });

  group('MovaAdConfig — 0.5.0 ad orchestration knobs', () {
    const adBreak = MovaAdBreak(kind: MovaAdBreakKind.mid, source: MovaSource('https://h/ad.mp4'));

    test('all seven new knobs carry their documented defaults', () {
      const c = MovaAdConfig();
      expect(c.waitForAdReady, isA<MovaAdWaitByKind>());
      expect(c.adReadyTimeout, const Duration(seconds: 5));
      expect(c.notReadyAction, MovaAdNotReady.hardCut);
      expect(c.failPolicy, isNull);
      expect(c.loadTimeout, const Duration(seconds: 8));
      expect(c.durationFromFirstFrame, isTrue);
      expect(c.adWarmPlan, isNull);
    });

    test('MovaAdWaitByKind defaults: pre false, mid true, post false', () {
      const p = MovaAdWaitByKind();
      expect(p.pre, isFalse, reason: 'nothing is on screen to protect before a pre-roll');
      expect(p.mid, isTrue, reason: 'the content the viewer is watching is worth protecting');
      expect(p.post, isFalse, reason: 'the content is over; nothing to protect');
    });

    test('MovaAdWaitByKind.waitFor answers per kind, and the defaults can be rewritten wholesale', () {
      const def = MovaAdWaitByKind();
      MovaAdBreak of(MovaAdBreakKind k) => MovaAdBreak(kind: k, source: const MovaSource('https://h/a.mp4'));
      expect(def.waitFor(of(MovaAdBreakKind.pre)), isFalse);
      expect(def.waitFor(of(MovaAdBreakKind.mid)), isTrue);
      expect(def.waitFor(of(MovaAdBreakKind.post)), isFalse);

      const custom = MovaAdWaitByKind(mid: false, post: true);
      expect(custom.waitFor(of(MovaAdBreakKind.pre)), isFalse);
      expect(custom.waitFor(of(MovaAdBreakKind.mid)), isFalse);
      expect(custom.waitFor(of(MovaAdBreakKind.post)), isTrue);
    });

    test('MovaAdBreak.waitForReady overrides the per-kind default in both directions', () {
      const c = MovaAdConfig();
      const forcedOn = MovaAdBreak(
        kind: MovaAdBreakKind.pre,
        source: MovaSource('https://h/pre.mp4'),
        waitForReady: true,
      );
      const forcedOff = MovaAdBreak(
        kind: MovaAdBreakKind.mid,
        source: MovaSource('https://h/mid.mp4'),
        waitForReady: false,
      );
      expect(c.waitsFor(forcedOn), isTrue, reason: 'pre defaults to false but the break says true');
      expect(c.waitsFor(forcedOff), isFalse, reason: 'mid defaults to true but the break says false');
    });

    test('waitsFor falls through to the injected policy when the break stays silent', () {
      final policy = RecordingWaitPolicy(answer: true);
      final c = MovaAdConfig(waitForAdReady: policy);
      expect(c.waitsFor(adBreak), isTrue);
      expect(policy.calls, 1, reason: 'the injected policy must actually be consulted');
    });

    test('effectiveWarmPlan / effectiveFailPolicy default sensibly and honour injection', () {
      const c = MovaAdConfig(adReadyTimeout: Duration(seconds: 3));
      final plan = c.effectiveWarmPlan;
      expect(plan.trigger, isA<MovaEagerWarm>());
      expect(plan.policy, isA<MovaBufferWarm>());
      expect((plan.policy! as MovaBufferWarm).timeout, const Duration(seconds: 3));
      expect(plan.pauseWhenReady, isTrue);
      expect(c.effectiveFailPolicy, isA<MovaAdRetrySkip>());

      const injected = MovaWarmPlan(pauseWhenReady: false);
      const abandon = MovaAdAbandonPod();
      const c2 = MovaAdConfig(adWarmPlan: injected, failPolicy: abandon);
      expect(c2.effectiveWarmPlan, same(injected));
      expect(c2.effectiveFailPolicy, same(abandon));
    });

    test('copyWith replaces one new field at a time, and MovaOpts.copyWith(ads:) is section-local', () {
      const c = MovaAdConfig();
      expect(c.copyWith(adReadyTimeout: const Duration(seconds: 9)).adReadyTimeout,
          const Duration(seconds: 9));
      expect(c.copyWith(adReadyTimeout: const Duration(seconds: 9)).loadTimeout, c.loadTimeout);
      expect(c.copyWith(notReadyAction: MovaAdNotReady.dropBreak).notReadyAction,
          MovaAdNotReady.dropBreak);
      expect(c.copyWith(loadTimeout: const Duration(seconds: 2)).loadTimeout,
          const Duration(seconds: 2));
      expect(c.copyWith(durationFromFirstFrame: false).durationFromFirstFrame, isFalse);
      expect(c.copyWith(failPolicy: const MovaAdAbandonPod()).failPolicy, isA<MovaAdAbandonPod>());
      expect(c.copyWith(waitForAdReady: const MovaAdWaitByKind(mid: false)).waitForAdReady,
          const MovaAdWaitByKind(mid: false));
      expect(c.copyWith(adWarmPlan: const MovaWarmPlan()).adWarmPlan, isNotNull);

      const o = MovaOpts();
      final n = o.copyWith(ads: const MovaAdConfig(loadTimeout: Duration(seconds: 1)));
      expect(n.ads.loadTimeout, const Duration(seconds: 1));
      expect(n.swap, o.swap);
      expect(n.gesture, o.gesture);
    });
  });

  group('MovaMiniConfig — in-app mini window', () {
    test('defaults: disabled, 180x(16/9), bottomRight corner', () {
      const c = MovaMiniConfig();
      expect(c.enabled, isFalse);
      expect(c.width, 180);
      expect(c.aspectRatio, 16 / 9);
      expect(c.initialCorner, MovaMiniCorner.bottomRight);
      expect(c.margin, 12);
      expect(c.snapToEdge, isTrue);
      expect(c.dismissible, isTrue);
      expect(c.settleDuration, const Duration(milliseconds: 220));
    });

    test('MovaOpts().mini equals a default MovaMiniConfig, and MovaOpts equality/hashCode include it', () {
      const o = MovaOpts();
      expect(o.mini, const MovaMiniConfig());
      final n = o.copyWith(mini: const MovaMiniConfig(enabled: true));
      expect(n.mini.enabled, isTrue);
      expect(n, isNot(equals(o)));
      expect(n.hashCode, isNot(equals(o.hashCode)));
      expect(n.preview, o.preview);
    });

    test('copyWith replaces only the given field', () {
      const c = MovaMiniConfig();
      final n = c.copyWith(enabled: true);
      expect(n.enabled, isTrue);
      expect(n.width, c.width);
      expect(n.aspectRatio, c.aspectRatio);
    });

    test('effectivePlacement falls back to MovaCornerSnap when placement is null, else returns it verbatim', () {
      const c = MovaMiniConfig();
      expect(c.effectivePlacement, isA<MovaCornerSnap>());
      final injected = MovaCornerSnap(snap: false);
      final c2 = MovaMiniConfig(placement: injected);
      expect(c2.effectivePlacement, same(injected));
    });

    test('constructor asserts reject non-positive width/aspectRatio and negative margin', () {
      expect(() => MovaMiniConfig(width: 0), throwsA(isA<AssertionError>()));
      expect(() => MovaMiniConfig(aspectRatio: -1), throwsA(isA<AssertionError>()));
      expect(() => MovaMiniConfig(margin: -1), throwsA(isA<AssertionError>()));
    });

    test('default MovaOpts() equals a freshly-constructed default (0.5.0 regression guard)', () {
      expect(const MovaOpts(), const MovaOpts());
    });
  });
}

/// A [MovaAdWaitPolicy] that records how often it was consulted.
///
/// 一个记录被咨询次数的 [MovaAdWaitPolicy]。
class RecordingWaitPolicy implements MovaAdWaitPolicy {
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
  RecordingWaitPolicy({this.answer = true});

  @override
  bool waitFor(MovaAdBreak adBreak) {
    calls++;
    return answer;
  }
}
