// A row-by-row audit of DESIGN-0.2.0 section 6.1: every decision videoman
// makes for the user must ship a default, a config knob, and — when the
// decision is a strategy — an injection point. This test fails loudly if a
// later change drops any of the three.
//
// 对 DESIGN-0.2.0 §6.1 的逐行对账：videoman 替用户做的每个决策都必须同时提供
// 默认值、配置项，以及（当该决策是策略时）注入点。后续改动若丢掉三者之一，
// 本测试会直接失败。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/model/source.dart';
import 'package:videoman/src/core/options/options.dart';
import 'package:videoman/src/core/preview/cache.dart';
import 'package:videoman/src/core/preview/dir_provider.dart';
import 'package:videoman/src/core/preview/extractor.dart';
import 'package:videoman/src/core/preview/models.dart';
import 'package:videoman/src/core/preview/net_probe.dart';
import 'package:videoman/src/core/preview/platform_kind.dart';
import 'package:videoman/src/core/preview/source.dart';
import 'package:videoman/src/ui/components/preview.dart';
import 'package:videoman/src/ui/skins/default_skin.dart';
import 'package:videoman/src/ui/slots/patch.dart';

/// A minimal [VmThumbSource] used to prove the source chain is replaceable.
///
/// 用于证明来源链可替换的最小 [VmThumbSource]。
class _NullSource implements VmThumbSource {
  @override
  String get name => 'null';

  @override
  Future<VmThumb?> thumbAt(VmSource source, Duration bucket) async => null;

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {}
}

/// A minimal [VmThumbCache] used to prove the cache is replaceable.
///
/// 用于证明缓存可替换的最小 [VmThumbCache]。
class _NullCache implements VmThumbCache {
  @override
  Uint8List? peek(String key) => null;

  @override
  Future<Uint8List?> read(String key) async => null;

  @override
  Future<void> write(String key, Uint8List bytes) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}

/// A minimal [VmFrameExtractor] used to prove extraction is replaceable.
///
/// 用于证明抽帧可替换的最小 [VmFrameExtractor]。
class _NullExtractor implements VmFrameExtractor {
  @override
  Future<Uint8List?> extract(
    String uri,
    Duration at, {
    required int width,
    required bool hwdec,
  }) async =>
      null;

  @override
  Future<void> release() async {}

  @override
  Future<void> dispose() async {}
}

void main() {
  group('DESIGN 6.1 row: network policy', () {
    test('default is wifiOnly, knob is network, strategy is probe', () {
      expect(const VmPreviewConfig().network, VmPreviewNetwork.wifiOnly);
      expect(
        const VmPreviewConfig(network: VmPreviewNetwork.never).network,
        VmPreviewNetwork.never,
      );
      expect(VmPreviewConfig(probe: AlwaysAllowNetProbe()).probe, isA<VmNetProbe>());
    });
  });

  group('DESIGN 6.1 row: blocked notification', () {
    test('default is silence, strategy is onBlocked', () {
      expect(const VmPreviewConfig().onBlocked, isNull);
      var seen = false;
      VmPreviewConfig(onBlocked: (_) => seen = true).onBlocked!(
        VmPreviewBlockReason.network,
      );
      expect(seen, isTrue);
    });
  });

  group('DESIGN 6.1 row: thumbnail sources', () {
    test('default chain is implicit, knob is vttEnabled/extractFallback, strategy is sources', () {
      const d = VmPreviewConfig();
      expect(d.sources, isNull, reason: 'null means the built-in [vtt, extract] chain');
      expect(d.vttEnabled, isTrue);
      expect(d.extractFallback, isTrue);
      expect(const VmPreviewConfig(vttEnabled: false).vttEnabled, isFalse);
      expect(const VmPreviewConfig(extractFallback: false).extractFallback, isFalse);
      expect(VmPreviewConfig(sources: [_NullSource()]).sources, hasLength(1));
    });
  });

  group('DESIGN 6.1 row: vtt url', () {
    test('default is the .vtt convention, knob is vttUrl, strategy is vttUrlResolver', () {
      expect(const VmPreviewConfig().vttUrl, isNull);
      expect(const VmPreviewConfig(vttUrl: 'https://cdn/t.vtt').vttUrl, 'https://cdn/t.vtt');
      final cfg = VmPreviewConfig(vttUrlResolver: (_) => Uri.parse('https://cdn/x.vtt'));
      expect(cfg.vttUrlResolver!(const VmSource('a')), Uri.parse('https://cdn/x.vtt'));
    });
  });

  group('DESIGN 6.1 row: extraction fallback', () {
    test('default on, knobs are extractFallback/extractPlatforms, strategy is extractor', () {
      const d = VmPreviewConfig();
      expect(d.extractFallback, isTrue);
      expect(d.extractPlatforms, VmPlatformKind.values.toSet());
      expect(
        const VmPreviewConfig(extractPlatforms: {VmPlatformKind.windows}).extractPlatforms,
        {VmPlatformKind.windows},
      );
      expect(VmPreviewConfig(extractor: _NullExtractor()).extractor, isA<VmFrameExtractor>());
    });
  });

  group('DESIGN 6.1 row: frame width / bucket / hwdec', () {
    test('defaults are 160px, 10s and software decoding, each configurable', () {
      const d = VmPreviewConfig();
      expect(d.frameWidth, 160);
      expect(d.bucket, const Duration(seconds: 10));
      expect(d.hwdec, isFalse);
      const c = VmPreviewConfig(
        frameWidth: 320,
        bucket: Duration(seconds: 5),
        hwdec: true,
      );
      expect(c.frameWidth, 320);
      expect(c.bucket, const Duration(seconds: 5));
      expect(c.hwdec, isTrue);
    });
  });

  group('DESIGN 6.1 row: memory ceiling', () {
    test('default 40 entries, knob memMaxEntries, strategy cache', () {
      expect(const VmPreviewConfig().memMaxEntries, 40);
      expect(const VmPreviewConfig(memMaxEntries: 5).memMaxEntries, 5);
      expect(VmPreviewConfig(cache: _NullCache()).cache, isA<VmThumbCache>());
    });
  });

  group('DESIGN 6.1 row: disk ceiling and directory', () {
    test('defaults 64MB and temp dir, knobs diskMaxBytes/diskDir, strategies cache/dirProvider', () {
      const d = VmPreviewConfig();
      expect(d.diskMaxBytes, 64 * 1024 * 1024);
      expect(d.diskDir, isNull, reason: 'null means the platform temp directory');
      expect(const VmPreviewConfig(diskMaxBytes: 1024).diskMaxBytes, 1024);
      expect(const VmPreviewConfig(diskDir: '/tmp/x').diskDir, '/tmp/x');
      expect(
        const VmPreviewConfig(dirProvider: FixedThumbDirProvider('/tmp/y')).dirProvider,
        isA<VmThumbDirProvider>(),
      );
    });
  });

  group('DESIGN 6.1 row: cache key', () {
    test('default is the built-in hash, strategy is cacheKeyBuilder', () {
      expect(const VmPreviewConfig().cacheKeyBuilder, isNull);
      final cfg = VmPreviewConfig(cacheKeyBuilder: (s, b, w) => 'k');
      expect(cfg.cacheKeyBuilder!('a', 1, 2), 'k');
    });
  });

  group('DESIGN 6.1 row: clear on dispose', () {
    test('default on, knob clearOnDispose, strategy cache', () {
      expect(const VmPreviewConfig().clearOnDispose, isTrue);
      expect(const VmPreviewConfig(clearOnDispose: false).clearOnDispose, isFalse);
      expect(VmPreviewConfig(cache: _NullCache()).cache, isA<VmThumbCache>());
    });
  });

  group('DESIGN 6.1 row: request debounce', () {
    test('default 120ms and configurable', () {
      expect(const VmPreviewConfig().debounce, const Duration(milliseconds: 120));
      expect(
        const VmPreviewConfig(debounce: Duration.zero).debounce,
        Duration.zero,
      );
    });
  });

  group('DESIGN 6.1 row: bubble appearance', () {
    test('default component is addressable and replaceable by patch', () {
      expect(PreviewComponent().name, 'preview');
      final patched = VmDefaultSkin(
        patches: [VmPatch.remove('preview')],
      ).components();
      expect(patched.where((c) => c.name == 'preview'), isEmpty);
    });
  });

  test('VmOptions carries the preview section and copyWith keeps it isolated', () {
    const o = VmOptions();
    expect(o.preview, const VmPreviewConfig());
    expect(o.copyWith(preview: const VmPreviewConfig(frameWidth: 99)).gesture, o.gesture);
  });
}
