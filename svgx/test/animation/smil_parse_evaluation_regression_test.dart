import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/svgx.dart' show RustLib;
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_dom.dart';

import 'node_test_utils.dart';
import 'pixel_test_utils.dart';

/// 用真实文档覆盖解析入口，原生库必须可用。
SvgNode _node(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">'
  '<path d="M0 0L10 0">$body</path></svg>',
).root.children.single;

/// SMIL 解析与求值回归；仅文档集成用例需要原生库。
void main() {
  var nativeReady = false;
  setUpAll(() async {
    try {
      await RustLib.init();
      nativeReady = true;
    } catch (_) {
      nativeReady = false;
    }
  });

  bool needsNative() {
    if (nativeReady) return false;
    markTestSkipped('原生库不可加载：把 prebuilt/windows/x64 放进 PATH 再跑');
    return true;
  }

  for (final count in ['1e303', '1e300']) {
    for (final direction in SmilDirection.values) {
      test('超大有限重复安全采样 $count $direction', () {
        final a = SmilAnimation(
          attributeName: 'x',
          values: [0, 1],
          duration: const Duration(seconds: 1),
          begin: const Duration(seconds: 1),
          repeatCount: parseSmilRepeatCount(count),
          direction: direction,
          fillFreeze: false,
        );
        expect(a.sample(const Duration(milliseconds: 1500)), 0.5);
      });
    }
    test('超大有限重复文档与 syncbase 链不溢出 $count', () {
      if (needsNative()) return;
      final doc = parsePixelDoc(
        '<path d="M0 0L10 0">'
        '<animate id="a" attributeName="x" values="0;1" '
        'dur="1s" begin="1s" repeatCount="$count"/>'
        '<animate id="b" attributeName="y" values="0;1" '
        'dur="1s" begin="a.end"/>'
        '<animate attributeName="opacity" values="0;1" '
        'dur="1s" begin="b.end"/></path>',
      );
      final animations = doc.root.children.single.animations;
      expect(doc.totalDuration, greaterThan(const Duration(days: 100)));
      expect(
        doc.totalDuration,
        lessThanOrEqualTo(const Duration(seconds: 10000000)),
      );
      for (final a in animations.skip(1)) {
        expect(a.begin, greaterThan(const Duration(days: 100)));
        expect(a.sample(const Duration(seconds: 2)), isNull);
      }
      expect(animations.first.sample(const Duration(milliseconds: 1500)), 0.5);
    });
  }

  test('负时长无限循环的直接构造 discrete 安全取首帧', () {
    final a = SmilAnimation(
      attributeName: 'opacity',
      values: [0.5, 1],
      duration: const Duration(seconds: -1),
      begin: Duration.zero,
      fillFreeze: false,
      repeatCount: const SmilRepeatCount.indefinite(),
      calcMode: SmilCalcMode.discrete,
    );
    expect(a.sample(kMs * 500), 0.5);
  });

  for (final attribute in ['opacity', 'd']) {
    test('负时长无限循环 set $attribute 安全采样', () {
      if (needsNative()) return;
      final n = _node(
        '<set attributeName="$attribute" '
        'to="${attribute == 'd' ? 'M0 0L20 0' : '0.5'}" '
        'dur="-1s" repeatCount="indefinite"/>',
      );
      if (attribute == 'd') {
        expect(n.pathAnimations.single.sample(kMs * 500), 0);
      } else {
        expect(n.animations.single.sample(kMs * 500), 0.5);
      }
      final document = parsePixelDoc(
        '<path d="M0 0L10 0"><set attributeName="$attribute" '
        'to="${attribute == 'd' ? 'M0 0L20 0' : '0.5'}" '
        'dur="-1s" repeatCount="indefinite"/></path>',
      );
      expect(document.hasIndefiniteLoop, isFalse);
      expect(() => paintAt(document, kMs * 500), returnsNormally);
    });
  }

  test('时长换算限制在一千万秒以内', () {
    for (final raw in [
      '1e300s',
      '10000001s',
      '10000001000ms',
      '-1e300s',
      '1e300',
    ]) {
      expect(
        parseSmilDuration(raw).abs(),
        const Duration(seconds: 10000000),
        reason: raw,
      );
      expect(
        parseSmilBeginSpec(raw).offset,
        raw.startsWith('-')
            ? const Duration(seconds: -10000000)
            : kSmilNeverBegins,
        reason: raw,
      );
    }
    expect(parseSmilDuration('10000000s'), const Duration(seconds: 10000000));
  });

  test('超大 dur 饱和且保留动画', () {
    if (needsNative()) return;
    expect(
      _node(
        '<animate attributeName="opacity" values="0;1" '
        'dur="1e300s" begin="1s"/>',
      ).animations.single.duration,
      const Duration(seconds: 10000000),
    );
  });

  for (final rotate in ['Infinity', '-Infinity', 'NaN', '1e400']) {
    test('motion 非有限 rotate 回退零角度：$rotate', () {
      if (needsNative()) return;
      final a = _node(
        '<animateMotion path="M0 0L10 0" dur="1s" '
        'rotate="$rotate"/>',
      ).motionAnimations.single;
      expect(a.sample(kMs * 500)!.angleDegrees, 0);
    });
  }

  for (final times in <List<double>?>[
    null,
    [0, 0.7],
    [0, 0.1, 1],
  ]) {
    test('discrete 全通道末帧及切换边界 keyTimes=$times', () {
      final scalar = SmilAnimation(
        attributeName: 'x',
        values: [0, 1],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
        keyTimes: times,
      );
      final transform = SmilTransformAnimation(
        type: SmilTransformType.translate,
        values: [
          [0, 0, 0],
          [1, 0, 0],
        ],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
        keyTimes: times,
      );
      final color = SmilColorAnimation(
        values: [0xff000000, 0xffffffff],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
        keyTimes: times,
      );
      final list = SmilListAnimation(
        attributeName: 'stroke-dasharray',
        values: [
          [0],
          [1],
        ],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
        keyTimes: times,
      );
      final motion = SmilMotionAnimation(
        samples: const [SmilMotionSample(0, 0, 0), SmilMotionSample(1, 0, 0)],
        keyPoints: [0, 1],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
        keyTimes: times,
      );
      final boundary = times?.length == 2 ? 700 : 500;
      for (final ms in [0, boundary - 1, boundary, 999, 1000, 1200]) {
        final expected = ms < boundary ? 0 : 1;
        final t = kMs * ms;
        expect(scalar.sample(t), expected, reason: '$ms');
        expect(transform.sample(t)!.first, expected);
        expect(color.sample(t), expected == 0 ? 0xff000000 : 0xffffffff);
        expect(list.sample(t), [expected]);
        expect(motion.sample(t)!.x, expected);
      }
    });
  }

  for (final times in <List<double>?>[
    null,
    [0, 1],
  ]) {
    test('三帧 discrete 等分，keyTimes 缺省或长度不匹配：$times', () {
      final scalar = SmilAnimation(
        attributeName: 'x',
        values: [0, 10, 20],
        duration: const Duration(milliseconds: 1200),
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
        keyTimes: times,
      );
      final transform = SmilTransformAnimation(
        type: SmilTransformType.translate,
        values: [
          [0, 0],
          [10, 0],
          [20, 0],
        ],
        duration: scalar.duration,
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
        keyTimes: times,
      );
      final motion = SmilMotionAnimation(
        samples: const [SmilMotionSample(0, 0, 0), SmilMotionSample(20, 0, 0)],
        keyPoints: [0, 0.5, 1],
        keyTimes: times,
        duration: scalar.duration,
        begin: Duration.zero,
        fillFreeze: true,
        calcMode: SmilCalcMode.discrete,
      );
      for (final (ms, expected) in [
        (0, 0),
        (399, 0),
        (400, 10),
        (799, 10),
        (800, 20),
        (1199, 20),
        (1200, 20),
        (1400, 20),
      ]) {
        expect(scalar.sample(kMs * ms), expected, reason: '$ms');
        expect(transform.sample(kMs * ms)!.first, expected, reason: '$ms');
        expect(motion.sample(kMs * ms)!.x, expected, reason: '$ms');
      }
    });
  }

  test('末尾分号和空项保留 values keyTimes transform keyPoints', () {
    expect(parseSmilValues(values: ' ;0; ;1; '), [0, 1]);
    expect(parseSmilKeyTimes(' ;0; ;0.7; '), [0, 0.7]);
    expect(parseSmilKeyTimes('; ;'), isNull);
    expect(parseSmilTransformKeyframes(values: ';0 0; ;10 0; '), [
      [0, 0],
      [10, 0],
    ]);
  });

  test('末尾分号文档解析', () {
    if (needsNative()) return;
    final n = _node(
      '<animateMotion path="M0 0L10 0" dur="1s" '
      'calcMode="discrete" keyPoints="0;1; " keyTimes="0;0.7; "/>'
      '<animate attributeName="opacity" values="0;1; " dur="1s"/>'
      '<animateTransform type="translate" values="0;10; " dur="1s"/>',
    );
    expect(n.animations.single.values, [0, 1]);
    expect(n.transformAnimations.single.values.last.first, 10);
    expect(n.motionAnimations.single.keyPoints, [0, 1]);
    expect(n.motionAnimations.single.sample(kMs * 700)!.x, closeTo(10, 0.001));
  });

  test('begin 支持连字符 id 和 indefinite 且不扩展列表语义', () {
    for (final event in ['begin', 'end']) {
      final spec = parseSmilBeginSpec('ring-1.$event+0.2s');
      expect(spec.syncbaseId, 'ring-1');
      expect(spec.onSyncbaseEnd, event == 'end');
      expect(spec.offset, kMs * 200);
    }
    for (final raw in ['ring-1.end;2s', 'a.end;b.end', 'a.end+1s;b.end']) {
      expect(parseSmilBeginSpec(raw).syncbaseId, isNull);
      expect(parseSmilBeginSpec(raw).offset, Duration.zero);
    }
  });

  test('begin 文档解析', () {
    if (needsNative()) return;
    final n = _node(
      '<animate id="ring-1" attributeName="x" values="0;1" dur="1s"/>'
      '<animate attributeName="y" values="0;1" dur="1s" begin="ring-1.end+0.2s"/>'
      '<animate id="never" attributeName="opacity" values="0;1" dur="1s" begin="indefinite"/>'
      '<animate attributeName="r" values="0;1" dur="1s" begin="never.end"/>',
    );
    expect(n.animations[1].begin, kMs * 1200);
    expect(n.animations[2].begin, kSmilNeverBegins);
    expect(n.animations[2].sample(kMs * 10000), isNull);
    expect(n.animations[3].begin, kSmilNeverBegins);
  });

  for (final dur in ['', ' dur="indefinite"', ' dur="0s"', ' dur="-1s"']) {
    test('无有效 dur 的 animate 各通道无效果，set 保持原行为：$dur', () {
      if (needsNative()) return;
      final n = _node(
        '<animate attributeName="opacity" values="0;1" fill="freeze"$dur/>'
        '<animate attributeName="fill" values="#000000;#ffffff"$dur/>'
        '<animate attributeName="d" values="M0 0L1 0;M0 0L2 0"$dur/>'
        '<animateTransform type="translate" values="0;10"$dur/>'
        '<animateMotion path="M0 0L10 0"$dur/>',
      );
      expect(n.animations, isEmpty);
      expect(n.colorAnimations, isEmpty);
      expect(n.pathAnimations, isEmpty);
      expect(n.transformAnimations, isEmpty);
      expect(n.motionAnimations, isEmpty);
      final set = _node('<set attributeName="opacity" to="0.5"/>');
      expect(set.animations.single.sample(kMs * 10000), 0.5);
    });
  }

  for (final raw in ['Infinity', '-Infinity', 'NaN', '1e400']) {
    test('非有限数安全降级：$raw', () {
      expect(parseSmilRepeatCount(raw).count, 1);
      expect(parseSmilRepeatCount(raw).indefinite, isFalse);
      expect(parseSmilDuration(raw), Duration.zero);
      expect(parseSmilDuration('${raw}s'), Duration.zero);
      expect(parseSmilDuration('${raw}ms'), Duration.zero);
      expect(parseSmilBeginSpec(raw).offset, Duration.zero);
      expect(parseSmilValues(values: '0;$raw'), isNull);
      expect(parseSmilValues(from: '0', to: raw), isNull);
      expect(parseSmilKeyTimes('0;$raw'), isNull);
      expect(parseSmilKeySplines('0 0 1 $raw'), isNull);
      expect(parseSmilTransformKeyframes(values: '0;$raw'), isNull);
    });
    test('非有限数文档解析：$raw', () {
      if (needsNative()) return;
      final n = _node(
        '<animate id="a" attributeName="x" values="0;1" dur="1s" repeatCount="$raw"/>'
        '<animate attributeName="y" values="0;1" dur="1s" begin="a.end"/>'
        '<animateMotion path="M0 0L10 0" dur="1s" keyPoints="0;$raw"/>',
      );
      expect(n.animations.first.repeatCount.count, 1);
      expect(n.animations[1].begin, const Duration(seconds: 1));
      expect(n.animations.first.sample(kMs * 500), 0.5);
      expect(n.motionAnimations.single.keyPoints, isNull);
    });
  }
  test('repeatCount indefinite 保持无限循环', () {
    expect(parseSmilRepeatCount('indefinite').indefinite, isTrue);
  });
}
