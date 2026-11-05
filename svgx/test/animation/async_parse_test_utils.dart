import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/src/animation/svg_document_cache.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/timeline_events.dart';

/// Fails native loading only inside the worker. / 仅让 worker 内原生加载失败。
const missingAsyncWorkerLibrary = 'svgx_missing_worker_library.dll';

/// Small finite animated source. / 小型有限动画源。
const smallAsyncSvg =
    '<svg width="100" height="100"><rect width="20" height="20">'
    '<animate id="a" attributeName="x" values="0;50" dur="2s" '
    'repeatCount="2" fill="freeze"/></rect></svg>';

/// Builds a large image-free tree with native values, SMIL and CSS events.
/// 生成含原生取值、SMIL 和 CSS 事件的无图片大树。
String largeAsyncSvg({String extra = '', String duration = '2s'}) {
  final shapes = List.generate(
    documentParseWorkerNodeThreshold + 1,
    (i) =>
        '<rect id="r$i" x="${i % 90}" y="${i % 80}" '
        'width="3" height="3" fill="cornflowerblue" '
        'transform="translate(1,2)"/>',
  ).join();
  return '<svg width="100" height="100"><defs><linearGradient id="g">'
      '<stop offset="0" stop-color="cornflowerblue"/>'
      '<stop offset="1" stop-color="red"/></linearGradient></defs>'
      '<style>@keyframes fade{from{opacity:0.2}to{opacity:1}}'
      '#css{animation:fade 1s 3 forwards}</style>$shapes'
      '<rect id="css" width="10" height="10" fill="url(#g)"/>'
      '<rect width="20" height="20"><animate id="a" '
      'attributeName="x" values="0;50" dur="$duration" repeatCount="2" '
      'fill="freeze"/><animate id="b" attributeName="y" values="0;30" '
      'dur="1s" begin="a.end" fill="freeze"/></rect>$extra</svg>';
}

/// Large malformed XML, including the UI diagnostic as ordinary text.
/// 大型坏 XML，含作为普通文本的 UI 诊断，验证错误不会误分类。
String invalidLargeAsyncSvg() =>
    '<svg>${List.generate(documentParseWorkerNodeThreshold, (_) => '<g/>').join()}'
    'UI actions are only available on root isolate<rect></svg>';

/// Converts compound motion/list samples into comparable data.
/// 把运动、列表等复合采样值转为可比较的数据。
Object? normalizeAsyncSample(Object? value) {
  if (value is SmilMotionSample) {
    return [value.x, value.y, value.angleDegrees];
  }
  if (value is List) return value.map(normalizeAsyncSample).toList();
  return value;
}

/// Samples every timeline at one time. / 在某时刻采样全部时间线。
List<Object?> asyncSamples(SvgDocument document, Duration time) => [
  for (final timeline in document.timelines)
    normalizeAsyncSample((timeline as dynamic).sample(time)),
];

/// Extracts comparable event data, extending lazy interval resolvers.
/// 提取可比较事件数据，同时扩展惰性区间解析器。
List<Object?> asyncEvents(SvgDocument document) => [
  for (final event in timelineEventsBetween(
    document,
    const Duration(microseconds: -1),
    const Duration(seconds: 70),
  ))
    [event.elementId, event.kind, event.time, event.iteration],
];
