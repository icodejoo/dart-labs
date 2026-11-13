import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xvg/src/animation/animated_svg_painter.dart';
import 'package:xvg/src/animation/svg_document_parser.dart';
import 'package:xvg/src/animation/svg_theme.dart';
import 'package:xvg/src/rust_static_svg.dart';
import 'package:xvg/xvg.dart' show RustLib;

const _canvasSize = 200;
const _iconSize = Size(96, 96);
const _origin = Offset(52, 52);
const _frozenTime = Duration(seconds: 61);
const _opaqueBackground = Color(0xffe4e8ec);
const _transparentBackground = Color(0x00000000);
const _corpusVariable = 'XVG_MASK_EDGE_SAMPLES';
const _maskReference = 'mask="url(#m)"';
const _viewport = 'width="24" height="24" viewBox="0 0 24 24"';
const _namespace = 'xmlns="http://www.w3.org/2000/svg"';
const _elementClip = 'clip-path="url(#c)"';
const _halfOpacity = 'opacity=".5"';
const _blurFilter = 'filter="url(#b)"';
const _whiteMaskPath = 'M-7 6 Q4 2 12 8 T25 6 V24 H-7 Z';
const _animatedMode = 'animated';
const _staticMode = 'static';
const _channelMax = 255;
const _visibleAlphaOffset = (110 * _canvasSize + 70) * 4 + 3;

// Original minimal geometry: an overflowing white mask with a black cutout.
// 原创最小几何：越界白色遮罩加黑色挖空，不复制第三方图标。
const _definitions =
    '''
<defs>
  <mask id="m">
    <path fill="white" d="$_whiteMaskPath">
      <animate attributeName="d" values="M-7 10 H25 V24 H-7 Z;$_whiteMaskPath"
          dur="1s" fill="freeze"/>
    </path>
    <path d="M7 3 H17 L15 20 H9 Z"/>
  </mask>
  <clipPath id="c"><rect x="4" y="4" width="16" height="16"/></clipPath>
  <filter id="b"><feGaussianBlur stdDeviation="1"/></filter>
</defs>
''';

String _source({String effects = '', bool overflow = false}) =>
    '''
<svg $_namespace $_viewport>
$_definitions
<g $_maskReference $effects>
  <rect x="${overflow ? -7 : 0}" width="${overflow ? 39 : 24}"
      height="24" fill="#345678"/>
</g>
</svg>
''';

void _paintAnimated(Canvas canvas, String source, {bool approximate = false}) {
  final doc = parseAnimatedSvgDocument(source);
  final clock = ValueNotifier(_frozenTime);
  try {
    AnimatedSvgPainter(
      root: doc.root,
      intrinsicSize: Size(doc.width, doc.height),
      clock: clock,
      theme: const XvgTheme(),
      fit: BoxFit.fill,
      alignment: Alignment.center,
      gradients: doc.gradients,
      clipPaths: doc.clipPaths,
      masks: doc.masks,
      approximateMasks: () => approximate,
    ).paint(canvas, _iconSize);
  } finally {
    clock.dispose();
  }
}

Future<ByteData> _render(
  void Function(Canvas) paint, {
  Color background = _transparentBackground,
  Offset origin = _origin,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(background, BlendMode.src);
  canvas.translate(origin.dx, origin.dy);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(_canvasSize, _canvasSize);
  try {
    return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  } finally {
    image.dispose();
    picture.dispose();
  }
}

// Check every outside pixel, including the default mask region's +/-10% edges.
// 检查全部外围像素，包含默认 mask 区域的左右 10% 边界。
int _outsidePixels(ByteData bytes, Rect viewport, Color background) {
  final argb = background.toARGB32();
  final expected = [
    argb >> 16 & _channelMax,
    argb >> 8 & _channelMax,
    argb & _channelMax,
    argb >> 24,
  ];
  var count = 0;
  for (var y = 0; y < _canvasSize; y++) {
    for (var x = 0; x < _canvasSize; x++) {
      if (viewport.overlaps(Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1))) {
        continue;
      }
      final offset = (y * _canvasSize + x) * 4;
      for (var channel = 0; channel < expected.length; channel++) {
        if (bytes.getUint8(offset + channel) != expected[channel]) {
          count++;
          break;
        }
      }
    }
  }
  return count;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => RustLib.init());
  tearDownAll(() => RustXvgPictureCache.instance.clear());

  test(
    'all effect layers composite under antialiased viewport and element clips',
    () {
      for (final (effects, layers) in [
        ('', 2),
        (_halfOpacity, 3),
        (_blurFilter, 3),
        ('$_halfOpacity $_blurFilter', 4),
      ]) {
        final recorder = ui.PictureRecorder();
        final canvas = _ClipAuditCanvas(Canvas(recorder));
        _paintAnimated(canvas, _source(effects: '$_elementClip $effects'));
        recorder.endRecording().dispose();
        expect(canvas.layers, hasLength(layers), reason: effects);
        expect(
          canvas.layers,
          everyElement((viewportClip: true, elementClip: true)),
          reason: effects,
        );
        expect(canvas.stack, isEmpty);
      }
    },
  );

  test('binary mask approximation retains clips without offscreen layers', () {
    final recorder = ui.PictureRecorder();
    final canvas = _ClipAuditCanvas(Canvas(recorder));
    _paintAnimated(canvas, _source(effects: _elementClip), approximate: true);
    recorder.endRecording().dispose();
    expect(canvas.layers, isEmpty);
    expect(canvas.pathClips, 2);
    expect(canvas.stack, isEmpty);
  });

  for (final background in [_transparentBackground, _opaqueBackground]) {
    for (final approximate in [false, true]) {
      test('animated frozen mask stays inside viewport '
          '(background=$background, approximate=$approximate)', () async {
        for (final origin in [_origin, const Offset(52.35, 51.65)]) {
          final bytes = await _render(
            (canvas) =>
                _paintAnimated(canvas, _source(), approximate: approximate),
            background: background,
            origin: origin,
          );
          expect(_outsidePixels(bytes, origin & _iconSize, background), 0);
          expect(bytes.getUint8(_visibleAlphaOffset), _channelMax);
        }
      });
    }
  }

  for (final effects in ['', _halfOpacity, _blurFilter]) {
    test(
      'mask/clip/filter composite respects element clip: $effects',
      () async {
        final bytes = await _render(
          (canvas) => _paintAnimated(
            canvas,
            _source(effects: '$_elementClip $effects', overflow: true),
          ),
        );
        expect(
          _outsidePixels(
            bytes,
            const Rect.fromLTWH(68, 68, 64, 64),
            _transparentBackground,
          ),
          0,
        );
      },
    );
  }

  test('transformed mask/clip/filter stay within the transformed element clip', () async {
    final source = _source(
      effects:
          '$_elementClip $_halfOpacity $_blurFilter transform="translate(2 -1)"',
      overflow: true,
    );
    final bytes = await _render((canvas) => _paintAnimated(canvas, source));
    expect(
      _outsidePixels(
        bytes,
        const Rect.fromLTWH(76, 64, 64, 64),
        _transparentBackground,
      ),
      0,
    );
    final recorder = ui.PictureRecorder();
    final canvas = _ClipAuditCanvas(Canvas(recorder));
    _paintAnimated(canvas, source);
    recorder.endRecording().dispose();
    expect(canvas.layers, hasLength(4));
    expect(
      canvas.layers,
      everyElement((viewportClip: true, elementClip: true)),
    );
    expect(canvas.stack, isEmpty);
  });

  testWidgets('StaticXvg mask comparison on a larger canvas', (tester) async {
    await tester.pumpWidget(
      Center(
        child: StaticXvg(
          _source(),
          width: _iconSize.width,
          height: _iconSize.height,
        ),
      ),
    );
    final customPaint = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .singleWhere((widget) => widget.painter != null);
    await tester.runAsync(() async {
      for (final background in [_transparentBackground, _opaqueBackground]) {
        final bytes = await _render(
          (canvas) => customPaint.painter!.paint(canvas, _iconSize),
          background: background,
        );
        expect(_outsidePixels(bytes, _origin & _iconSize, background), 0);
        expect(bytes.getUint8(_visibleAlphaOffset), _channelMax);
      }
    });
  });

  // Read-only optional corpus; third-party sources never enter the repository.
  // 可选只读外部语料；第三方源码始终不入库。
  final directory = Platform.environment[_corpusVariable];
  if (directory != null) {
    test('external mask-edge corpus statistics', () async {
      final files =
          Directory(directory)
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.svg'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final counts = <String, int>{_animatedMode: 0, _staticMode: 0};
      final pixels = <String, int>{_animatedMode: 0, _staticMode: 0};
      for (final file in files) {
        final source = file.readAsStringSync();
        final info = RustXvgPictureCache.instance.getOrRender(source);
        for (final mode in counts.keys) {
          final bytes = await _render((canvas) {
            if (mode == _animatedMode) {
              _paintAnimated(canvas, source);
            } else {
              canvas.scale(
                _iconSize.width / info.size.width,
                _iconSize.height / info.size.height,
              );
              canvas.drawPicture(info.picture);
            }
          });
          final outside = _outsidePixels(
            bytes,
            _origin & _iconSize,
            _transparentBackground,
          );
          if (outside > 0) counts[mode] = counts[mode]! + 1;
          pixels[mode] = pixels[mode]! + outside;
        }
      }
      // ignore: avoid_print
      print(
        'mask-edge: files=${files.length}, leakingIcons=$counts, outsidePixels=$pixels',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

typedef _ClipState = ({bool viewportClip, bool elementClip});

// Delegate actual drawing; audit clips captured at layer entry (restore state).
// 委托真实绘制；审计图层入口捕获的裁剪，即恢复合成时的裁剪状态。
class _ClipAuditCanvas implements Canvas {
  _ClipAuditCanvas(this.delegate);
  final Canvas delegate;
  final stack = <_ClipState>[];
  final layers = <_ClipState>[];
  var pathClips = 0;
  _ClipState state = (viewportClip: false, elementClip: false);

  @override
  void save() {
    stack.add(state);
    delegate.save();
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    layers.add(state);
    stack.add(state);
    delegate.saveLayer(bounds, paint);
  }

  @override
  void restore() {
    state = stack.removeLast();
    delegate.restore();
  }

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) {
    expect(doAntiAlias, isTrue);
    state = (viewportClip: true, elementClip: state.elementClip);
    delegate.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);
  }

  @override
  void clipPath(ui.Path path, {bool doAntiAlias = true}) {
    pathClips++;
    state = (viewportClip: state.viewportClip, elementClip: true);
    delegate.clipPath(path, doAntiAlias: doAntiAlias);
  }

  @override
  Float64List getTransform() => delegate.getTransform();

  @override
  void translate(double dx, double dy) => delegate.translate(dx, dy);
  @override
  void scale(double sx, [double? sy]) => delegate.scale(sx, sy);
  @override
  void transform(Float64List matrix4) => delegate.transform(matrix4);
  @override
  void drawPath(ui.Path path, Paint paint) => delegate.drawPath(path, paint);
  @override
  void drawColor(Color color, BlendMode blendMode) =>
      delegate.drawColor(color, blendMode);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
