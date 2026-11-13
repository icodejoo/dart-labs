import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_theme.dart';

const _wide = 'width="200" height="100"';
const _squareBox = 'viewBox="0 0 100 100"';
const _identity = <double>[1, 0, 0, 1, 0, 0];

/// Parses only root attributes. / 仅解析根属性。
SvgDocument _parse(String attributes) =>
    parseAnimatedSvgDocument('<svg $attributes/>');

/// Covers the plain numeric model and the identity paint fast path.
/// 覆盖纯数值模型及恒等映射绘制快路径。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final value in [
    '50 50 100 100',
    '50,50,100,100',
    ' 50 , 50  100, 100 ',
    '+5e1,5E1,1e2,100.',
    '50\t50\n100\r100',
  ]) {
    test('viewBox separators and number grammar: $value', () {
      final doc = _parse('width="200" height="200" viewBox="$value"');
      expect(doc.width, 200);
      expect(doc.height, 200);
      expect(doc.rootViewBoxTransform, [2, 0, 0, 2, -100, -100]);
      expect(() => doc.rootViewBoxTransform![0] = 3, throwsUnsupportedError);
    });
  }

  for (final value in [
    '',
    '0 0 100',
    '0 0 100 100 5',
    '0,,0,100,100',
    ',0 0 100 100',
    '0 0 100 100,',
    'x 0 100 100',
    '0 0 0 100',
    '0 0 100 0',
    '0 0 -1 100',
    '0 0 100 -1',
    'NaN 0 100 100',
    '0 Infinity 100 100',
    '0 0 1e999 100',
    '0 0 100px 100',
    '0 0 100-100',
  ]) {
    test('invalid viewBox is absent: $value', () {
      final doc = _parse('viewBox="$value"');
      expect((doc.width, doc.height), (24, 24));
      expect(doc.rootViewBoxTransform, isNull);
      expect(_parse('$_wide viewBox="$value"').rootViewBoxTransform, isNull);
    });
  }

  for (final (attributes, size) in [
    ('width="200px" height="100px"', (200.0, 100.0)),
    ('width=" +2e2px " height="100."', (200.0, 100.0)),
    ('width="200"', (200.0, 100.0)),
    ('height="200px"', (100.0, 200.0)),
    ('width="50%" height="4em"', (100.0, 100.0)),
    ('width="1cm" height="2pt"', (100.0, 100.0)),
    ('width="NaN" height="Infinity"', (100.0, 100.0)),
    ('width="1e999px" height="nope"', (100.0, 100.0)),
    ('width="0px" height="0"', (100.0, 100.0)),
  ]) {
    test('viewport lengths: $attributes', () {
      final doc = _parse('$attributes $_squareBox');
      expect((doc.width, doc.height), size);
    });
  }

  test('axis fallback is independent and legacy negative sizes stay empty', () {
    final doc = _parse('width="200px" height="50%"');
    expect((doc.width, doc.height), (200, 24));
    expect(_parse('width="-5"').width, -5);
    expect(_parse('').rootViewBoxTransform, isNull);
    expect(_parse(_squareBox).rootViewBoxTransform, isNull);
  });

  const factors = {'Min': 0.0, 'Mid': .5, 'Max': 1.0};
  for (final x in factors.entries) {
    for (final y in factors.entries) {
      final align = 'x${x.key}Y${y.key}';
      for (final mode in ['', ' meet', ' slice']) {
        for (final wide in [true, false]) {
          test('$align$mode in ${wide ? 'wide' : 'tall'} viewport', () {
            final dimensions = wide ? _wide : 'width="100" height="200"';
            final doc = _parse(
              '$dimensions $_squareBox preserveAspectRatio="$align$mode"',
            );
            final slice = mode == ' slice';
            final scale = slice ? 2.0 : 1.0;
            final gap = slice ? -100.0 : 100.0;
            final tx = wide != slice ? gap * x.value : 0.0;
            final ty = wide == slice ? gap * y.value : 0.0;
            expect(doc.rootViewBoxTransform ?? _identity, [
              scale,
              0,
              0,
              scale,
              tx,
              ty,
            ]);
          });
        }
      }
    }
  }

  for (final value in [
    'none',
    'none meet',
    'none slice',
    ' defer none slice ',
  ]) {
    test('independent scales: $value', () {
      expect(
        _parse('$_wide $_squareBox preserveAspectRatio="$value"')
            .rootViewBoxTransform,
        [2, 0, 0, 1, 0, 0],
      );
    });
  }
  for (final value in [
    '',
    'bogus',
    'xMinYMin invalid',
    'xMaxYMax slice extra',
    'meet',
    'NONE',
    'xmidymid',
    'xMinYMin,meet',
    'none invalid',
  ]) {
    test('invalid preserveAspectRatio defaults completely: $value', () {
      expect(
        _parse('$_wide $_squareBox preserveAspectRatio="$value"')
            .rootViewBoxTransform,
        [1, 0, 0, 1, 50, 0],
      );
    });
  }
  test('absent preserveAspectRatio defaults and no viewBox ignores it', () {
    expect(_parse('$_wide $_squareBox').rootViewBoxTransform, [
      1,
      0,
      0,
      1,
      50,
      0,
    ]);
    expect(
      _parse('$_wide preserveAspectRatio="none"').rootViewBoxTransform,
      isNull,
    );
  });

  test(
    'identity never transforms, mapped clip precedes user-space transform',
    () {
      for (final attributes in [_squareBox, '$_wide $_squareBox']) {
        final doc = _parse(attributes);
        final canvas = _RootAuditCanvas();
        final clock = ValueNotifier(Duration.zero);
        final painter = AnimatedSvgPainter(
          root: doc.root,
          intrinsicSize: Size(doc.width, doc.height),
          rootViewBoxTransform: doc.rootViewBoxTransform,
          clock: clock,
          theme: const XvgTheme(),
          fit: BoxFit.fill,
          alignment: Alignment.center,
        );
        painter.paint(canvas, const Size(200, 100));
        expect(
          canvas.operations,
          doc.rootViewBoxTransform == null ? ['clip'] : ['clip', 'transform'],
        );
        expect(canvas.clip, Rect.fromLTWH(0, 0, doc.width, doc.height));
        clock.dispose();
      }
    },
  );
}

/// Records root-only canvas operations. / 记录仅含根节点的画布操作。
class _RootAuditCanvas implements Canvas {
  /// Recorded clip/transform order. / 记录的裁剪与变换顺序。
  final operations = <String>[];

  /// Last viewport clip. / 最近的视口裁剪。
  Rect? clip;

  /// Records viewport clipping. / 记录视口裁剪。
  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    clip = rect;
    operations.add('clip');
  }

  /// Records the user-space transform. / 记录用户坐标变换。
  @override
  void transform(Float64List matrix4) => operations.add('transform');

  /// Ignores drawing-free root operations. / 忽略空根的其它操作。
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
