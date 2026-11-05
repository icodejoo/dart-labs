import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/timeline_events.dart';
import 'package:svgx/svgx.dart' show SvgxAnimationInfo;

/// Shared infinite-repeat attribute.
///
/// 共用的无限重复属性。
const _infinite = 'repeatCount="indefinite"';

/// Shared CSS keyframes.
///
/// 共用的 CSS 关键帧。
const _cssFrames = '<style>@keyframes x {from{opacity:0}to{opacity:1}}</style>';

/// Existing SMIL clock clamp in seconds.
///
/// 现有 SMIL 时钟钳位的秒数。
const _clockLimitSeconds = 10000000;

/// Integer-second test time.
///
/// 整秒测试时刻。
Duration _seconds(int value) => Duration(seconds: value);

/// Parses a small document with numeric SMIL children on one shape.
///
/// 解析在单个图形上包含数值 SMIL 子元素的小文档。
SvgDocument _document(String body) => parseAnimatedSvgDocument(
  '<svg width="24" height="24"><rect width="10" height="10">'
  '$body</rect></svg>',
);

/// Creates a numeric animation with optional timing attributes.
///
/// 创建带可选时序属性的数值动画。
String _animate(String duration, [String timing = '']) =>
    '<animate attributeName="opacity" values="0;1" dur="$duration" $timing/>';

/// Verifies duration metadata and actual steady-state sampling.
///
/// 验证时长信息与实际稳态采样。
void main() {
  test('empty and finite documents preserve legacy durations', () {
    final empty = _document('');
    expect(empty.info.settleTime, Duration.zero);
    expect(empty.info.naturalDuration, Duration.zero);
    final doc = _document(_animate('2s', 'begin="1s" repeatCount="3"'));
    expect(doc.info.settleTime, _seconds(7));
    expect(doc.info.loops, isFalse);
    expect(doc.info.loopPeriod, isNull);
    expect(doc.info.naturalDuration, doc.totalDuration);
    expect(identical(doc.info, doc.info), isTrue);
  });

  test('pure infinite duration is one period despite legacy zero duration', () {
    final doc = _document(_animate('2s', _infinite));
    expect(doc.totalDuration, Duration.zero);
    expect(doc.info.settleTime, Duration.zero);
    expect(doc.info.loops, doc.hasIndefiniteLoop);
    expect(doc.info.loopPeriod, _seconds(2));
    expect(doc.info.naturalDuration, _seconds(2));
  });

  test('integer-microsecond LCM includes different periods', () {
    final doc = _document(
      _animate('2s', _infinite) + _animate('3s', _infinite),
    );
    expect(doc.info.loopPeriod, _seconds(6));
    final fractional = _document(
      _animate('0.000002s', _infinite) + _animate('0.000003s', _infinite),
    );
    expect(fractional.info.loopPeriod, const Duration(microseconds: 6));
  });

  for (final direction in ['alternate', 'alternate-reverse']) {
    test('$direction contributes two iterations to the period', () {
      final doc = parseAnimatedSvgDocument(
        '<svg>$_cssFrames<rect style="animation:x 1s infinite $direction"/></svg>',
      );
      expect(doc.info.loopPeriod, _seconds(2));
    });
  }

  test('LCM cap is inclusive and checked before multiplication', () {
    final atCap = _document(
      _animate('12s', _infinite) + _animate('15s', _infinite),
    );
    expect(atCap.info.loopPeriod, _seconds(60));
    for (final body in [
      _animate('7s', _infinite) + _animate('11s', _infinite),
      _animate('10000000s', _infinite),
      _animate('59.999999s', _infinite) + _animate('59.999998s', _infinite),
    ]) {
      final doc = _document(body);
      expect(doc.info.loopPeriod, isNull);
      expect(doc.info.naturalDuration, isNull);
    }
  });

  test('alternate duration over half the cap has no known period', () {
    final doc = parseAnimatedSvgDocument(
      '<svg>$_cssFrames<rect style="animation:x 31s infinite alternate"/></svg>',
    );
    expect(doc.info.loopPeriod, isNull);
  });

  test('list begin infinite duration has no defined period', () {
    final doc = _document(_animate('2s', 'begin="1s;4s" $_infinite'));
    expect(doc.info.loops, isTrue);
    expect(doc.info.settleTime, _seconds(1));
    expect(doc.info.loopPeriod, isNull);
  });

  test('finite list duration uses its last resolved interval end', () {
    final doc = _document(_animate('3s', 'begin="1s;4s" end="5s"'));
    expect(doc.info.settleTime, _seconds(5));
    expect(doc.info.settleTime, doc.totalDuration);
  });

  test('mixed documents include infinite begins in settling time', () {
    final finiteLater = _document(
      _animate('3s', 'begin="2s"') + _animate('2s', 'begin="1s" $_infinite'),
    );
    expect(finiteLater.info.settleTime, _seconds(5));
    expect(finiteLater.info.naturalDuration, _seconds(7));
    final infiniteLater = _document(
      _animate('3s') + _animate('2s', 'begin="8s" $_infinite'),
    );
    expect(infiniteLater.totalDuration, _seconds(3));
    expect(infiniteLater.info.settleTime, _seconds(8));
    expect(infiniteLater.info.naturalDuration, _seconds(10));
  });

  test('never-begin timelines do not contribute times or periods', () {
    final doc = _document(
      _animate('2s') +
          _animate('7s', 'id="disabled" begin="disabled.end" $_infinite'),
    );
    expect(
      doc.timelines.singleWhere((a) => a.elementId == 'disabled').begin,
      kSmilNeverBegins,
    );
    expect(doc.info.settleTime, _seconds(2));
    expect(doc.info.loops, isFalse);
    expect(doc.info.loopPeriod, isNull);
  });

  test('CSS infinite animation uses the same duration model', () {
    final doc = parseAnimatedSvgDocument(
      '<svg>$_cssFrames<rect style="animation:x 2s infinite"/></svg>',
    );
    expect(doc.info.settleTime, Duration.zero);
    expect(doc.info.loopPeriod, _seconds(2));
    expect(doc.info.loops, doc.hasIndefiniteLoop);
  });

  test('CSS alternate loopPeriod spans two repeat boundaries after settling', () {
    final doc = parseAnimatedSvgDocument(
      '<svg>$_cssFrames<rect style="animation:x 2s 1s infinite alternate"/></svg>',
    );
    expect(doc.info.settleTime, _seconds(1));
    expect(doc.info.loopPeriod, _seconds(4));
    final from = doc.info.settleTime;
    final to = from + doc.info.loopPeriod!;
    final events = timelineEventsBetween(doc, from, to);
    expect(events.map((e) => e.kind), [
      SvgxTimelineEventKind.repeat,
      SvgxTimelineEventKind.repeat,
    ]);
    expect(events.map((e) => e.time), [_seconds(3), to]);
    expect(events.map((e) => e.iteration), [1, 2]);
  });

  test('pending list instances preserve the existing false-infinite flag', () {
    final doc = _document(
      _animate('1s', 'id="a" begin="0;100s;a.end" restart="never"'),
    );
    expect(doc.hasIndefiniteLoop, isTrue);
    expect(doc.info.loops, isTrue);
    expect(doc.info.loopPeriod, isNull);
  });

  test('zero-duration list sets retain the legacy last-begin convention', () {
    final doc = _document(
      '<set id="s" attributeName="opacity" to="1" begin="1s;4s"/>',
    );
    expect(doc.info.settleTime, doc.totalDuration);
    expect(doc.info.settleTime, _seconds(4));
    expect(doc.info.loops, isFalse);
  });

  test('value equality, hash, and readable description', () {
    final info = SvgxAnimationInfo(
      settleTime: _seconds(3),
      loops: true,
      loopPeriod: _seconds(2),
    );
    final same = SvgxAnimationInfo(
      settleTime: _seconds(3),
      loops: true,
      loopPeriod: _seconds(2),
    );
    expect(info, same);
    expect(info.hashCode, same.hashCode);
    expect(
      info,
      isNot(SvgxAnimationInfo(settleTime: _seconds(4), loops: true)),
    );
    expect(
      info,
      isNot(SvgxAnimationInfo(settleTime: _seconds(3), loops: false)),
    );
    expect(info, isNot(Object()));
    expect(info.toString(), contains('settleTime: 0:00:03.000000'));
    expect(info.toString(), contains('loops: true'));
    expect(info.toString(), contains('loopPeriod: 0:00:02.000000'));
  });

  test('settling uses the sampled active end beyond legacy sum saturation', () {
    final doc = _document(
      _animate('2s', 'begin="${_clockLimitSeconds}s" fill="freeze"') +
          _animate('1s', _infinite),
    );
    expect(doc.totalDuration, _seconds(_clockLimitSeconds));
    expect(doc.info.settleTime, _seconds(_clockLimitSeconds + 2));
    final finite = doc.timelines.first as SmilAnimation;
    expect(finite.sample(doc.totalDuration), 0);
    final t = doc.info.settleTime;
    expect(finite.sample(t), 1);
    expect(finite.sample(t), finite.sample(t + doc.info.loopPeriod!));
  });

  final periodicDocuments = [
    _document(
      _animate('2s', _infinite) +
          _animate('3s', 'begin="1s" $_infinite') +
          _animate('4s', 'fill="freeze"'),
    ),
    parseAnimatedSvgDocument('''<svg><style>
@keyframes x {from{opacity:0}to{opacity:1}}
@keyframes move {from{transform:translate(0px)}to{transform:translate(10px)}}
</style><rect style="animation:x 1s infinite alternate, move 3s infinite alternate-reverse">
${_animate('2s', 'begin="2s" $_infinite')}</rect></svg>'''),
    _document(
      _animate('0.25s', 'begin="-1s" $_infinite') +
          _animate('1.5s', 'begin="2s" $_infinite') +
          _animate('1s'),
    ),
  ];
  for (var i = 0; i < periodicDocuments.length; i++) {
    test('real sampling is periodic at and after settling: document $i', () {
      final doc = periodicDocuments[i];
      final period = doc.info.loopPeriod!;
      for (final offset in [0, 1, 123456, 1000000, 123456789]) {
        final t = doc.info.settleTime + Duration(microseconds: offset);
        for (final timeline in doc.timelines) {
          // These documents contain scalar and transform channels only.
          // 这些文档仅包含数值和变换通道，并逐条比较全部时间线。
          if (timeline is SmilAnimation) {
            expect(timeline.sample(t), timeline.sample(t + period));
          } else if (timeline is SmilTransformAnimation) {
            expect(timeline.sample(t), timeline.sample(t + period));
          } else {
            fail('Unexpected unsampled timeline: ${timeline.runtimeType}');
          }
        }
      }
    });
  }
}
