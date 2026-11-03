import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/css_animation_values.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/css_stylesheet.dart';
import 'package:svgx/svgx.dart' show RustLib;

import 'pixel_test_utils.dart';

/// 给测试片段补上根元素。
SvgDocument _parse(String body) => parseAnimatedSvgDocument('<svg>$body</svg>');

/// 原生库是否已成功加载；在文件级 [setUpAll] 里一次性尝试初始化。
bool _nativeReady = false;

/// 验证样式表接入属性、定义、实例及像素路径。
void main() {
  // 原生库必须在解析任何文档之前初始化：封装层一旦在未初始化时调用失败，就会记住
  // "原生不可用"，之后即使初始化成功也不再调用（生产里应用启动时就已初始化）。
  // flutter_rust_bridge 同一进程内只能初始化一次，所以整个文件只在这里尝试一次。
  setUpAll(() async {
    try {
      await RustLib.init();
      _nativeReady = true;
    } catch (_) {
      _nativeReady = false;
    }
  });

  final cases = <(String, String, String)>[
    ('<style>#r{fill:#f00}</style>', '<rect id="r"/>', '#f00'),
    ('<style>#r{fill:#f00}</style>', '<rect id="r" fill="#00f"/>', '#f00'),
    (
      '<style>#r{fill:#f00}</style>',
      '<rect id="r" style="fill:#0f0"/>',
      '#0f0',
    ),
    (
      '<style>#r{fill:#f00!important}</style>',
      '<rect id="r" style="fill:#0f0"/>',
      '#f00',
    ),
    (
      '<style>#r{fill:#f00!important}</style>',
      '<rect id="r" style="fill:#0f0!important"/>',
      '#0f0',
    ),
    (
      '<style>#r{fill:#f00}</style><style>#r{fill:#00f}</style>',
      '<rect id="r"/>',
      '#00f',
    ),
    ('<defs><style>#r{fill:#f00}</style></defs>', '<rect id="r"/>', '#f00'),
    ('<style><![CDATA[#r{fill:#f00}]]></style>', '<rect id="r"/>', '#f00'),
    (
      '<style type="text/foo">#r{fill:#f00}</style>',
      '<rect id="r" fill="#abc"/>',
      '#abc',
    ),
    (
      '<style media="print">#r{fill:#f00}</style>',
      '<rect id="r" fill="#abc"/>',
      '#abc',
    ),
    (
      '<style type=" Text/CSS " media=" SCREEN ">#r{fill:#f00}</style>',
      '<rect id="r"/>',
      '#f00',
    ),
    (
      '<style type=" " media=" ">#r{fill:#f00}</style>',
      '<rect id="r"/>',
      '#f00',
    ),
    ('<style media="all">#r{fill:#f00}</style>', '<rect id="r"/>', '#f00'),
    ('<style>*{fill:#f00}</style>', '<rect id="r" fill="#abc"/>', '#f00'),
    (
      '<style>#r:hover{fill:#f00}</style>',
      '<rect id="r" fill="#abc"/>',
      '#abc',
    ),
    ('', '<rect id="r" style="fill:#f00"/>', '#f00'),
    (
      '<style>#r{fill:inherit;stroke-width:initial}</style>',
      '<rect id="r" fill="#abc"/>',
      '#abc',
    ),
  ];
  for (var i = 0; i < cases.length; i++) {
    test('样式块与行内层叠 $i', () {
      final c = cases[i];
      final node = _parse('${c.$1}${c.$2}').root.children.single;
      expect(node.attributes['fill'], c.$3);
    });
  }
  test('后置样式块同样参与全文层叠', () {
    final doc = _parse(
      '<style>#r{opacity:.1}</style><rect id="r"/>'
      '<defs><style>#r{opacity:.8}</style></defs>',
    );
    expect(doc.root.children.single.attributes['opacity'], '.8');
    expect(doc.root.children, hasLength(1));
  });
  test('class、后代与子代规则', () {
    final doc = _parse(
      '<style>.g rect{fill:#f00}.g > rect{stroke:#0f0}.a.b{opacity:.3}</style>'
      '<g class="g"><rect class="a b"/><g><rect/></g></g>',
    );
    final group = doc.root.children.single;
    expect(group.children.first.attributes['fill'], '#f00');
    expect(group.children.first.attributes['stroke'], '#0f0');
    expect(group.children.first.attributes['opacity'], '.3');
    expect(group.children.last.children.single.attributes['fill'], '#f00');
    expect(group.children.last.children.single.attributes['stroke'], isNull);
  });
  test('渐变及色标的规则、行内样式与 href 继承', () {
    final doc = _parse(
      '<style>.g stop{stop-color:#f00;stop-opacity:.5}'
      '#g{x2:.75}#last{stop-opacity:.25!important}</style>'
      '<defs><linearGradient id="g" class="g">'
      '<stop offset="0" stop-color="#00f"/>'
      '<stop id="last" offset="1" style="stop-color:#0f0;stop-opacity:.8"/>'
      '</linearGradient><linearGradient id="copy" href="#g"/></defs>',
    );
    final gradient = doc.gradients['g']!;
    expect(gradient.x2, .75);
    expect(gradient.stops.first.color.r, 1);
    expect(gradient.stops.first.color.a, closeTo(.5, .01));
    expect(gradient.stops.last.color.g, 1);
    expect(gradient.stops.last.color.a, closeTo(.25, .01));
    expect(gradient.stopNodes.first.attributes['stop-color'], '#f00');
    expect(gradient.stopNodes.last.attributes['stop-opacity'], '.25');
    expect(doc.gradients['copy']!.x2, .75);
    expect(doc.gradients['copy']!.stops.first.color.r, 1);
  });
  test('use 的目标按原文档祖先匹配，包装节点保留自身样式', () {
    final doc = _parse(
      '<style>defs > rect{fill:#f00}g > rect{fill:#00f}'
      'use{stroke:#0f0;animation:unknown 1s}</style>'
      '<defs><rect id="target"/></defs>'
      '<g><use href="#target" style="opacity:.4;transform:translate(2px)"/></g>',
    );
    final wrapper = doc.root.children.single.children.single;
    expect(wrapper.attributes['stroke'], '#0f0');
    expect(wrapper.attributes['opacity'], '.4');
    expect(wrapper.cssProperties['transform'], 'translate(2px)');
    expect(wrapper.cssAnimations.single.name, 'unknown');
    expect(wrapper.children.single.attributes['fill'], '#f00');
  });
  test('动画配置与全部关键帧跨样式块保留，未知引用也保留', () {
    final doc = _parse(
      '<style>@keyframes fade{from{opacity:0}to{opacity:1}}'
      '#r{animation:fade 2s steps(4,end) -1s infinite alternate-reverse forwards paused, missing 3s}</style>'
      '<rect id="r"/><style>@keyframes fade{50%{opacity:.5}}</style>',
    );
    final node = doc.root.children.single;
    expect(node.cssAnimations, hasLength(2));
    final animation = node.cssAnimations.first;
    expect(animation.name, 'fade');
    expect(animation.duration, const Duration(seconds: 2));
    expect(animation.delay, const Duration(seconds: -1));
    expect(animation.timing, const CssTimingFunction.steps(4));
    expect(animation.iterationCount, double.infinity);
    expect(animation.direction, CssAnimationDirection.alternateReverse);
    expect(animation.fillMode, CssAnimationFillMode.forwards);
    expect(animation.paused, isTrue);
    expect(node.cssAnimations.last.name, 'missing');
    expect(doc.cssKeyframes['fade']!.stops.single.offset, .5);
    expect(doc.totalDuration, Duration.zero);
    expect(doc.hasIndefiniteLoop, isFalse);
  });
  test('只有关键帧没有规则也保留关键帧，行内动画可引用', () {
    final doc = _parse(
      '<style>@keyframes fade{to{opacity:0}}</style>'
      '<rect style="animation:fade 1s"/>',
    );
    expect(doc.cssKeyframes.keys, ['fade']);
    expect(doc.root.children.single.cssAnimations.single.name, 'fade');
  });
  test('CSS 专用值不会污染 SVG transform 与路径属性', () {
    final doc = _parse(
      '<style>#r{transform:translate(2px) rotate(3deg);'
      'offset-path:path("M0 0L1 1");d:path("M2 2L3 3");stroke-width:2px}</style>'
      '<path id="r" transform="translate(1 2)" d="M0 0L1 1"/>',
    );
    final node = doc.root.children.single;
    expect(node.attributes['transform'], 'translate(1 2)');
    expect(node.attributes['d'], 'M0 0L1 1');
    expect(node.attributes['stroke-width'], '2');
    expect(node.cssProperties, {
      'transform': 'translate(2px) rotate(3deg)',
      'offset-path': 'path("M0 0L1 1")',
      'd': 'path("M2 2L3 3")',
    });
  });
  test('CSS 命名颜色沿用现有原生规范化', () async {
    if (!_nativeReady) {
      markTestSkipped('原生库不可加载：把 prebuilt/windows/x64 放进 PATH 再跑');
      return;
    }
    final node = _parse('<style>rect{fill:red}</style><rect/>')
        .root
        .children
        .single;
    expect(node.attributes['fill'], '#FF0000FF');
  });
  test('无 CSS 及空 CSS 保持属性内容与共享空集合', () {
    for (final styles in [
      '',
      '<style>/* empty */</style>',
      '<style>#missing{opacity:0}</style>',
    ]) {
      final node = _parse('$styles<rect id="r" width="2" fill="#abc"/>')
          .root
          .children
          .single;
      expect(node.attributes, {'id': 'r', 'width': '2', 'fill': '#abc'});
      expect(identical(node.cssAnimations, const <CssAnimation>[]), isTrue);
      expect(identical(node.cssProperties, const <String, String>{}), isTrue);
    }
    expect(
      identical(_parse('<rect/>').cssKeyframes, const <String, CssKeyframes>{}),
      isTrue,
    );
  });
  test('CSS 不参与 SMIL 元素自身取值', () {
    final node = _parse(
      '<style>animate{dur:9s}</style><rect><animate attributeName="opacity" '
      'from="0" to="1" dur="1s"/></rect>',
    ).root.children.single;
    expect(node.animations.single.duration, const Duration(seconds: 1));
  });
  test('规则 fill-opacity 与行内 opacity 反映到像素', () async {
    final plain = parsePixelDoc(
      '<style>#r{fill:#f00;fill-opacity:.5}</style>'
      '<rect id="r" width="100" height="100"/>',
    );
    final pixels = await renderAt(plain, Duration.zero);
    expect(alphaAt(pixels, 50, 50), closeTo(128, 2));
    // rawRgba 存储预乘颜色，反算直通道后验证红色。
    expect(
      redAt(pixels, 50, 50) * 255 / alphaAt(pixels, 50, 50),
      closeTo(255, 2),
    );
    final inline = parsePixelDoc(
      '<style>#r{fill:#f00}</style>'
      '<rect id="r" width="100" height="100" style="opacity:.25"/>',
    );
    final faded = await renderAt(inline, Duration.zero);
    expect(alphaAt(faded, 50, 50), closeTo(64, 2));
    expect(
      redAt(faded, 50, 50) * 255 / alphaAt(faded, 50, 50),
      closeTo(255, 2),
    );
  });
  test('渐变后代选择器上色后像素改变', () async {
    final doc = parsePixelDoc(
      '<style>.g stop{stop-color:#f00}</style>'
      '<defs><linearGradient id="g" class="g"><stop offset="0" stop-color="#00f"/>'
      '<stop offset="1" stop-color="#00f"/></linearGradient></defs>'
      '<rect width="100" height="100" fill="url(#g)"/>',
    );
    final pixels = await renderAt(doc, Duration.zero);
    expect(alphaAt(pixels, 50, 50), 255);
    expect(redAt(pixels, 50, 50), 255);
    expect(doc.gradients['g']!.stops.first.color, const Color(0xffff0000));
  });
}
