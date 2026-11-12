import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/document_parse_worker.dart';
import 'package:xvg/src/animation/svg_document_cache.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/xvg.dart' show RustLib;
import 'package:xml/xml.dart';

import 'async_parse_test_utils.dart';
import 'pixel_test_utils.dart';

/// Times spanning active animation, syncbase activation and settled frames.
/// 覆盖活动动画、syncbase 激活和定格的采样时刻。
const _times = [0, 500, 1500, 4100, 65000];

/// Payload size exceeding the former length cutoff. / 超过旧长度阈值的载荷大小。
const _longPayloadLength = 70 * 1024;

/// Short injected cooldown; no real-time sleeps needed. / 注入短冷却期，无须真实等待。
const _testWorkerCooldown = Duration(seconds: 10);

/// Offset used to check both sides of cooldown expiry. / 检查冷却到期两侧的时间步长。
const _cooldownBoundaryStep = Duration(milliseconds: 1);

/// Compares metadata, samples, events and exact RGBA bytes.
/// 比较元信息、采样、事件及精确 RGBA 字节。
Future<void> _expectEquivalent(SvgDocument actual, SvgDocument expected) async {
  expect(actual.info, expected.info);
  expect((actual.width, actual.height), (expected.width, expected.height));
  expect(actual.timelines.length, expected.timelines.length);
  expect(asyncEvents(actual), asyncEvents(expected));
  for (final ms in _times) {
    final time = Duration(milliseconds: ms);
    expect(asyncSamples(actual, time), asyncSamples(expected, time));
    final actualPixels = await renderAt(actual, time);
    final expectedPixels = await renderAt(expected, time);
    expect(
      actualPixels.buffer.asUint8List(),
      expectedPixels.buffer.asUint8List(),
    );
  }
}

/// Native-backed async cache contracts. / 带原生库的异步缓存契约。
void main() {
  final cache = XvgDocumentCache.instance;
  final worker = DocumentParseWorker.instance;
  setUpAll(RustLib.init);
  setUp(cache.debugResetAsyncParsing);
  tearDown(cache.debugResetAsyncParsing);

  test('opening tag estimate handles XML syntax and self-closing tags', () {
    expect(estimateDocumentParseNodeCount(''), 0);
    expect(estimateDocumentParseNodeCount('<'), 0);
    expect(estimateDocumentParseNodeCount('</x><?xml version="1.0"?>'), 0);
    expect(
      estimateDocumentParseNodeCount(
        '<!-- comment --><!DOCTYPE svg><![CDATA[plain text]]>',
      ),
      0,
    );
    expect(
      estimateDocumentParseNodeCount('<svg><x/><Y /><ns:z></ns:z></svg>'),
      4,
    );
    // Deliberate approximation: embedded pseudo-tags can overcount.
    // 有意的近似：注释或 CDATA 中的伪标签允许多计。
    expect(estimateDocumentParseNodeCount('<!-- <x/> --><![CDATA[<y/>]]>'), 2);
    expect(
      estimateDocumentParseNodeCount(smallAsyncSvg),
      lessThan(documentParseWorkerNodeThreshold),
    );
  });

  test('long text and path data with few tags complete inline', () async {
    final payload = List.filled(_longPayloadLength, '0 ').join();
    for (final source in [
      '<svg><text>$payload</text></svg>',
      '<svg><path d="M0 0 L$payload"/></svg>',
    ]) {
      expect(source.length, greaterThan(_longPayloadLength));
      expect(estimateDocumentParseNodeCount(source), 2);
      var inline = false;
      final parsed = cache.getOrParseAsync(source);
      parsed.then((_) => inline = true);
      expect(inline, isTrue);
      expect((await parsed).hasImages, isFalse);
    }
    expect(worker.debugStartCount, 0);
    expect(worker.debugRequestCount, 0);
  });

  test('short trees switch to worker exactly at the tag threshold', () async {
    for (final count in [
      documentParseWorkerNodeThreshold - 1,
      documentParseWorkerNodeThreshold,
    ]) {
      final source =
          '<svg>${List.generate(count - 1, (_) => '<g/>').join()}</svg>';
      expect(estimateDocumentParseNodeCount(source), count);
      expect(source.length, lessThan(_longPayloadLength));
      var inline = false;
      final parsed = cache.getOrParseAsync(source);
      parsed.then((_) => inline = true);
      expect(inline, count < documentParseWorkerNodeThreshold);
      await parsed;
    }
    expect(worker.debugStartCount, 1);
    expect(worker.debugRequestCount, 1);
  });

  test(
    'small source and cache hits complete inline without a worker',
    () async {
      var completed = false;
      final first = cache.getOrParseAsync(smallAsyncSvg);
      first.then((_) => completed = true);
      expect(completed, isTrue);
      expect(
        (await first).document,
        same(cache.getOrParse(smallAsyncSvg).document),
      );
      expect(worker.debugStartCount, 0);

      final source = largeAsyncSvg();
      final sync = cache.getOrParse(source);
      completed = false;
      final hit = cache.getOrParseAsync(source);
      hit.then((value) {
        completed = true;
        expect(value.document, same(sync.document));
      });
      expect(completed, isTrue);
      expect(worker.debugRequestCount, 0);
    },
  );

  test(
    'large source uses worker with equivalent native values and RGBA',
    () async {
      final source = largeAsyncSvg();
      expect(
        estimateDocumentParseNodeCount(source),
        greaterThan(documentParseWorkerNodeThreshold),
      );
      final parsed = await cache.getOrParseAsync(source);
      expect(worker.debugStartCount, 1);
      expect(worker.debugRequestCount, 1);
      expect(parsed.hasImages, isFalse);
      final sync = parseAnimatedSvgDocument(source);
      expect(parsed.document.root.children.first.transform, [
        1.0,
        0.0,
        0.0,
        1.0,
        1.0,
        2.0,
      ]);
      expect(
        parsed.document.gradients['g']!.stops.first.color,
        const Color(0xFF6495ED),
      );
      await _expectEquivalent(parsed.document, sync);
      expect(cache.getOrParse(source).document, same(parsed.document));
      // The root has now cached ui.Path; a cache hit must never send it back.
      // 主线程此时已缓存 ui.Path，缓存命中不得把它再发往 worker。
      expect(
        (await cache.getOrParseAsync(source)).document,
        same(parsed.document),
      );
      expect(worker.debugRequestCount, 1);
    },
  );

  for (final motion in [
    '<rect width="10" height="10"><animateMotion path="M0 0 L80 80" '
        'dur="2s"/></rect>',
    '<style>@keyframes travel{from{offset-distance:0%}'
        'to{offset-distance:100%}}#m{offset-path:path("M0 0 L80 80");'
        'animation:travel 2s forwards}</style>'
        '<rect id="m" width="10" height="10"/>',
  ]) {
    test(
      'root-only motion falls back and survives document eviction: $motion',
      () async {
        final source = largeAsyncSvg(extra: motion);
        final parsed = await cache.getOrParseAsync(source);
        expect(worker.debugRequestCount, 1);
        await _expectEquivalent(
          parsed.document,
          parseAnimatedSvgDocument(source),
        );
        cache.clear();
        var inline = false;
        final again = cache.getOrParseAsync(source);
        again.then((_) => inline = true);
        expect(inline, isTrue);
        expect(worker.debugRequestCount, 1);
        expect((await again).document.info, parsed.document.info);
      },
    );
  }

  test(
    'bad XML preserves its exception and does not poison subsequent work',
    () async {
      final source = invalidLargeAsyncSvg();
      for (var i = 0; i < 2; i++) {
        await expectLater(
          cache.getOrParseAsync(source),
          throwsA(isA<XmlException>()),
        );
      }
      expect(worker.debugRequestCount, 2);
      expect(worker.debugStartCount, 1);
      expect(cache.length, 0);
      await cache.getOrParseAsync(largeAsyncSvg());
      expect(cache.length, 1);
    },
  );

  test(
    'same-source concurrency shares one future; distinct requests queue',
    () async {
      final source = largeAsyncSvg();
      final a = cache.getOrParseAsync(source);
      final b = cache.getOrParseAsync(source);
      final c = cache.getOrParseAsync(largeAsyncSvg(duration: '3s'));
      expect(a, same(b));
      final results = await Future.wait([a, b, c]);
      expect(results[0].document, same(results[1].document));
      expect(results[2].document.info, isNot(results[0].document.info));
      expect(worker.debugStartCount, 1);
      expect(worker.debugRequestCount, 2);
    },
  );

  test(
    'unexpected exit falls back for queued requests and immediately rebuilds',
    () async {
      // Start native initialization fully before killing a resident worker.
      // 完成原生初始化后再强杀常驻 worker，覆盖运行中的意外退出。
      await cache.getOrParseAsync(largeAsyncSvg(duration: '4s'));
      cache.clear();
      final a = cache.getOrParseAsync(largeAsyncSvg());
      final b = cache.getOrParseAsync(largeAsyncSvg(duration: '3s'));
      final results = Future.wait([a, b]);
      await worker.debugKill();
      final parsed = await results;
      expect(
        parsed[0].document.info.naturalDuration,
        const Duration(seconds: 5),
      );
      expect(
        parsed[1].document.info.naturalDuration,
        const Duration(seconds: 7),
      );
      expect(cache.length, 2);
      // Use a distinct source so a cache hit cannot hide an unwanted cooldown.
      // 使用新源，避免缓存命中掩盖意外进入冷却的问题。
      await cache.getOrParseAsync(largeAsyncSvg(duration: '4s'));
      expect(worker.debugStartCount, 2);
      expect(cache.length, 3);
    },
  );

  test('clearing during parse does not refill a cleared cache', () async {
    final parsed = cache.getOrParseAsync(largeAsyncSvg());
    cache.clear();
    await parsed;
    expect(cache.length, 0);
  });

  test(
    'native initialization failure falls back once and retries after cooldown',
    () async {
      var now = DateTime.utc(2026, 11, 5);
      cache.debugWorkerClock = () => now;
      cache.debugWorkerCooldown = _testWorkerCooldown;
      final diagnostics = <String?>[];
      final previousPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          diagnostics.add(message);
      addTearDown(() => debugPrint = previousPrint);
      worker.debugNativeLibraryPath = missingAsyncWorkerLibrary;
      final a = cache.getOrParseAsync(largeAsyncSvg());
      final b = cache.getOrParseAsync(largeAsyncSvg(duration: '3s'));
      final parsed = await Future.wait([a, b]);
      expect(parsed.every((value) => !value.hasImages), isTrue);
      expect(cache.length, 2);
      expect(worker.debugStartCount, 1);
      expect(worker.debugRequestCount, 2);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single, contains('initialization'));
      expect(diagnostics.single, contains(missingAsyncWorkerLibrary));
      expect(diagnostics.single, contains('falling back'));
      expect(diagnostics.single, isNot(contains('\n')));
      expect(diagnostics.single, isNot(contains('\r')));

      now = now.add(_testWorkerCooldown - _cooldownBoundaryStep);
      worker.debugNativeLibraryPath = null;
      cache.clear();
      var inline = false;
      final cooling = cache.getOrParseAsync(largeAsyncSvg());
      cooling.then((_) => inline = true);
      expect(inline, isTrue);
      await cooling;
      expect(worker.debugStartCount, 1);
      expect(worker.debugRequestCount, 2);

      now = now.add(_cooldownBoundaryStep);
      await cache.getOrParseAsync(largeAsyncSvg(duration: '4s'));
      expect(worker.debugStartCount, 2);
      expect(worker.debugRequestCount, 3);
      expect(cache.length, 2);
      expect(diagnostics, hasLength(1));
    },
  );

  test(
    'worker initialization errors retain their type, phase and cause',
    () async {
      worker.debugNativeLibraryPath = missingAsyncWorkerLibrary;
      await expectLater(
        worker.parse(largeAsyncSvg()),
        throwsA(
          isA<DocumentParseWorkerUnavailable>()
              .having(
                (error) => error.kind,
                'kind',
                DocumentParseWorkerFailureKind.initialization,
              )
              .having((error) => error.shouldCooldown, 'shouldCooldown', isTrue)
              .having(
                (error) => error.cause.toString(),
                'cause',
                contains(missingAsyncWorkerLibrary),
              ),
        ),
      );
    },
  );

  test(
    'fallback still reports malformed XML and keeps startup cooldown',
    () async {
      worker.debugNativeLibraryPath = missingAsyncWorkerLibrary;
      await expectLater(
        cache.getOrParseAsync(invalidLargeAsyncSvg()),
        throwsA(isA<XmlException>()),
      );
      final parsed = await cache.getOrParseAsync(largeAsyncSvg());
      expect(parsed.hasImages, isFalse);
      expect(worker.debugStartCount, 1);
      expect(cache.length, 1);
    },
  );

  test('fallback after clear does not refill a cleared cache', () async {
    worker.debugNativeLibraryPath = missingAsyncWorkerLibrary;
    final parsed = cache.getOrParseAsync(largeAsyncSvg());
    cache.clear();
    expect((await parsed).hasImages, isFalse);
    expect(cache.length, 0);
  });

  test(
    'disposal during startup falls back and waits for all ports to close',
    () async {
      final parsed = cache.getOrParseAsync(largeAsyncSvg());
      await cache.debugResetAsyncParsing();
      expect((await parsed).hasImages, isFalse);
      expect(cache.length, 0);
      await cache.getOrParseAsync(largeAsyncSvg());
      expect(worker.debugStartCount, 1);
    },
  );

  test('large images bypass worker, remain uncached and unshared', () async {
    final source = largeAsyncSvg(
      extra:
          '<image width="1" height="1" href="data:image/png;base64,unused"/>',
    );
    final a = await cache.getOrParseAsync(source);
    final b = await cache.getOrParseAsync(source);
    expect(a.hasImages, isTrue);
    expect(b.document, isNot(same(a.document)));
    expect(cache.length, 0);
    expect(worker.debugStartCount, 0);
  });

  test('large namespaced images complete inline without a worker', () async {
    final source = largeAsyncSvg(
      extra:
          '<svg:image xmlns:svg="http://www.w3.org/2000/svg" '
          'width="1" height="1" href="data:image/png;base64,unused"/>',
    );
    var inline = false;
    final parsed = cache.getOrParseAsync(source);
    parsed.then((_) => inline = true);
    expect(inline, isTrue);
    expect((await parsed).hasImages, isTrue);
    expect(cache.length, 0);
    expect(worker.debugStartCount, 0);
    expect(worker.debugRequestCount, 0);
  });

  test(
    'prewarm ignores failures, continues and retains normal cache limits',
    () async {
      final previous = cache.maximumSize;
      addTearDown(() => cache.maximumSize = previous);
      cache.maximumSize = 1;
      await cache.prewarm([
        invalidLargeAsyncSvg(),
        smallAsyncSvg,
        largeAsyncSvg(),
      ]);
      expect(cache.length, 1);
      final count = worker.debugRequestCount;
      await cache.getOrParseAsync(largeAsyncSvg());
      expect(worker.debugRequestCount, count);
    },
  );
}
