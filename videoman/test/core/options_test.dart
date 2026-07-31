import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/fit.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/preview/net_probe.dart';
import 'package:videoman/src/core/preview/platform_kind.dart';
import 'package:videoman/src/core/state/state.dart';

void main() {
  test('VmOptions defaults are const-constructible and preserve 0.1.0 gesture behaviour', () {
    const o = VmOptions();
    expect(o.gesture.leftVerticalVolume, isTrue);
    expect(o.gesture.rightVerticalBrightness, isTrue);
    expect(o.gesture.hSeekSpanPerScreen, const Duration(seconds: 90));
    expect(o.gesture.doubleTapStep, const Duration(seconds: 10));
    expect(o.abr.stallThreshold, 3);
    expect(o.controls.autoHideDelay, const Duration(seconds: 3));
    expect(o.live.seekMode, VmLiveSeekMode.off);
  });

  test('VmStrings.fitLabel covers every VmFit value', () {
    const s = VmStrings();
    for (final f in VmFit.values) {
      expect(s.fitLabel(f), isNotEmpty);
    }
    expect(s.fitLabel(VmFit.contain), '适应');
  });

  test('VmStrings can be replaced wholesale for localisation', () {
    const s = VmStrings(fitContain: 'Fit', live: 'ON AIR');
    expect(s.fitLabel(VmFit.contain), 'Fit');
    expect(s.live, 'ON AIR');
  });

  test('VmOptions.copyWith replaces one section only', () {
    const o = VmOptions();
    final n = o.copyWith(controls: const VmControlsConfig(autoHide: false));
    expect(n.controls.autoHide, isFalse);
    expect(n.gesture, o.gesture);
  });

  test('VmPreviewConfig defaults match DESIGN section 6.1', () {
    const p = VmPreviewConfig();
    expect(p.enabled, isTrue);
    expect(p.network, VmPreviewNetwork.wifiOnly);
    expect(p.onBlocked, isNull);
    expect(p.sources, isNull, reason: 'null means the built-in [vtt, extract] chain');
    expect(p.vttEnabled, isTrue);
    expect(p.vttUrl, isNull);
    expect(p.vttUrlResolver, isNull);
    expect(p.extractFallback, isTrue);
    expect(p.extractPlatforms, VmPlatformKind.values.toSet());
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

  test('VmOptions exposes a preview section that defaults to VmPreviewConfig', () {
    const o = VmOptions();
    expect(o.preview, const VmPreviewConfig());
  });

  test('VmOptions.copyWith replaces only the preview section', () {
    const o = VmOptions();
    final n = o.copyWith(preview: const VmPreviewConfig(frameWidth: 320));
    expect(n.preview.frameWidth, 320);
    expect(n.gesture, o.gesture);
    expect(n.controls, o.controls);
    expect(n, isNot(o));
  });

  test('VmPreviewConfig.copyWith replaces one knob and compares by value', () {
    const p = VmPreviewConfig();
    final n = p.copyWith(network: VmPreviewNetwork.never);
    expect(n.network, VmPreviewNetwork.never);
    expect(n.frameWidth, p.frameWidth);
    expect(n, isNot(p));
    expect(p.copyWith(), p);
  });

  test('every VmPreviewConfig injection point accepts a custom strategy', () {
    final p = VmPreviewConfig(
      probe: AlwaysAllowNetProbe(),
      cacheKeyBuilder: (s, b, w) => 'custom',
      vttUrlResolver: (s) => Uri.parse('https://cdn/t.vtt'),
      onBlocked: (_) {},
      extractPlatforms: const {VmPlatformKind.windows},
    );
    expect(p.probe, isA<VmNetProbe>());
    expect(p.cacheKeyBuilder!('a', 1, 2), 'custom');
    expect(p.vttUrlResolver!(const VmSource('x')), Uri.parse('https://cdn/t.vtt'));
    expect(p.onBlocked, isNotNull);
    expect(p.extractPlatforms, {VmPlatformKind.windows});
  });

  test('VmLiveConfig defaults keep 0.1.0 behaviour and add the new knobs off', () {
    const c = VmLiveConfig();
    expect(c.seekMode, VmLiveSeekMode.off);
    expect(c.dvrWindow, isNull);
    expect(c.edgeThreshold, const Duration(seconds: 10));
    expect(c.urlBuilder, isNull);
    expect(c.backToLive, isNull);
    expect(c.autoBackToLiveOnStall, isFalse);
    expect(c.windowResolver, isNull);
  });

  test('effectiveBackToLive derives from seekMode when not configured', () {
    expect(const VmLiveConfig(seekMode: VmLiveSeekMode.dvr).effectiveBackToLive,
        VmBackToLive.seekEnd);
    expect(const VmLiveConfig(seekMode: VmLiveSeekMode.timeshift).effectiveBackToLive,
        VmBackToLive.reopen);
    expect(const VmLiveConfig().effectiveBackToLive, VmBackToLive.seekEnd);
  });

  test('an explicit backToLive overrides the derived default', () {
    const c = VmLiveConfig(
      seekMode: VmLiveSeekMode.timeshift,
      backToLive: VmBackToLive.seekEnd,
    );
    expect(c.effectiveBackToLive, VmBackToLive.seekEnd);
  });

  test('urlBuilder and windowResolver are injectable strategies', () {
    final c = VmLiveConfig(
      seekMode: VmLiveSeekMode.timeshift,
      urlBuilder: (uri, behind, at) => '$uri?behind=${behind.inSeconds}',
      windowResolver: (s) => const Duration(minutes: 30),
    );
    expect(
      c.urlBuilder!('https://h/l.m3u8', const Duration(seconds: 60), DateTime(2026)),
      'https://h/l.m3u8?behind=60',
    );
    expect(c.windowResolver!(const VmState()), const Duration(minutes: 30));
  });

  test('VmLiveConfig.copyWith replaces one field only', () {
    const c = VmLiveConfig(seekMode: VmLiveSeekMode.dvr);
    final n = c.copyWith(autoBackToLiveOnStall: true);
    expect(n.autoBackToLiveOnStall, isTrue);
    expect(n.seekMode, VmLiveSeekMode.dvr);
    expect(n.edgeThreshold, c.edgeThreshold);
  });
}
