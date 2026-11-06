import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/timeline_events.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// Shared event kinds. / 共用事件类型。
const _begin = XvgTimelineEventKind.begin,
    _repeat = XvgTimelineEventKind.repeat,
    _end = XvgTimelineEventKind.end;

/// Origin including time-zero events. / 包含零时刻事件的查询起点。
const _beforeZero = Duration(microseconds: -1);

/// Identifiers reused by fixtures. / 样例共用标识。
const _name = 'pulse', _otherName = 'move', _follower = 'follower';

/// Three one-second iterations. / 三轮一秒的动画声明。
const _threeIterations = '$_name 1s linear 3';

/// Scalar opacity keyframes. / 标量透明度关键帧。
const _opacityFrames = 'from{opacity:0}to{opacity:1}';

/// Three transform slots in one animation. / 一个动画中的三个变换槽位。
const _transformFrames =
    'from{transform:translate(0px) rotate(0deg) scale(1)}'
    'to{transform:translate(10px) rotate(90deg) scale(2)}';

/// All six supported channel types. / 全部六类受支持通道。
const _allFrames = '''
from {transform:translate(0px) rotate(0deg) scale(1);opacity:0;
stroke-width:1;fill:#000;stroke-dasharray:1 2;d:path('M0 0L10 0');offset-distance:0%}
to {transform:translate(10px) rotate(90deg) scale(2);opacity:1;
stroke-width:2;fill:#fff;stroke-dasharray:2 4;d:path('M0 0L20 0');offset-distance:100%}
''';

/// Integer-second document time. / 整秒文档时间。
Duration _seconds(int value) => Duration(seconds: value);

/// One element with a CSS animation list. / 带 CSS 动画列表的单个元素。
String _shape(String animation) =>
    '<path d="M0 0L10 0" style="offset-path:path(\'M0 0L10 0\');'
    'animation:$animation"/>';

/// Parses CSS fixtures, optionally with additional elements or keyframes.
/// 解析 CSS 样例，可附加元素和关键帧。
SvgDocument _document(
  String animation, {
  String frames = _opacityFrames,
  String extra = '',
  String extraFrames = '',
}) => parseAnimatedSvgDocument(
  '<svg><style>@keyframes $_name {$frames}$extraFrames</style>'
  '${_shape(animation)}$extra</svg>',
);

/// Comparable event values without channel details. / 不含通道细节的事件值。
List<(String, XvgTimelineEventKind, Duration, int)> _events(
  SvgDocument document,
  Duration from,
  Duration to,
) => [
  for (final event in timelineEventsBetween(document, from, to))
    (event.elementId, event.kind, event.time, event.iteration),
];

/// Expected lifecycle for three one-second iterations. / 三轮一秒动画的预期事件。
List<(String, XvgTimelineEventKind, Duration, int)> _threeEvents([
  int delay = 0,
]) => [
  (_name, _begin, _seconds(delay), 0),
  (_name, _repeat, _seconds(delay + 1), 1),
  (_name, _repeat, _seconds(delay + 2), 2),
  (_name, _end, _seconds(delay + 3), 0),
];

/// Verifies CSS event identity, grouping and compiled timing.
/// 验证 CSS 事件标识、分组和已编译时序。
void main() {
  setUpAll(() async => RustLib.init());

  test('single property emits begin, repeats 1/2 and end once', () {
    final doc = _document(_threeIterations);
    expect(_events(doc, _beforeZero, _seconds(4)), _threeEvents());
    expect(_events(doc, Duration.zero, _seconds(1)), [
      (_name, _repeat, _seconds(1), 1),
    ]);
    expect(_events(doc, _seconds(3), _seconds(4)), isEmpty);
  });

  test('transform slots plus opacity emit only one lifecycle', () {
    final doc = _document(
      _threeIterations,
      frames: '$_transformFrames $_opacityFrames',
    );
    expect(doc.timelines, hasLength(4));
    expect(_events(doc, _beforeZero, _seconds(4)), _threeEvents());
  });

  test('all six channel types share one event source', () {
    final doc = _document(_threeIterations, frames: _allFrames);
    expect(doc.timelines, hasLength(9));
    expect(doc.timelines.map((t) => t.runtimeType).toSet(), hasLength(6));
    expect(doc.timelines.map((t) => t.eventGroup).toSet(), hasLength(1));
    expect(doc.timelines.where((t) => t.eventId != null), hasLength(1));
    expect(doc.timelines.every((t) => t.elementId == null), isTrue);
    expect(_events(doc, _beforeZero, _seconds(4)), _threeEvents());
  });

  test(
    'unsupported first property leaves supported channel as event source',
    () {
      final doc = _document(
        _threeIterations,
        frames: 'from{unknown:0}to{unknown:1}$_opacityFrames',
      );
      expect(_events(doc, _beforeZero, _seconds(4)), _threeEvents());
    },
  );

  test('two animation declarations on one element emit independently', () {
    final doc = _document(
      '$_threeIterations, $_otherName 2s linear 2',
      extraFrames: '@keyframes $_otherName {$_transformFrames}',
    );
    final events = _events(doc, _beforeZero, _seconds(4));
    expect(events, hasLength(7));
    expect(events.where((e) => e.$1 == _name), _threeEvents());
    expect(events.where((e) => e.$1 == _otherName), [
      (_otherName, _begin, Duration.zero, 0),
      (_otherName, _repeat, _seconds(2), 1),
      (_otherName, _end, _seconds(4), 0),
    ]);
  });

  test('same name on two elements retains two independent event groups', () {
    final doc = _document(_threeIterations, extra: _shape(_threeIterations));
    final expected = _threeEvents();
    expect(_events(doc, _beforeZero, _seconds(4)), [
      for (final event in expected) ...[event, event],
    ]);
    expect(doc.timelines.map((t) => t.eventGroup).toSet(), hasLength(2));
  });

  test('same name repeated on one element is still two declarations', () {
    final doc = _document('$_threeIterations, $_name 2s linear 2');
    final events = _events(doc, _beforeZero, _seconds(4));
    expect(events, hasLength(7));
    expect(events.where((e) => e.$2 == _begin), hasLength(2));
    expect(events.where((e) => e.$2 == _repeat), [
      (_name, _repeat, _seconds(1), 1),
      (_name, _repeat, _seconds(2), 2),
      (_name, _repeat, _seconds(2), 1),
    ]);
    expect(events.where((e) => e.$2 == _end).map((e) => e.$3), [
      _seconds(3),
      _seconds(4),
    ]);
  });

  for (final fill in ['none', 'forwards', 'backwards', 'both']) {
    test('positive delay and alternate preserve lifecycle with fill=$fill', () {
      final doc = _document('$_threeIterations 2s alternate $fill');
      expect(_events(doc, _beforeZero, _seconds(1)), isEmpty);
      expect(_events(doc, _beforeZero, _seconds(6)), _threeEvents(2));
      expect(doc.timelines.single.direction, SmilDirection.alternate);
    });
  }

  test(
    'negative delay preserves compiled absolute times and repeat details',
    () {
      final doc = _document('$_threeIterations -1s');
      expect(_events(doc, _seconds(-2), _seconds(2)), _threeEvents(-1));
      expect(_events(doc, _beforeZero, _seconds(2)), _threeEvents(-1).skip(1));
    },
  );

  test('infinite alternate has no end and jumps directly to late repeats', () {
    final doc = _document('$_name 2s linear 1s infinite alternate');
    expect(_events(doc, _beforeZero, _seconds(5)), [
      (_name, _begin, _seconds(1), 0),
      (_name, _repeat, _seconds(3), 1),
      (_name, _repeat, _seconds(5), 2),
    ]);
    expect(_events(doc, _seconds(9000000), _seconds(9000003)), [
      (_name, _repeat, _seconds(9000001), 4500000),
      (_name, _repeat, _seconds(9000003), 4500001),
    ]);
  });

  test('fractional repeat count ends without inventing another repeat', () {
    final doc = _document('$_name 2s linear 2.5 forwards');
    expect(_events(doc, _beforeZero, _seconds(6)), [
      (_name, _begin, Duration.zero, 0),
      (_name, _repeat, _seconds(2), 1),
      (_name, _repeat, _seconds(4), 2),
      (_name, _end, _seconds(5), 0),
    ]);
  });

  test('zero duration follows existing forwards-only compilation', () {
    final doc = _document('$_name 0s infinite forwards');
    expect(_events(doc, _beforeZero, _seconds(1)), [
      (_name, _begin, Duration.zero, 0),
      (_name, _end, Duration.zero, 0),
    ]);
    expect(_events(_document('$_name 0s'), _beforeZero, _seconds(1)), isEmpty);
  });

  test('CSS name collision cannot replace an actual SMIL syncbase', () {
    final doc = _document(
      _threeIterations,
      extra:
          '<rect><animate id="$_name" attributeName="x" values="0;1" '
          'begin="2s" dur="4s"/>'
          '<animate id="$_follower" attributeName="y" values="0;1" '
          'begin="$_name.end" dur="1s"/></rect>',
    );
    expect(
      doc.timelines.singleWhere((t) => t.elementId == _follower).begin,
      _seconds(6),
    );
    expect(
      _events(doc, _seconds(5), _seconds(7)).where((e) => e.$1 == _follower),
      [(_follower, _begin, _seconds(6), 0), (_follower, _end, _seconds(7), 0)],
    );
  });

  test('CSS names never become syncbase targets for single or list begins', () {
    final doc = _document(
      _threeIterations,
      extra:
          '<rect><animate id="single" attributeName="x" values="0;1" '
          'begin="$_name.end" dur="1s"/>'
          '<animate id="list" attributeName="y" values="0;1" '
          'begin="$_name.end;10s" dur="1s"/></rect>',
    );
    expect(
      doc.timelines.singleWhere((t) => t.elementId == 'single').begin,
      Duration.zero,
    );
    final list = doc.timelines.singleWhere((t) => t.elementId == 'list');
    expect(list.intervals!.map((i) => i.begin), [_seconds(10)]);
  });
}
