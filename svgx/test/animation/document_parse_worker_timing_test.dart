import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/svg_document_cache.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/svgx.dart' show RustLib;

/// Timer period used as a root-isolate scheduling probe. / 主 isolate 调度探针周期。
const _probePeriod = Duration(milliseconds: 1);

/// Reports total latency and the largest observed root timer gap.
/// 报告总延迟及观测到的最大主 isolate 定时器间隙。
Future<Map<String, int>> _measure(FutureOr<void> Function() work) async {
  final wall = Stopwatch()..start();
  var previous = wall.elapsedMicroseconds;
  var gap = 0;
  final timer = Timer.periodic(_probePeriod, (_) {
    final now = wall.elapsedMicroseconds;
    final elapsed = now - previous;
    if (elapsed > gap) gap = elapsed;
    previous = now;
  });
  final start = wall.elapsedMicroseconds;
  try {
    await work();
    final latency = wall.elapsedMicroseconds - start;
    // Let the probe observe a synchronous stall before cancelling it.
    // 取消前给探针机会记录同步阻塞。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return {'latencyUs': latency, 'maxRootTimerGapUs': gap};
  } finally {
    timer.cancel();
  }
}

/// Optional local timing experiment; no corpus or generated output in git.
/// 可选本地计时实验，语料及生成结果不入 git。
void main() {
  final sample = Platform.environment['SVGX_ASYNC_PARSE_SAMPLE'];
  test(
    'Windows root scheduling during cold and resident document parsing',
    () async {
      await RustLib.init();
      final cache = SvgxDocumentCache.instance;
      addTearDown(cache.debugResetAsyncParsing);
      final source = File(sample!).readAsStringSync();
      final cold = await _measure(() async {
        await cache.getOrParseAsync(source);
      });
      // Warm both JIT paths, retaining the worker but clearing document hits.
      // 预热两条 JIT 路径，保留 worker 并清空文档命中。
      for (var i = 0; i < 3; i++) {
        parseAnimatedSvgDocument(source);
        cache.clear();
        await cache.getOrParseAsync(source);
      }
      final idle = await _measure(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      final sync = <Map<String, int>>[];
      final async = <Map<String, int>>[];
      for (var i = 0; i < 7; i++) {
        sync.add(
          await _measure(() {
            parseAnimatedSvgDocument(source);
          }),
        );
        cache.clear();
        async.add(
          await _measure(() async {
            await cache.getOrParseAsync(source);
          }),
        );
      }
      final result = {
        'sample': sample,
        'sourceLength': source.length,
        'coldWorker': cold,
        'idle': idle,
        'sync': sync,
        'async': async,
      };
      File(
        '.dart_tool/svgx_async/performance.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
      // ignore: avoid_print
      print(jsonEncode(result));
    },
    skip: sample == null
        ? 'Set SVGX_ASYNC_PARSE_SAMPLE to a local large SVG'
        : false,
  );
}
