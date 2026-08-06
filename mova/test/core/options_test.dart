import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/danmaku.dart';
import 'package:mova/src/core/model/fit.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/core/preview/platform_kind.dart';
import 'package:mova/src/core/state/state.dart';

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
}
