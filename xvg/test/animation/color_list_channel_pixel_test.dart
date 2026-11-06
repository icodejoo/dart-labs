// P4-4：颜色通道与列表通道在 painter 里的像素级验证。节点全部手工构造（不经过
// 解析器/编译器），直接把 [SmilColorAnimation]/[SmilListAnimation] 挂到
// [SvgNode] 上，再用 renderRootAt 渲染。

import 'dart:typed_data';

import 'package:flutter/painting.dart' show TileMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/smil_animation.dart';
import 'package:xvg/src/animation/svg_dom.dart';
import 'package:xvg/src/animation/svg_gradient.dart';

import 'pixel_test_utils.dart';

/// 单次动画时长。
const Duration _second = Duration(seconds: 1);

/// 纯红（0xAARRGGBB）。
const int _red = 0xFFFF0000;

/// 纯蓝（0xAARRGGBB）。
const int _blue = 0xFF0000FF;

/// SVGator 样本 225 里的橙色。
const int _orange = 0xFFDD753D;

/// 毫秒转时间。
Duration _ms(int ms) => Duration(milliseconds: ms);

/// 把 [children] 包进根节点。
SvgNode _root(List<SvgNode> children) =>
    SvgNode(kind: SvgNodeKind.root, attributes: const {}, children: children);

/// 构造颜色动画，默认定格、线性、作用于 `fill`。
SmilColorAnimation _color(
  List<int> values, {
  String attribute = 'fill',
  Duration begin = Duration.zero,
  bool freeze = true,
  List<SmilSegmentEasing>? keySplines,
}) => SmilColorAnimation(
  attributeName: attribute,
  values: values,
  duration: _second,
  begin: begin,
  fillFreeze: freeze,
  keySplines: keySplines,
);

/// 构造一个 (10,10) 起、40x40 的矩形，带颜色动画与额外属性。
SvgNode _rect(
  List<SmilColorAnimation> colors, {
  Map<String, String> extra = const {},
}) => SvgNode(
  kind: SvgNodeKind.rect,
  attributes: {
    'x': '10',
    'y': '10',
    'width': '40',
    'height': '40',
    'fill': '#00ff00',
    ...extra,
  },
  colorAnimations: colors,
);

/// ([x], [y]) 处的 RGBA。
List<int> _rgba(ByteData p, int x, int y) {
  final base = (y * kPixelSize + x) * 4;
  return [for (var i = 0; i < 4; i++) p.getUint8(base + i)];
}

/// 矩形中心像素的 RGBA。
List<int> _center(ByteData p) => _rgba(p, 30, 30);

/// 构造 y=50 的水平描边线，带列表动画与可选数值动画。
SvgNode _line({
  required List<SmilListAnimation> lists,
  List<SmilAnimation> numeric = const [],
  Map<String, String> extra = const {},
}) => SvgNode(
  kind: SvgNodeKind.line,
  attributes: {
    'x1': '0',
    'y1': '50',
    'x2': '100',
    'y2': '50',
    'stroke': '#ff0000',
    'stroke-width': '10',
    ...extra,
  },
  listAnimations: lists,
  animations: numeric,
);

/// 构造 `stroke-dasharray` 列表动画（1 秒、定格）。
SmilListAnimation _dash(List<List<double>> values) => SmilListAnimation(
  attributeName: 'stroke-dasharray',
  values: values,
  duration: _second,
  begin: Duration.zero,
  fillFreeze: true,
);

/// 沿 y=50 读出每个 x 是否有色（alpha>200；虚线间隙里引擎本身会留下 alpha≈128 的底色，不计入）。
List<bool> _runs(ByteData p) => [
  for (var x = 0; x < kPixelSize; x++) alphaAt(p, x, 50) > 200,
];

/// 断言实测掩码与 [on] 判定一致；边缘 ±1 像素容忍抗锯齿。
void _expectPattern(List<bool> runs, bool Function(int x) on) {
  for (var x = 0; x < kPixelSize; x++) {
    final near = [-1, 0, 1].any((d) {
      final n = x + d;
      return n >= 0 && n < kPixelSize && on(n) != on(x);
    });
    if (near) continue;
    expect(runs[x], on(x), reason: 'x=$x');
  }
}

void main() {
  group('颜色通道：形状 fill', () {
    test('红到蓝中点约为 (128,0,128)', () async {
      final node = _rect([
        _color([_red, _blue]),
      ]);
      final c = _center(await renderRootAt(_root([node]), _ms(500)));
      expect(c[0], closeTo(128, 2));
      expect(c[1], closeTo(0, 2));
      expect(c[2], closeTo(128, 2));
      expect(c[3], 255);
    });

    test('fill 在颜色与 none 之间：翻转点前后一个有色一个透明', () async {
      final node = _rect([
        _color([_orange, kSmilColorNone]),
      ]);
      final root = _root([node]);
      final before = _center(await renderRootAt(root, _ms(300)));
      expect(before.sublist(0, 3), [0xDD, 0x75, 0x3D]);
      expect(before[3], 255);
      final after = _center(await renderRootAt(root, _ms(700)));
      expect(after[3], 0);
    });

    test('多段 #dd753d -> none -> none -> #dd753d', () async {
      final node = _rect([
        _color([_orange, kSmilColorNone, kSmilColorNone, _orange]),
      ]);
      final root = _root([node]);
      // 三段各 1/3；首段约在 1/6 处翻到 none，末段约在 5/6 处翻回。
      final alphas = <int>[];
      for (final ms in [100, 250, 500, 750, 900]) {
        alphas.add(_center(await renderRootAt(root, _ms(ms)))[3]);
      }
      expect(alphas, [255, 0, 0, 0, 255]);
    });

    test('stroke 颜色动画', () async {
      final node = _rect(
        [
          _color([_red, _blue], attribute: 'stroke'),
        ],
        extra: {'fill': 'none', 'stroke': '#00ff00', 'stroke-width': '10'},
      );
      // 描边中心线在 x=10。
      final p = await renderRootAt(_root([node]), _ms(500));
      final c = _rgba(p, 10, 30);
      expect(c[0], closeTo(128, 2));
      expect(c[2], closeTo(128, 2));
      expect(_center(p)[3], 0, reason: 'fill=none 内部应透明');
    });

    test('fill-opacity 与 opacity 同时作用，最终 alpha 相乘', () async {
      final node = _rect(
        [
          _color([_red, _blue]),
        ],
        extra: {'fill-opacity': '0.5', 'opacity': '0.5'},
      );
      final c = _center(await renderRootAt(_root([node]), _ms(500)));
      expect(c[3], closeTo(64, 2));
    });

    test('颜色自带 alpha 与 opacity 相乘', () async {
      final node = _rect(
        [
          _color([0x80FF0000, 0x80FF0000]),
        ],
        extra: {'opacity': '0.5'},
      );
      final c = _center(await renderRootAt(_root([node]), _ms(500)));
      expect(c[3], closeTo(64, 2));
    });

    test('结束且不定格后回到静态 fill', () async {
      final node = _rect([
        _color([_red, _blue], freeze: false),
      ]);
      final c = _center(await renderRootAt(_root([node]), _ms(2000)));
      expect(c.sublist(0, 3), [0, 255, 0]);
    });

    test('定格时停在终值', () async {
      final node = _rect([
        _color([_red, _blue]),
      ]);
      final c = _center(await renderRootAt(_root([node]), _ms(2000)));
      expect(c.sublist(0, 3), [0, 0, 255]);
    });

    test('delay 内显示静态 fill', () async {
      final node = _rect([
        _color([_red, _blue], begin: _second),
      ]);
      final root = _root([node]);
      expect(_center(await renderRootAt(root, _ms(500))).sublist(0, 3), [
        0,
        255,
        0,
      ]);
      expect(_center(await renderRootAt(root, _ms(1000))).sublist(0, 3), [
        255,
        0,
        0,
      ]);
    });

    test('回弹缓动逐通道钳制（冒烟：不抛异常、保持不透明）', () async {
      final node = _rect([
        _color(
          [_red, _blue],
          keySplines: const [CubicBezier(0.175, 0.885, 0.32, 1.275)],
        ),
      ]);
      final root = _root([node]);
      for (final ms in [100, 300, 500, 700, 900]) {
        final c = _center(await renderRootAt(root, _ms(ms)));
        expect(c[3], 255, reason: 'ms=$ms');
      }
    });

    test('颜色动画驱动 text 的 fill，TextPainter 缓存随之重建', () async {
      final node = SvgNode(
        kind: SvgNodeKind.text,
        attributes: const {
          'x': '10',
          'y': '70',
          'font-size': '60',
          'fill': '#00ff00',
        },
        textContent: 'I',
        colorAnimations: [
          _color([_red, _blue]),
        ],
      );
      final root = _root([node]);
      // 数指定通道占优的不透明像素。
      int count(ByteData p, int channel) {
        var n = 0;
        for (var y = 0; y < kPixelSize; y++) {
          for (var x = 0; x < kPixelSize; x++) {
            final c = _rgba(p, x, y);
            if (c[3] > 200 && c[channel] > 200) n++;
          }
        }
        return n;
      }

      final start = await renderRootAt(root, _ms(0));
      expect(count(start, 0), greaterThan(0));
      expect(count(start, 2), 0);
      final end = await renderRootAt(root, _ms(1000));
      expect(count(end, 2), greaterThan(0));
      expect(count(end, 0), 0);
      // 再回到起点：缓存不得停留在终值。
      final again = await renderRootAt(root, _ms(0));
      expect(count(again, 0), greaterThan(0));
      expect(count(again, 2), 0);
    });
  });

  group('颜色通道：渐变 stop', () {
    /// 带 stop-color 属性的 stop 节点。
    SvgNode stopNode(List<SmilColorAnimation> colors) => SvgNode(
      kind: SvgNodeKind.group,
      attributes: const {'offset': '0', 'stop-color': '#00ff00'},
      colorAnimations: colors,
    );

    /// 两色标渐变定义，首个 stop 节点为 [node]。
    SvgGradientDef def(SvgNode node) => SvgGradientDef(
      radial: false,
      stops: [
        stopFromAttributes(node.attributes)!,
        stopFromAttributes(const {'offset': '1', 'stop-color': '#000000'})!,
      ],
      objectBoundingBox: true,
      tileMode: TileMode.clamp,
      stopNodes: [
        node,
        SvgNode(
          kind: SvgNodeKind.group,
          attributes: const {'offset': '1', 'stop-color': '#000000'},
        ),
      ],
      animatedNode: SvgNode(kind: SvgNodeKind.group, attributes: const {}),
    );

    test('stop-color 动画照常重采样', () {
      final node = stopNode([
        _color([_red, _blue], attribute: 'stop-color'),
      ]);
      final c = resampleGradientAtTime(def(node), _ms(500)).stops.first.color;
      expect((c.r * 255).round(), closeTo(128, 2));
      expect((c.b * 255).round(), closeTo(128, 2));
    });

    test('attributeName 为 fill 的颜色动画挂在 stop 上被忽略', () {
      final node = stopNode([
        _color([_red, _blue]),
      ]);
      final c = resampleGradientAtTime(def(node), _ms(500)).stops.first.color;
      // 保持静态 #00ff00。
      expect((c.g * 255).round(), 255);
      expect((c.r * 255).round(), 0);
    });

    test('stop 上的 none 哨兵被跳过而不是变白', () {
      final node = stopNode([
        _color([kSmilColorNone, kSmilColorNone], attribute: 'stop-color'),
      ]);
      final c = resampleGradientAtTime(def(node), _ms(500)).stops.first.color;
      expect((c.g * 255).round(), 255);
      expect((c.r * 255).round(), 0, reason: '不应变成白色');
    });

    test('smilColorToHex 把 AARRGGBB 重排成 #RRGGBBAA', () {
      expect(smilColorToHex(0xFFFF0000), '#FF0000FF');
      expect(smilColorToHex(0x80112233), '#11223380');
    });
  });

  group('列表通道：stroke-dasharray', () {
    test('三个时刻的虚线图案符合手算', () async {
      final root = _root([
        _line(
          lists: [
            _dash([
              [10, 10],
              [20, 40],
            ]),
          ],
        ),
      ]);
      _expectPattern(
        _runs(await renderRootAt(root, _ms(0))),
        (x) => x % 20 < 10,
      );
      _expectPattern(
        _runs(await renderRootAt(root, _ms(1000))),
        (x) => x % 60 < 20,
      );
      // 中点 [15,25]：周期 40，前 15 有色。
      _expectPattern(
        _runs(await renderRootAt(root, _ms(500))),
        (x) => x % 40 < 15,
      );
    });

    test('与 stroke-dashoffset 数值动画同时作用互不影响', () async {
      final root = _root([
        _line(
          lists: [
            _dash([
              [10, 10],
              [20, 20],
            ]),
          ],
          numeric: [
            SmilAnimation(
              attributeName: 'stroke-dashoffset',
              values: const [0, 5],
              duration: _second,
              begin: Duration.zero,
              fillFreeze: true,
            ),
          ],
        ),
      ]);
      // t=1s：dasharray=[20,20]，dashoffset=5 -> (x+5)%40<20 为有色。
      _expectPattern(
        _runs(await renderRootAt(root, _ms(1000))),
        (x) => (x + 5) % 40 < 20,
      );
    });

    test('奇数长度列表 [10]->[20] 按 SVG 规则翻倍', () async {
      final root = _root([
        _line(
          lists: [
            _dash([
              [10],
              [20],
            ]),
          ],
        ),
      ]);
      _expectPattern(
        _runs(await renderRootAt(root, _ms(1000))),
        (x) => x % 40 < 20,
      );
    });

    test('动画结束且不定格后回到静态 dasharray', () async {
      final anim = SmilListAnimation(
        attributeName: 'stroke-dasharray',
        values: const [
          [20, 40],
          [20, 40],
        ],
        duration: _second,
        begin: Duration.zero,
        fillFreeze: false,
      );
      final root = _root([
        _line(lists: [anim], extra: {'stroke-dasharray': '10 10'}),
      ]);
      _expectPattern(
        _runs(await renderRootAt(root, _ms(2000))),
        (x) => x % 20 < 10,
      );
    });
  });
}
