import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/timeline_events.dart';
import 'package:xvg/xvg.dart' show RustLib;

/// Begin event alias for expected tables.
///
/// 预期时刻表的开始事件别名。
const _begin = XvgTimelineEventKind.begin;

/// End event alias for expected tables.
///
/// 预期时刻表的结束事件别名。
const _end = XvgTimelineEventKind.end;

/// Repeat event alias for expected tables.
///
/// 预期时刻表的重复事件别名。
const _repeat = XvgTimelineEventKind.repeat;

/// Query start that includes an event at document time zero.
///
/// 可包含文档零时刻事件的查询起点。
const _beforeZero = Duration(microseconds: -1);

/// Existing SMIL clock clamp in seconds.
///
/// 现有 SMIL 时钟钳位的秒数。
const _clockLimitSeconds = 10000000;

/// Creates an integer-second test time.
///
/// 创建整秒测试时刻。
Duration _seconds(int value) => Duration(seconds: value);

/// Parses numeric animations on one shape.
///
/// 解析单个图形上的数值动画。
SvgDocument _document(String body) => parseAnimatedSvgDocument(
  '<svg><rect width="10" height="10">$body</rect></svg>',
);

/// Creates a one-second animation with optional id and timing attributes.
///
/// 创建带可选 id 和时序属性的一秒动画。
String _animate([String attributes = 'id="a"']) =>
    '<animate attributeName="opacity" values="0;1" dur="1s" $attributes/>';

/// Converts event objects to comparable value records.
///
/// 将事件对象转为可按值比较的记录。
List<(String, XvgTimelineEventKind, Duration, int)> _events(
  SvgDocument document,
  Duration from,
  Duration to,
) => [
  for (final event in timelineEventsBetween(document, from, to))
    (event.elementId, event.kind, event.time, event.iteration),
];

/// Verifies event times, interval boundaries, and stable source order.
///
/// 验证事件时刻、区间边界和稳定的源文档顺序。
void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  for (final fill in ['remove', 'freeze']) {
    test('single finite animation emits begin/end with fill=$fill', () {
      final doc = _document(_animate('id="a" fill="$fill"'));
      expect(_events(doc, _beforeZero, _seconds(2)), [
        ('a', _begin, Duration.zero, 0),
        ('a', _end, _seconds(1), 0),
      ]);
    });
  }

  test('repeatCount=3 emits repeat details 1 and 2, then only end', () {
    final doc = _document(_animate('id="a" repeatCount="3"'));
    expect(_events(doc, _beforeZero, _seconds(3)), [
      ('a', _begin, Duration.zero, 0),
      ('a', _repeat, _seconds(1), 1),
      ('a', _repeat, _seconds(2), 2),
      ('a', _end, _seconds(3), 0),
    ]);
  });

  test('infinite repeat query jumps directly to a late narrow range', () {
    final doc = _document(_animate('id="a" repeatCount="indefinite"'));
    expect(_events(doc, _seconds(3600), _seconds(3602)), [
      ('a', _repeat, _seconds(3601), 3601),
      ('a', _repeat, _seconds(3602), 3602),
    ]);
    expect(_events(doc, _seconds(9000000), _seconds(9000001)), [
      ('a', _repeat, _seconds(9000001), 9000001),
    ]);
  });

  test('empty and reversed ranges return no events', () {
    final doc = _document(_animate());
    expect(timelineEventsBetween(doc, Duration.zero, Duration.zero), isEmpty);
    expect(timelineEventsBetween(doc, _seconds(2), Duration.zero), isEmpty);
  });

  test('query excludes from and includes to for every event kind', () {
    final doc = _document(_animate('id="a" begin="1s" repeatCount="2"'));
    expect(_events(doc, Duration.zero, _seconds(1)), [
      ('a', _begin, _seconds(1), 0),
    ]);
    expect(_events(doc, _seconds(1), _seconds(2)), [
      ('a', _repeat, _seconds(2), 1),
    ]);
    expect(_events(doc, _seconds(2), _seconds(3)), [
      ('a', _end, _seconds(3), 0),
    ]);
    expect(_events(doc, _seconds(3), _seconds(4)), isEmpty);
  });

  test(
    'same-time events follow source order across channel types and defs',
    () {
      final doc = parseAnimatedSvgDocument('''<svg><defs><clipPath id="clip">
<rect><animate id="first" attributeName="opacity" values="0;1" dur="1s"/></rect>
</clipPath></defs><rect>
<animateTransform id="second" type="translate" values="0;10" dur="1s" begin="1s"/>
<animate id="third" attributeName="fill" values="red;blue" dur="1s" repeatCount="3"/>
</rect></svg>''');
      expect(_events(doc, Duration.zero, _seconds(1)), [
        ('first', _end, _seconds(1), 0),
        ('second', _begin, _seconds(1), 0),
        ('third', _repeat, _seconds(1), 1),
      ]);
    },
  );

  test('syncbase end becomes the dependent animation begin time', () {
    final doc = _document(_animate() + _animate('id="b" begin="a.end"'));
    expect(_events(doc, _beforeZero, _seconds(2)), [
      ('a', _begin, Duration.zero, 0),
      ('a', _end, _seconds(1), 0),
      ('b', _begin, _seconds(1), 0),
      ('b', _end, _seconds(2), 0),
    ]);
  });

  test('list begins emit independent intervals and reset repeat detail', () {
    final doc = _document(_animate('id="a" begin="0;4s" repeatCount="2"'));
    final expected = [
      ('a', _begin, Duration.zero, 0),
      ('a', _repeat, _seconds(1), 1),
      ('a', _end, _seconds(2), 0),
      ('a', _begin, _seconds(4), 0),
      ('a', _repeat, _seconds(5), 1),
      ('a', _end, _seconds(6), 0),
    ];
    expect(_events(doc, _beforeZero, _seconds(6)), expected);
    expect(_events(doc, _beforeZero, _seconds(6)), expected);
    expect(_events(doc, _seconds(4), _seconds(5)), [
      ('a', _repeat, _seconds(5), 1),
    ]);
  });

  test(
    'restart truncation emits end before the next begin on the same track',
    () {
      final doc = _document(_animate('id="a" begin="0;1s" repeatCount="3"'));
      expect(_events(doc, Duration.zero, _seconds(2)), [
        ('a', _end, _seconds(1), 0),
        ('a', _begin, _seconds(1), 0),
        ('a', _repeat, _seconds(2), 1),
      ]);
    },
  );

  test('infinite list interval emits end when a restart truncates it', () {
    final doc = _document(
      _animate('id="a" begin="0;2s" repeatCount="indefinite"'),
    );
    expect(_events(doc, Duration.zero, _seconds(3)), [
      ('a', _repeat, _seconds(1), 1),
      ('a', _end, _seconds(2), 0),
      ('a', _begin, _seconds(2), 0),
      ('a', _repeat, _seconds(3), 1),
    ]);
  });

  test(
    'list cycles extend through to and support earlier queries afterward',
    () {
      final doc = _document(_animate('id="a" begin="0;a.end"'));
      expect(_events(doc, _seconds(3600), _seconds(3601)), [
        ('a', _end, _seconds(3601), 0),
        ('a', _begin, _seconds(3601), 0),
      ]);
      expect(_events(doc, Duration.zero, _seconds(1)), [
        ('a', _end, _seconds(1), 0),
        ('a', _begin, _seconds(1), 0),
      ]);
    },
  );

  test(
    'finite fractional repeat count excludes the end from repeat events',
    () {
      final doc = _document(_animate('id="a" repeatCount="2.5"'));
      expect(_events(doc, Duration.zero, _seconds(3)), [
        ('a', _repeat, _seconds(1), 1),
        ('a', _repeat, _seconds(2), 2),
        ('a', _end, const Duration(milliseconds: 2500), 0),
      ]);
    },
  );

  test(
    'minimum active duration holds the final value without extra repeats',
    () {
      final doc = _document(_animate('id="a" begin="0;10s" min="3s"'));
      expect(_events(doc, _beforeZero, _seconds(4)), [
        ('a', _begin, Duration.zero, 0),
        ('a', _end, _seconds(3), 0),
      ]);
    },
  );

  test('negative begin gives absolute repeat and end times', () {
    final doc = _document(_animate('id="a" begin="-1s" repeatCount="3"'));
    expect(_events(doc, _beforeZero, _seconds(2)), [
      ('a', _repeat, Duration.zero, 1),
      ('a', _repeat, _seconds(1), 2),
      ('a', _end, _seconds(2), 0),
    ]);
  });

  test('end uses the sampled active end beyond legacy sum saturation', () {
    final doc = _document(_animate('id="a" begin="${_clockLimitSeconds}s"'));
    expect(
      _events(
        doc,
        _seconds(_clockLimitSeconds - 1),
        _seconds(_clockLimitSeconds + 2),
      ),
      [
        ('a', _begin, _seconds(_clockLimitSeconds), 0),
        ('a', _end, _seconds(_clockLimitSeconds + 1), 0),
      ],
    );
  });

  test('missing/empty id and never-begin animations emit nothing', () {
    final doc = _document(
      _animate('') +
          _animate('id=""') +
          _animate('id="disabled" begin="disabled.end"'),
    );
    expect(timelineEventsBetween(doc, _beforeZero, _seconds(10)), isEmpty);
  });

  test('compiled CSS keeps syncbase id empty and emits its animation name', () {
    final doc = parseAnimatedSvgDocument('''<svg><style>
@keyframes x {from{opacity:0}to{opacity:1}}
</style><rect id="shape" style="animation:x 2s infinite"/></svg>''');
    expect(doc.timelines, hasLength(1));
    expect(doc.timelines.single.elementId, isNull);
    expect(_events(doc, _beforeZero, _seconds(2)), [
      ('x', _begin, Duration.zero, 0),
      ('x', _repeat, _seconds(2), 1),
    ]);
  });
}
