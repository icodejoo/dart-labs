// A row-by-row audit of DESIGN-0.2.0 section 6.1: every decision mova
// makes for the user must ship a default, an opts knob, and — when the
// decision is a strategy — an injection point. This test fails loudly if a
// later change drops any of the three.
//
// 对 DESIGN-0.2.0 §6.1 的逐行对账：mova 替用户做的每个决策都必须同时提供
// 默认值、配置项，以及（当该决策是策略时）注入点。后续改动若丢掉三者之一，
// 本测试会直接失败。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';
import 'package:mova/src/core/preview/cache.dart';
import 'package:mova/src/core/preview/dir_provider.dart';
import 'package:mova/src/core/preview/extractor.dart';
import 'package:mova/src/core/preview/models.dart';
import 'package:mova/src/core/preview/net_probe.dart';
import 'package:mova/src/core/preview/platform_kind.dart';
import 'package:mova/src/core/preview/source.dart';
import 'package:mova/src/ui/components/preview.dart';
import 'package:mova/src/ui/ui_kits/default_ui_kit.dart';
import 'package:mova/src/ui/slots/patch.dart';

/// A minimal [IMovaThumbSource] used to prove the source chain is replaceable.
///
/// 用于证明来源链可替换的最小 [IMovaThumbSource]。
class _NullSource implements IMovaThumbSource {
  @override
  String get name => 'null';

  @override
  Future<MovaThumb?> thumbAt(MovaSource source, Duration bucket) async => null;

  @override
  Future<void> reset() async {}

  @override
  Future<void> dispose() async {}
}

/// A minimal [IMovaThumbCache] used to prove the cache is replaceable.
///
/// 用于证明缓存可替换的最小 [IMovaThumbCache]。
class _NullCache implements IMovaThumbCache {
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

/// A minimal [IMovaFramePuller] used to prove extraction is replaceable.
///
/// 用于证明抽帧可替换的最小 [IMovaFramePuller]。
class _NullExtractor implements IMovaFramePuller {
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
      expect(const MovaPreviewOpts().network, MovaPreviewNet.wifiOnly);
      expect(
        const MovaPreviewOpts(network: MovaPreviewNet.never).network,
        MovaPreviewNet.never,
      );
      expect(MovaPreviewOpts(probe: MovaAlwaysAllowNetProbe()).probe, isA<IMovaNetProbe>());
    });
  });

  group('DESIGN 6.1 row: blocked notification', () {
    test('default is silence, strategy is onBlocked', () {
      expect(const MovaPreviewOpts().onBlocked, isNull);
      var seen = false;
      MovaPreviewOpts(onBlocked: (_) => seen = true).onBlocked!(
        MovaPreviewBlockReason.network,
      );
      expect(seen, isTrue);
    });
  });

  group('DESIGN 6.1 row: thumbnail sources', () {
    test('default chain is implicit, knob is vttEnabled/extractFallback, strategy is sources', () {
      const d = MovaPreviewOpts();
      expect(d.sources, isNull, reason: 'null means the built-in [vtt, extract] chain');
      expect(d.vttEnabled, isTrue);
      expect(d.extractFallback, isTrue);
      expect(const MovaPreviewOpts(vttEnabled: false).vttEnabled, isFalse);
      expect(const MovaPreviewOpts(extractFallback: false).extractFallback, isFalse);
      expect(MovaPreviewOpts(sources: [_NullSource()]).sources, hasLength(1));
    });
  });

  group('DESIGN 6.1 row: vtt url', () {
    test('default is the .vtt convention, knob is vttUrl, strategy is vttUrlResolver', () {
      expect(const MovaPreviewOpts().vttUrl, isNull);
      expect(const MovaPreviewOpts(vttUrl: 'https://cdn/t.vtt').vttUrl, 'https://cdn/t.vtt');
      final opts = MovaPreviewOpts(vttUrlResolver: (_) => Uri.parse('https://cdn/x.vtt'));
      expect(opts.vttUrlResolver!(const MovaSource('a')), Uri.parse('https://cdn/x.vtt'));
    });
  });

  group('DESIGN 6.1 row: extraction fallback', () {
    test('default on, knobs are extractFallback/extractPlatforms, strategy is extractor', () {
      const d = MovaPreviewOpts();
      expect(d.extractFallback, isTrue);
      expect(d.extractPlatforms, MovaPlatformKind.values.toSet());
      expect(
        const MovaPreviewOpts(extractPlatforms: {MovaPlatformKind.windows}).extractPlatforms,
        {MovaPlatformKind.windows},
      );
      expect(MovaPreviewOpts(extractor: _NullExtractor()).extractor, isA<IMovaFramePuller>());
    });
  });

  group('DESIGN 6.1 row: frame width / bucket / hwdec', () {
    test('defaults are 160px, 10s and software decoding, each configurable', () {
      const d = MovaPreviewOpts();
      expect(d.frameWidth, 160);
      expect(d.bucket, const Duration(seconds: 10));
      expect(d.hwdec, isFalse);
      const c = MovaPreviewOpts(
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
      expect(const MovaPreviewOpts().memMaxEntries, 40);
      expect(const MovaPreviewOpts(memMaxEntries: 5).memMaxEntries, 5);
      expect(MovaPreviewOpts(cache: _NullCache()).cache, isA<IMovaThumbCache>());
    });
  });

  group('DESIGN 6.1 row: disk ceiling and directory', () {
    test('defaults 64MB and temp dir, knobs diskMaxBytes/diskDir, strategies cache/dirProvider', () {
      const d = MovaPreviewOpts();
      expect(d.diskMaxBytes, 64 * 1024 * 1024);
      expect(d.diskDir, isNull, reason: 'null means the platform temp directory');
      expect(const MovaPreviewOpts(diskMaxBytes: 1024).diskMaxBytes, 1024);
      expect(const MovaPreviewOpts(diskDir: '/tmp/x').diskDir, '/tmp/x');
      expect(
        const MovaPreviewOpts(dirProvider: MovaFixedThumbDirProvider('/tmp/y')).dirProvider,
        isA<IMovaThumbDirProvider>(),
      );
    });
  });

  group('DESIGN 6.1 row: cache key', () {
    test('default is the built-in hash, strategy is cacheKeyBuilder', () {
      expect(const MovaPreviewOpts().cacheKeyBuilder, isNull);
      final opts = MovaPreviewOpts(cacheKeyBuilder: (s, b, w) => 'k');
      expect(opts.cacheKeyBuilder!('a', 1, 2), 'k');
    });
  });

  group('DESIGN 6.1 row: clear on dispose', () {
    test('default on, knob clearOnDispose, strategy cache', () {
      expect(const MovaPreviewOpts().clearOnDispose, isTrue);
      expect(const MovaPreviewOpts(clearOnDispose: false).clearOnDispose, isFalse);
      expect(MovaPreviewOpts(cache: _NullCache()).cache, isA<IMovaThumbCache>());
    });
  });

  group('DESIGN 6.1 row: request debounce', () {
    test('default 120ms and configurable', () {
      expect(const MovaPreviewOpts().debounce, const Duration(milliseconds: 120));
      expect(
        const MovaPreviewOpts(debounce: Duration.zero).debounce,
        Duration.zero,
      );
    });
  });

  group('DESIGN 6.1 row: bubble appearance', () {
    test('default component is addressable and replaceable by patch', () {
      expect(MovaPreviewComponent().name, 'preview');
      final patched = MovaDefaultUiKit(
        patches: [MovaPatch.remove('preview')],
      ).components();
      expect(patched.where((c) => c.name == 'preview'), isEmpty);
    });
  });

  test('MovaOpts carries the preview section and copyWith keeps it isolated', () {
    const o = MovaOpts();
    expect(o.preview, const MovaPreviewOpts());
    expect(o.copyWith(preview: const MovaPreviewOpts(frameWidth: 99)).gesture, o.gesture);
  });
}
