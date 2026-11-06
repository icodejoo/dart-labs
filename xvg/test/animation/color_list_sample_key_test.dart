// P4-4：`_effectiveAttributes` 采样键（颜色段、列表段）的不变量回归测试。
//
// 三条不变量：缺失 = 负无穷且不覆盖属性；none 哨兵 = -1.0 且覆盖为 `none`；
// 所有槽位都没变时必须交回上一帧缓存的同一张属性表实例，使 `_resolveStyle` 与
// 几何缓存继续命中。错一处会表现为缓存冻结在首帧或每帧都未命中。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/svg_dom.dart';
import 'package:xvg/src/animation/svg_path_morph.dart';
import 'package:xvg/src/animation/svg_theme.dart';

import 'pixel_test_utils.dart';

/// 毫秒转时间。
Duration _ms(int ms) => Duration(milliseconds: ms);

/// 不带 `<animate>` 的静态填充色。
const String _staticFill = '#00ff00';

/// 静态虚线数组。
const String _staticDash = '5 5';

/// 纯红、纯蓝（0xAARRGGBB）。
const int _red = 0xFFFF0000;
const int _blue = 0xFF0000FF;

/// 构造数值动画（作用于 `x`，定格）。
SmilAnimation _numeric({int seconds = 1}) => SmilAnimation(
  attributeName: 'x',
  values: const [0, 10],
  duration: Duration(seconds: seconds),
  begin: Duration.zero,
  fillFreeze: true,
);

/// 构造颜色动画（作用于 `fill`）。
SmilColorAnimation _color({
  int seconds = 1,
  List<int> values = const [_red, _blue],
  bool freeze = true,
  Duration begin = Duration.zero,
  String attribute = 'fill',
}) => SmilColorAnimation(
  attributeName: attribute,
  values: values,
  duration: Duration(seconds: seconds),
  begin: begin,
  fillFreeze: freeze,
);

/// 构造列表动画（作用于 `stroke-dasharray`）。
SmilListAnimation _list({
  int seconds = 1,
  List<List<double>> values = const [
    [10, 10],
    [20, 40],
  ],
  bool freeze = true,
}) => SmilListAnimation(
  attributeName: 'stroke-dasharray',
  values: values,
  duration: Duration(seconds: seconds),
  begin: Duration.zero,
  fillFreeze: freeze,
);

/// 构造路径变形动画（两帧，定格）。
SmilPathAnimation _path({int seconds = 1}) {
  const frames = ['M10 10L30 10L30 30Z', 'M10 10L50 10L50 30Z'];
  return SmilPathAnimation(
    frames: frames,
    morph: buildPathMorphData(frames),
    duration: Duration(seconds: seconds),
    begin: Duration.zero,
    fillFreeze: true,
  );
}

/// 构造带各类动画的 `<path>` 节点。
SvgNode _pathNode({
  List<SmilAnimation> numeric = const [],
  List<SmilPathAnimation> paths = const [],
  List<SmilColorAnimation> colors = const [],
  List<SmilListAnimation> lists = const [],
}) => SvgNode(
  kind: SvgNodeKind.path,
  attributes: const {
    'd': 'M10 10L30 10L30 30Z',
    'fill': _staticFill,
    'stroke': '#000000',
    'stroke-width': '2',
    'stroke-dasharray': _staticDash,
  },
  animations: numeric,
  pathAnimations: paths,
  colorAnimations: colors,
  listAnimations: lists,
);

/// 把 [children] 包进根节点。
SvgNode _root(List<SvgNode> children) =>
    SvgNode(kind: SvgNodeKind.root, attributes: const {}, children: children);

/// 用全新 painter 在 [t] 绘制 [root]（只录制），保留节点上的缓存。
void _paint(SvgNode root, Duration t) {
  final clock = ValueNotifier(t);
  final recorder = ui.PictureRecorder();
  AnimatedSvgPainter(
    root: root,
    intrinsicSize: const Size.square(100),
    clock: clock,
    theme: const XvgTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
  ).paint(Canvas(recorder), const Size.square(100));
  recorder.endRecording().dispose();
  clock.dispose();
}

/// 持有一个长生命周期 painter 与时钟，模拟生产里同一 painter 随时钟逐帧重绘。
class _Rig {
  /// 以 [root] 创建 painter。
  _Rig(SvgNode root) : _clock = ValueNotifier(Duration.zero), _painter = null {
    _painter = AnimatedSvgPainter(
      root: root,
      intrinsicSize: const Size.square(100),
      clock: _clock,
      theme: const XvgTheme(),
      fit: BoxFit.fill,
      alignment: Alignment.center,
    );
  }

  /// 驱动 painter 的时钟。
  final ValueNotifier<Duration> _clock;

  /// 被复用的 painter。
  AnimatedSvgPainter? _painter;

  /// 在 [t] 时刻绘制一帧（只录制）。
  void paint(Duration t) {
    _clock.value = t;
    final recorder = ui.PictureRecorder();
    _painter!.paint(Canvas(recorder), const Size.square(100));
    recorder.endRecording().dispose();
  }
}

/// 绘制 [node]（包在根里）后取出它缓存的属性表。
Map<String, String> _attrs(SvgNode node, Duration t) {
  _paint(_root([node]), t);
  return node.cachedAnimatedAttributes!;
}

/// 渲染并返回像素。
Future<ByteData> _render(
  SvgNode root,
  Duration t, {
  Map<String, SvgNode> masks = const {},
  bool approximate = false,
}) => renderRootAt(root, t, masks: masks, approximateMasks: approximate);

/// 字节级比较两帧像素。
void _expectSamePixels(ByteData a, ByteData b, String reason) {
  expect(
    a.buffer.asUint8List().toList(),
    b.buffer.asUint8List().toList(),
    reason: reason,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('无变化复用同一张属性表', () {
    test('四类动画混合的节点，同一时刻连续两帧返回同一实例', () {
      final node = _pathNode(
        numeric: [_numeric()],
        paths: [_path()],
        colors: [_color()],
        lists: [_list()],
      );
      for (final ms in [0, 500, 1000, 5000]) {
        final first = _attrs(node, _ms(ms));
        final second = _attrs(node, _ms(ms));
        expect(identical(first, second), isTrue, reason: 'ms=$ms');
      }
    });

    test('全部定格后不同时刻仍复用同一实例，且 style/几何缓存命中', () {
      final node = _pathNode(
        numeric: [_numeric()],
        paths: [_path()],
        colors: [_color()],
        lists: [_list()],
      );
      // 与生产一致：同一个 painter 实例随时钟逐帧重绘。
      final rig = _Rig(_root([node]));
      rig.paint(_ms(2000));
      final first = node.cachedAnimatedAttributes;
      final style = node.cachedStyle;
      final geometry = node.cachedGeometry;
      expect(style, isNotNull);
      rig.paint(_ms(3000));
      expect(identical(node.cachedAnimatedAttributes, first), isTrue);
      expect(identical(node.cachedStyle, style), isTrue, reason: '样式缓存命中');
      expect(
        identical(node.cachedGeometry, geometry),
        isTrue,
        reason: '几何缓存命中',
      );
    });

    test('颜色仍在变化时样式缓存按预期失效', () {
      final node = _pathNode(colors: [_color()]);
      final rig = _Rig(_root([node]));
      rig.paint(_ms(300));
      final style = node.cachedStyle;
      rig.paint(_ms(600));
      expect(identical(node.cachedStyle, style), isFalse);
    });
  });

  group('任一类采样值变化 -> 新 Map 且内容正确', () {
    test('颜色变化', () {
      final node = _pathNode(colors: [_color()]);
      final a = _attrs(node, _ms(0));
      final b = _attrs(node, _ms(500));
      expect(identical(a, b), isFalse);
      expect(a['fill'], '#FF0000FF');
      expect(b['fill'], '#800080FF');
      // 前一帧的表不得被原地改写。
      expect(a['fill'], '#FF0000FF');
    });

    test('列表变化', () {
      final node = _pathNode(lists: [_list()]);
      final a = _attrs(node, _ms(0));
      final b = _attrs(node, _ms(500));
      expect(identical(a, b), isFalse);
      expect(a['stroke-dasharray'], '10.0 10.0');
      expect(b['stroke-dasharray'], '15.0 25.0');
    });

    test('数值变化', () {
      final node = _pathNode(numeric: [_numeric()]);
      final a = _attrs(node, _ms(0));
      final b = _attrs(node, _ms(500));
      expect(identical(a, b), isFalse);
      expect(a['x'], '0.0');
      expect(b['x'], '5.0');
    });

    test('只有路径段在动时（其余已定格）也判为变化，且其它通道值保持', () {
      // 数值 1s、颜色 2s、列表 3s、路径 4s 各自定格；3.5s 起只剩路径在动。
      final node = _pathNode(
        numeric: [_numeric(seconds: 1)],
        colors: [_color(seconds: 2)],
        lists: [_list(seconds: 3)],
        paths: [_path(seconds: 4)],
      );
      final a = _attrs(node, _ms(3500));
      final morphA = node.animatedMorphPath;
      final b = _attrs(node, _ms(3600));
      expect(identical(a, b), isFalse);
      expect(identical(node.animatedMorphPath, morphA), isFalse);
      expect(b['fill'], '#0000FFFF');
      expect(b['stroke-dasharray'], '20.0 40.0');
      expect(b['x'], '10.0');
    });

    test('只有列表段在动（颜色已定格）也判为变化', () {
      final node = _pathNode(
        colors: [_color(seconds: 1)],
        lists: [_list(seconds: 3)],
      );
      final a = _attrs(node, _ms(1500));
      final b = _attrs(node, _ms(2000));
      expect(identical(a, b), isFalse);
      expect(a['fill'], b['fill']);
      expect(a['stroke-dasharray'], isNot(b['stroke-dasharray']));
    });

    test('多条列表动画按各自 width 占槽位，互不串位', () {
      final second = SmilListAnimation(
        attributeName: 'stroke-dashoffset',
        values: const [
          [0],
          [8],
        ],
        duration: const Duration(seconds: 2),
        begin: Duration.zero,
        fillFreeze: true,
      );
      final node = _pathNode(lists: [_list(), second]);
      // 3 个槽位：dasharray 两个 + dashoffset 一个。
      final a = _attrs(node, _ms(1000));
      expect(node.animatedSampleKey!.length, 3);
      expect(a['stroke-dasharray'], '20.0 40.0');
      expect(a['stroke-dashoffset'], '4.0');
      // 仅第二条（槽位 2）在动：必须判为变化。
      final b = _attrs(node, _ms(1500));
      expect(identical(a, b), isFalse);
      expect(b['stroke-dasharray'], '20.0 40.0');
      expect(b['stroke-dashoffset'], '6.0');
    });

    test('同一属性被多条动画覆盖时，颜色/列表晚于数值写入并胜出', () {
      final numericFill = SmilAnimation(
        attributeName: 'stroke-dasharray',
        values: const [3, 3],
        duration: const Duration(seconds: 1),
        begin: Duration.zero,
        fillFreeze: true,
      );
      final node = _pathNode(numeric: [numericFill], lists: [_list()]);
      expect(_attrs(node, _ms(0))['stroke-dasharray'], '10.0 10.0');
    });
  });

  group('缺失（-inf）与 none（-1.0）', () {
    test('颜色结束且不定格 -> 属性回到静态值', () {
      final node = _pathNode(colors: [_color(freeze: false)]);
      expect(_attrs(node, _ms(500))['fill'], '#800080FF');
      expect(_attrs(node, _ms(2000))['fill'], _staticFill);
    });

    test('列表结束且不定格 -> 属性回到静态值', () {
      final node = _pathNode(lists: [_list(freeze: false)]);
      expect(_attrs(node, _ms(500))['stroke-dasharray'], '15.0 25.0');
      expect(_attrs(node, _ms(2000))['stroke-dasharray'], _staticDash);
    });

    test('none 哨兵覆盖为字符串 none；从 none 变到缺失必须判为变化', () {
      final node = _pathNode(
        colors: [
          _color(values: const [_red, kSmilColorNone], freeze: false),
        ],
      );
      final during = _attrs(node, _ms(700));
      expect(during['fill'], 'none');
      final after = _attrs(node, _ms(2000));
      expect(identical(during, after), isFalse, reason: '-1.0 与 -inf 必须可区分');
      expect(after['fill'], _staticFill);
    });

    test('从缺失变到 none 也必须判为变化', () {
      final node = _pathNode(
        colors: [
          _color(
            values: const [kSmilColorNone, kSmilColorNone],
            begin: const Duration(seconds: 1),
          ),
        ],
      );
      final before = _attrs(node, _ms(500));
      expect(before['fill'], _staticFill);
      final during = _attrs(node, _ms(1500));
      expect(identical(before, during), isFalse);
      expect(during['fill'], 'none');
    });

    test('缺失连续多帧不会因 NaN 式比较每帧都判变化', () {
      final node = _pathNode(
        colors: [_color(freeze: false)],
        lists: [_list(freeze: false)],
      );
      final a = _attrs(node, _ms(3000));
      final b = _attrs(node, _ms(4000));
      expect(identical(a, b), isTrue);
    });

    test('列表缺失时整段槽位都是负无穷', () {
      final node = _pathNode(lists: [_list(freeze: false)]);
      _attrs(node, _ms(3000));
      expect(node.animatedSampleKey!.toList(), [
        double.negativeInfinity,
        double.negativeInfinity,
      ]);
    });
  });

  group('键长度与跨 painter', () {
    test('键长度不符时重新分配并判为已变化（过短与过长）', () {
      final node = _pathNode(
        numeric: [_numeric()],
        colors: [_color()],
        lists: [_list()],
      );
      // 1 + 1 + 2 个槽位。
      for (final wrong in [1, 50]) {
        node.animatedSampleKey = Float64List(wrong);
        final attrs = _attrs(node, _ms(1000));
        expect(node.animatedSampleKey!.length, 4, reason: 'wrong=$wrong');
        expect(attrs['fill'], '#0000FFFF');
        expect(attrs['stroke-dasharray'], '20.0 40.0');
        expect(attrs['x'], '10.0');
      }
    });

    test('同一文档被两个 painter 以不同时刻交错渲染互不污染', () async {
      SvgNode build() => _root([
        SvgNode(
          kind: SvgNodeKind.rect,
          attributes: const {
            'x': '10',
            'y': '10',
            'width': '40',
            'height': '40',
            'fill': _staticFill,
          },
          colorAnimations: [_color()],
        ),
        SvgNode(
          kind: SvgNodeKind.line,
          attributes: const {
            'x1': '0',
            'y1': '80',
            'x2': '100',
            'y2': '80',
            'stroke': '#ff0000',
            'stroke-width': '6',
          },
          listAnimations: [_list()],
        ),
      ]);
      final shared = build();
      final times = [0, 1000, 0, 500, 1000, 500, 0];
      for (final ms in times) {
        final expected = await _render(build(), _ms(ms));
        final actual = await _render(shared, _ms(ms));
        _expectSamePixels(actual, expected, 'ms=$ms');
      }
    });
  });

  group('mask 子树内的颜色/列表动画走精确管线', () {
    /// 被遮罩的红色整幅矩形。
    SvgNode target() => SvgNode(
      kind: SvgNodeKind.rect,
      attributes: const {
        'x': '0',
        'y': '0',
        'width': '100',
        'height': '100',
        'fill': '#ff0000',
      },
      maskId: 'm',
    );

    /// 遮罩内的整幅矩形，填充由颜色动画从白变黑。
    SvgNode maskRect({List<SmilListAnimation> lists = const []}) => SvgNode(
      kind: SvgNodeKind.rect,
      attributes: const {
        'x': '0',
        'y': '0',
        'width': '100',
        'height': '100',
        'fill': '#ffffff',
      },
      colorAnimations: lists.isEmpty
          ? [
              _color(values: const [0xFFFFFFFF, 0xFF000000]),
            ]
          : const [],
      listAnimations: lists,
    );

    test('mask 内颜色动画：近似与精确模式结果一致且随时间变化', () async {
      final masks = {'m': maskRect()};
      for (final approximate in [false, true]) {
        final root = _root([target()]);
        final start = await _render(
          root,
          _ms(0),
          masks: masks,
          approximate: approximate,
        );
        expect(alphaAt(start, 50, 50), 255, reason: 'approx=$approximate');
        final end = await _render(
          root,
          _ms(1000),
          masks: masks,
          approximate: approximate,
        );
        expect(alphaAt(end, 50, 50), 0, reason: 'approx=$approximate');
        final back = await _render(
          root,
          _ms(0),
          masks: masks,
          approximate: approximate,
        );
        _expectSamePixels(back, start, 'approx=$approximate 回到起点');
      }
    });

    test('mask 内列表动画（无描边，无可见效果）近似与精确一致', () async {
      final masks = {
        'm': maskRect(lists: [_list()]),
      };
      final exact = await _render(_root([target()]), _ms(500), masks: masks);
      final approx = await _render(
        _root([target()]),
        _ms(500),
        masks: masks,
        approximate: true,
      );
      _expectSamePixels(approx, exact, '列表动画不改变覆盖度');
      expect(alphaAt(exact, 50, 50), 255);
    });
  });

  group('零分配快路径', () {
    test('没有任何动画的节点原样返回自己的属性表', () {
      final node = _pathNode();
      _paint(_root([node]), _ms(500));
      expect(node.cachedAnimatedAttributes, isNull);
      expect(node.animatedSampleKey, isNull);
    });
  });
}
