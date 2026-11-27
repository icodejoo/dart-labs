import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_theme.dart';
import 'package:xvg/xvg.dart' show RustLib, RustXvgPictureCache;

/// Test viewport side. / 测试视口边长。
const _side = 100;
const _red = 0xff0000ff;
const _blue = 0x0000ffff;
const _black = 0x000000ff;
const _clear = 0;
const _half = Duration(milliseconds: 500);

/// Wraps test markup in an SVG viewport. / 为测试内容添加 SVG 视口。
String _svg(String body, [String viewport = 'width="100" height="100"']) =>
    '<svg xmlns="http://www.w3.org/2000/svg" $viewport>$body</svg>';

/// Records SVG and reads interior RGBA pixels. / 录制 SVG 并读取内部 RGBA 像素。
Future<ByteData> _render(
  String body, {
  Duration time = Duration.zero,
  String? viewport,
  bool approximateMasks = false,
}) async {
  final doc = parseAnimatedSvgDocument(
    viewport == null ? _svg(body) : _svg(body, viewport),
  );
  await resolveImageNodes(doc);
  final recorder = ui.PictureRecorder();
  final clock = ValueNotifier(time);
  AnimatedSvgPainter(
    root: doc.root,
    intrinsicSize: Size(doc.width, doc.height),
    rootViewBoxTransform: doc.rootViewBoxTransform,
    clock: clock,
    theme: const XvgTheme(currentColor: Color(0xff00ff00)),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    gradients: doc.gradients,
    clipPaths: doc.clipPaths,
    masks: doc.masks,
    approximateMasks: () => approximateMasks,
  ).paint(Canvas(recorder), const Size.square(100));
  clock.dispose();
  final picture = recorder.endRecording();
  final image = await picture.toImage(_side, _side);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Checks pixels away from antialiased boundaries. / 比对远离抗锯齿边界的像素。
void _pixel(ByteData data, int x, int y, int rgba) =>
    expect(data.getUint32((y * _side + x) * 4), rgba, reason: '($x, $y)');

/// Samples a single numeric timeline. / 采样单条数值时间线。
double? _sample(String attrs, Duration time) => parseAnimatedSvgDocument(
  _svg('<rect x="20"><animate attributeName="x" dur="1s" $attrs/></rect>'),
).root.children.single.animations.firstOrNull?.sample(time);

void main() {
  setUpAll(RustLib.init);

  test('q03 v06b viewport lengths and normalized diagonal stroke', () async {
    final data = await _render(
      '<rect x="10px" y="20%" width="5mm" height="2em" fill="#f00"/>'
      '<line x1="50%" x2="90%" y1="50pt" y2="50pt" stroke="#00f" stroke-width="10%"/>',
    );
    _pixel(data, 26, 46, _red);
    _pixel(data, 31, 46, _clear);
    _pixel(data, 70, 70, _blue);
    _pixel(data, 70, 73, _clear);
  });

  test(
    'q03 percentages use the nearest non-square user-space viewBox',
    () async {
      final data = await _render(
        '<circle cx="50%" cy="50%" r="10%" fill="#f00"/>',
        viewport: 'width="100" height="100" viewBox="0 0 200 100" preserveAspectRatio="none"',
      );
      _pixel(data, 50, 64, _red);
      _pixel(data, 50, 67, _clear);
      _pixel(data, 56, 50, _red);
      _pixel(data, 60, 50, _clear);
    },
  );

  test('y01 font size resolves px, em, and inherited percentages', () async {
    final actual = await _render(
      '<g font-size="20px"><text x="10" y="65" font-size="2em">X</text>'
      '<text x="60" y="65" font-size="200%">X</text></g>',
    );
    final expected = await _render(
      '<text x="10" y="65" font-size="40">X</text>'
      '<text x="60" y="65" font-size="40">X</text>',
    );
    expect(actual.buffer.asUint8List(), expected.buffer.asUint8List());
  });

  test('v07 nested svg maps its viewBox and clips overflow', () async {
    final data = await _render(
      '<svg x="20" y="10" width="60" height="30" viewBox="0 0 10 10">'
      '<rect x="-10" width="30" height="100%" fill="#f00"/></svg>'
      '<svg x="20" y="60" width="25" height="10" overflow="visible">'
      '<rect x="-5" y="-5" width="30" height="20" fill="#00f"/></svg>',
    );
    _pixel(data, 70, 20, _red);
    _pixel(data, 15, 20, _clear);
    _pixel(data, 17, 56, _blue);
  });

  test('v08 w11 use supplies symbol and svg viewport sizes', () async {
    final data = await _render(
      '<defs><symbol id="s" viewBox="0 0 10 10" preserveAspectRatio="xMinYMin meet">'
      '<rect x="-5" width="30" height="10" fill="#f00"/></symbol>'
      '<svg id="v" width="20" height="20" viewBox="0 0 10 10">'
      '<rect width="10" height="10" fill="#00f"/></svg></defs>'
      '<use href="#s" x="10%" y="10" width="30" height="20"/>'
      '<use href="#v" x="50" y="40" width="40" height="30"/>',
    );
    _pixel(data, 35, 24, _red);
    _pixel(data, 7, 24, _clear);
    _pixel(data, 45, 24, _clear);
    _pixel(data, 79, 65, _blue);
    _pixel(data, 52, 65, _clear);
  });

  test('e04 q06 switch selects the first eligible link', () async {
    final data = await _render(
      '<switch><rect requiredExtensions="urn:unsupported" width="100" height="100"/>'
      '<a fill="#f00"><rect width="30" height="30"/></a>'
      '<rect width="100" height="100" fill="#00f"/></switch>',
    );
    _pixel(data, 15, 15, _red);
    _pixel(data, 50, 15, _clear);
  });

  test('q07 tspan preserves style and x y dx dy positions', () async {
    final actual = await _render(
      '<text font-size="20" fill="#f00" x="5" y="30">A'
      '<tspan fill="#00f" x="40" y="50" dx="5" dy="7">B</tspan></text>',
    );
    final expected = await _render(
      '<text font-size="20" fill="#f00" x="5" y="30">A</text>'
      '<text font-size="20" fill="#00f" x="45" y="57">B</text>',
    );
    expect(actual.buffer.asUint8List(), expected.buffer.asUint8List());
  });

  test('q07 text-anchor applies to a positioned chunk of spans', () async {
    final singleGlyph = TextPainter(
      text: const TextSpan(text: 'H', style: TextStyle(fontSize: 20)),
      textDirection: TextDirection.ltr,
    )..layout();
    final firstX = 50 - singleGlyph.width;
    singleGlyph.dispose();
    final actual = await _render(
      '<text font-size="20" x="50" y="45" text-anchor="middle" fill="#f00">'
      '<tspan>H</tspan><tspan fill="#00f">H</tspan></text>',
    );
    final expected = await _render(
      '<text font-size="20" x="$firstX" y="45" fill="#f00">H</text>'
      '<text font-size="20" x="50" y="45" fill="#00f">H</text>',
    );
    expect(actual.buffer.asUint8List(), expected.buffer.asUint8List());
  });

  test('p09 objectBoundingBox clip uses target geometry', () async {
    final data = await _render(
      '<defs><clipPath id="c" clipPathUnits="objectBoundingBox">'
      '<rect width="50%" height="1"/></clipPath></defs>'
      '<rect x="20" y="20" width="60" height="30" fill="#f00" clip-path="url(#c)"/>',
    );
    _pixel(data, 42, 30, _red);
    _pixel(data, 65, 30, _clear);
  });

  test('p09 p10 mask content and explicit regions use their own units', () async {
    final data = await _render(
      '<defs><mask id="a" x="0" y="0" width=".5" height="1" maskContentUnits="objectBoundingBox">'
      '<rect x=".25" width=".75" height="1" fill="#fff"/></mask>'
      '<mask id="b" maskUnits="userSpaceOnUse" x="40%" y="0" width="30%" height="100">'
      '<rect width="100" height="100" fill="#fff"/></mask></defs>'
      '<rect x="20" y="10" width="60" height="30" fill="#f00" mask="url(#a)"/>'
      '<rect x="20" y="50" width="60" height="30" fill="#00f" mask="url(#b)"/>',
    );
    _pixel(data, 40, 25, _red);
    _pixel(data, 29, 25, _clear);
    _pixel(data, 55, 25, _clear);
    _pixel(data, 60, 60, _blue);
    _pixel(data, 75, 60, _clear);
  });

  test(
    'p10 exact and approximate masks enforce the same explicit region',
    () async {
      const body =
          '<defs><mask id="m" maskUnits="userSpaceOnUse" x="20" y="10" width="40" height="50">'
          '<rect width="100" height="100" fill="#fff"/></mask></defs>'
          '<rect width="100" height="100" fill="#f00" mask="url(#m)"/>';
      for (final approximate in [false, true]) {
        final data = await _render(body, approximateMasks: approximate);
        _pixel(data, 40, 25, _red);
        _pixel(data, 15, 25, _clear);
        _pixel(data, 65, 25, _clear);
      }
    },
  );

  test('w13 clipPath intersects its own clip-path', () async {
    final data = await _render(
      '<defs><clipPath id="a" clip-path="url(#b)"><rect width="60" height="50"/></clipPath>'
      '<clipPath id="b"><rect x="20" width="20" height="50"/></clipPath></defs>'
      '<rect width="100" height="100" fill="#f00" clip-path="url(#a)"/>',
    );
    _pixel(data, 30, 20, _red);
    _pixel(data, 10, 20, _clear);
  });

  test('p04 paint-order puts inherited stroke before fill', () async {
    final data = await _render(
      '<g style="paint-order:stroke markers" fill="#f00" stroke="#00f" stroke-width="12">'
      '<rect x="20" y="20" width="40" height="40"/></g>',
    );
    _pixel(data, 22, 35, _red);
    _pixel(data, 16, 35, _blue);
  });

  test(
    'p05 e02 w15 resolves currentColor, paint fallbacks and inherit',
    () async {
      final data = await _render(
        '<style>.base{fill:#f00}</style>'
        '<g color="#f00" fill="currentColor"><rect width="20" height="20"/>'
        '<rect x="20" width="20" height="20" style="color:#00f;fill:inherit"/></g>'
        '<rect x="40" width="20" height="20" fill="currentColor"/>'
        '<rect x="60" width="20" height="20" fill="url(#missing) #00f"/>'
        '<rect x="80" width="20" height="20" class="base" style="fill:#xyz"/>'
        '<rect y="30" width="20" height="20" fill="garbage"/>',
      );
      _pixel(data, 10, 10, _red);
      _pixel(data, 30, 10, _blue);
      _pixel(data, 50, 10, 0x00ff00ff);
      _pixel(data, 70, 10, _blue);
      _pixel(data, 90, 10, _red);
      _pixel(data, 10, 40, _black);
    },
  );

  test('q08 image defaults to centered meet and supports slice', () async {
    const png =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAAD0lEQVR4nGP4z8DAwPAfAAcAAf9+CLHQAAAAAElFTkSuQmCC';
    final data = await _render(
      '<image href="$png" x="10" y="10" width="30" height="30"/>'
      '<image href="$png" x="50" y="10" width="30" height="30" preserveAspectRatio="xMaxYMax slice"/>'
      '<image href="$png" x="10" y="50" width="30" height="30" preserveAspectRatio="none"/>',
    );
    _pixel(data, 15, 12, _clear);
    _pixel(data, 15, 20, _red);
    _pixel(data, 55, 12, _blue);
    _pixel(data, 85, 25, _clear);
    _pixel(data, 15, 52, _red);
  });

  test('v01 missing intrinsic dimensions use 300 by 150', () {
    final source = _svg('<rect width="500" height="400"/>', '');
    final doc = parseAnimatedSvgDocument(source);
    final staticSize = RustXvgPictureCache.instance.getOrRender(source).size;
    debugPrint('v01 Rust intrinsic size: $staticSize');
    expect(Size(doc.width, doc.height), const Size(300, 150));
  });

  test('a01 additive sum, by and from-by sample the SVG sandwich', () async {
    const time = _half;
    final data = await _render(
      '<rect x="20" y="10" width="5" height="10" fill="#f00">'
      '<animate attributeName="x" from="0" to="40" dur="1s" additive="sum"/></rect>'
      '<rect x="20" y="30" width="5" height="10" fill="#f00">'
      '<animate attributeName="x" by="40" dur="1s"/></rect>'
      '<rect x="20" y="50" width="5" height="10" fill="#f00">'
      '<animate attributeName="x" from="10" by="40" dur="1s"/></rect>',
      time: time,
    );
    _pixel(data, 42, 15, _red);
    _pixel(data, 42, 35, _red);
    _pixel(data, 32, 55, _red);
  });

  test('a03 accumulate and fractional repeatDur freeze', () {
    const time = Duration(milliseconds: 2300);
    expect(
      _sample('from="10" to="40" repeatCount="3" accumulate="sum"', time),
      99,
    );
    expect(
      _sample('from="0" to="40" repeatDur="2.5s" fill="freeze"', time),
      closeTo(12, .001),
    );
    expect(
      _sample(
        'from="0" to="40" repeatDur="2.5s" fill="freeze"',
        const Duration(seconds: 3),
      ),
      20,
    );
  });

  test('a15 animateTransform defaults to replace', () async {
    final data = await _render(
      '<rect x="10" y="10" width="10" height="10" fill="#f00">'
      '<animateTransform attributeName="transform" type="translate" from="0" to="60" dur="1s"/>'
      '<animateTransform attributeName="transform" type="scale" from="1" to="3" dur="1s"/></rect>',
      time: _half,
    );
    _pixel(data, 25, 25, _red);
    _pixel(data, 55, 25, _clear);
  });

  test('a02 a03 transform sums keep the base and accumulate the terminal parameters', () async {
    final body =
        '<rect x="5" y="10" width="5" height="10" fill="#f00" transform="translate(20)">'
        '<animateTransform attributeName="transform" type="translate" by="20" dur="1s" additive="sum"/>'
        '</rect><rect x="5" y="30" width="5" height="5" fill="#00f">'
        '<animateTransform attributeName="transform" type="translate" from="0" to="20" dur="1s" '
        'repeatCount="2" fill="freeze" accumulate="sum"/></rect>';
    _pixel(await _render(body, time: _half), 37, 15, _red);
    _pixel(
      await _render(body, time: const Duration(milliseconds: 1500)),
      37,
      32,
      _blue,
    );
  });

  test('a05 a06 invalid keyTimes and keySplines disable the animation', () {
    for (final attrs in [
      'values="20;60;80" keyTimes="0;1"',
      'values="20;60" keyTimes="0.2;1"',
      'values="20;60;80" keyTimes="0;.8;.5"',
      'values="20;60" calcMode="spline" keyTimes="0;1" keySplines=".5 2 .5 -1"',
      'values="20;60" calcMode="spline" keyTimes="0;1"',
    ]) {
      expect(_sample(attrs, _half), isNull, reason: attrs);
    }
  });

  test('a04 single begin honors explicit end, min, and max', () {
    const time = Duration(seconds: 2);
    expect(
      _sample('from="10" to="100" begin=".5s" end="1s" fill="freeze"', time),
      55,
    );
    expect(_sample('from="0" to="100" max=".25s" fill="freeze"', time), 25);
    expect(
      _sample('from="0" to="100" min="2s"', const Duration(milliseconds: 1500)),
      isNull,
    );
    expect(
      _sample(
        'from="0" to="100" min="2s" fill="freeze"',
        const Duration(milliseconds: 1500),
      ),
      100,
    );
  });

  test('a11 points keyframes animate polygon geometry', () async {
    final data = await _render(
      '<polygon fill="#f00" points="0,0 20,0 0,20"><animate attributeName="points"'
      ' values="0,0 20,0 0,20;40,0 60,0 40,20" dur="1s"/></polygon>',
      time: _half,
    );
    _pixel(data, 24, 4, _red);
    _pixel(data, 4, 4, _clear);
  });

  test(
    'a13 w14 pathLength scales percentage dash lengths and offset',
    () async {
      final data = await _render(
        '<path fill="none" d="M0 40H100" stroke="#00f" stroke-width="4" stroke-dasharray="10%" pathLength="50"/>'
        '<path fill="none" d="M0 70H100" stroke="#00f" stroke-width="4" '
        'stroke-dasharray="10" stroke-dashoffset="5" pathLength="50"/>',
      );
      _pixel(data, 16, 40, _blue);
      _pixel(data, 30, 40, _clear);
      _pixel(data, 7, 70, _blue);
      _pixel(data, 15, 70, _clear);
    },
  );

  test(
    'a13 dasharray keyframes interpolate lists and retain percentage units',
    () async {
      final data = await _render(
        '<path fill="none" d="M0 70H100" stroke="#00f" stroke-width="4" stroke-dasharray="5 35">'
        '<animate attributeName="stroke-dasharray" values="5% 35;35% 5" dur="1s"/></path>',
        time: _half,
      );
      _pixel(data, 15, 70, _blue);
      _pixel(data, 30, 70, _clear);
    },
  );
}
