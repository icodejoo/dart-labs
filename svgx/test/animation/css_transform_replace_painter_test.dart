import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/smil_animation.dart';
import 'package:svgx/src/animation/svg_dom.dart';
import 'package:svgx/src/animation/svg_theme.dart';

import 'pixel_test_utils.dart';

/// 延迟、刚开始、中点与结束后的采样时刻。
const _times = [
  Duration(milliseconds: 500),
  Duration(milliseconds: 1001),
  Duration(seconds: 2),
  Duration(milliseconds: 3001),
];

/// 两组静态位移，分别等于及不同于首关键帧。
const _offsets = [40, 10];

/// 测试图形的边长。
const _side = 10;

/// 遮罩或裁剪定义的引用名。
const _effectId = 'effect';

/// 红色图形的填充色。
const _red = '#ff0000';

/// 二值遮罩的填充色。
const _white = '#ffffff';

/// 普通绘制模式。
const _normalMode = 'normal';

/// 近似遮罩模式。
const _maskMode = 'mask';

/// 精确遮罩模式。
const _exactMaskMode = 'exactMask';

/// 裁剪路径模式。
const _clipMode = 'clip';

/// 延迟一秒、持续两秒的平移槽位。
SmilTransformAnimation _translate({
  bool replaces = true,
  bool freeze = false,
  bool constant = false,
}) => SmilTransformAnimation(
  type: SmilTransformType.translate,
  values: [
    const [40, 0, 0],
    constant ? const [40, 0, 0] : const [80, 0, 0],
  ],
  begin: const Duration(seconds: 1),
  duration: const Duration(seconds: 2),
  fillFreeze: freeze,
  replacesStaticTransform: replaces,
);

/// 构建直接赋予静态矩阵的矩形，完全绕过 XML 与原生解析。
SvgNode _rect({
  int x = 0,
  int y = 0,
  int side = _side,
  String fill = _red,
  double? staticX,
  List<SmilTransformAnimation> slots = const [],
  String? maskId,
  String? clipPathId,
}) => SvgNode(
  kind: SvgNodeKind.rect,
  attributes: {
    'x': '$x',
    'y': '$y',
    'width': '$side',
    'height': '$side',
    'fill': fill,
  },
  transform: staticX == null ? null : [1, 0, 0, 1, staticX, 0],
  transformAnimations: slots,
  maskId: maskId,
  clipPathId: clipPathId,
);

/// 获取可见红色区域的像素包围盒，以半覆盖阈值容忍边缘抗锯齿。
Rect? _redBounds(ByteData pixels) {
  const threshold = 128;
  var left = kPixelSize;
  var top = kPixelSize;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < kPixelSize; y++) {
    for (var x = 0; x < kPixelSize; x++) {
      if (alphaAt(pixels, x, y) < threshold ||
          redAt(pixels, x, y) < threshold) {
        continue;
      }
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  return right < 0
      ? null
      : Rect.fromLTRB(
          left.toDouble(),
          top.toDouble(),
          (right + 1).toDouble(),
          (bottom + 1).toDouble(),
        );
}

/// 断言整个红色列区间与高度，包含画布外的完全不可见情形。
void _expectPosition(ByteData pixels, int x, {int y = 0}) {
  expect(
    _redBounds(pixels),
    x >= kPixelSize
        ? null
        : Rect.fromLTWH(
            x.toDouble(),
            y.toDouble(),
            _side.toDouble(),
            _side.toDouble(),
          ),
  );
}

/// 把同一几何放在普通树、近似/精确遮罩或裁剪定义中。
AnimatedSvgPainter _painter(
  SvgNode geometry,
  ValueNotifier<Duration> clock,
  String mode,
) {
  final masked = mode == _maskMode || mode == _exactMaskMode;
  final clipped = mode == _clipMode;
  return AnimatedSvgPainter(
    root: masked || clipped
        ? _rect(
            side: kPixelSize,
            maskId: masked ? _effectId : null,
            clipPathId: clipped ? _effectId : null,
          )
        : geometry,
    intrinsicSize: const Size.square(kPixelSize * 1.0),
    clock: clock,
    theme: const SvgxTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    masks: masked ? {_effectId: geometry} : const {},
    clipPaths: clipped ? {_effectId: geometry} : const {},
    approximateMasks: () => mode == _maskMode,
  );
}

/// 多次录制同一 painter，保留节点及 mask 缓存。
Future<ByteData> _renderPainter(AnimatedSvgPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), const Size.square(kPixelSize * 1.0));
  final picture = recorder.endRecording();
  final image = await picture.toImage(kPixelSize, kPixelSize);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return bytes!;
}

/// 验证 CSS 替换静态矩阵的三条绘制路径与缓存隔离。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final offset in _offsets) {
    final expected = [offset, 40, 60, offset];
    for (var i = 0; i < _times.length; i++) {
      test('§6.5 S=$offset t=${_times[i].inMilliseconds}ms', () async {
        final node = _rect(staticX: offset.toDouble(), slots: [_translate()]);
        _expectPosition(await renderRootAt(node, _times[i]), expected[i]);
      });
    }

    test('forwards S=$offset 结束后仍替换', () async {
      final node = _rect(
        staticX: offset.toDouble(),
        slots: [_translate(freeze: true)],
      );
      _expectPosition(await renderRootAt(node, _times.last), 80);
    });

    test('SMIL S=$offset 四态仍叠加静态矩阵', () async {
      final node = _rect(
        staticX: offset.toDouble(),
        slots: [_translate(replaces: false)],
      );
      final expected = [offset, offset + 40, offset + 60, offset];
      for (var i = 0; i < _times.length; i++) {
        _expectPosition(await renderRootAt(node, _times[i]), expected[i]);
      }
    });

    test('仅静态 S=$offset 与直接定位逐像素相同且缓存不变', () async {
      final node = _rect(staticX: offset.toDouble());
      final reference = await renderRootAt(_rect(x: offset), Duration.zero);
      Object? matrix;
      for (final time in _times) {
        final pixels = await renderRootAt(node, time);
        _expectPosition(pixels, offset);
        expect(
          pixels.buffer.asUint8List(),
          orderedEquals(reference.buffer.asUint8List()),
        );
        matrix ??= node.cachedTransformMatrix;
        expect(node.cachedTransformMatrix, same(matrix));
      }
    });
  }

  test('translate 后 rotate 按槽位顺序合成并跳过静态矩阵', () async {
    final rotate = SmilTransformAnimation(
      type: SmilTransformType.rotate,
      values: const [
        [90, 0, 0],
        [90, 0, 0],
      ],
      begin: const Duration(seconds: 1),
      duration: const Duration(seconds: 2),
      fillFreeze: false,
      replacesStaticTransform: true,
    );
    final node = _rect(staticX: 10, slots: [_translate(), rotate]);
    _expectPosition(await renderRootAt(node, _times[2]), 50);
  });

  for (final mode in [_maskMode, _exactMaskMode, _clipMode]) {
    test('$mode 三态可见区域与普通树一致', () async {
      final geometry = _rect(
        fill: mode == _clipMode ? _red : _white,
        staticX: 10,
        slots: [_translate()],
      );
      final clock = ValueNotifier(Duration.zero);
      addTearDown(clock.dispose);
      final painter = _painter(geometry, clock, mode);
      final direct = _rect(staticX: 10, slots: [_translate()]);
      for (final time in [_times.first, _times[2], _times.last]) {
        clock.value = time;
        final actual = await _renderPainter(painter);
        final reference = await renderRootAt(direct, time);
        expect(
          actual.buffer.asUint8List(),
          orderedEquals(reference.buffer.asUint8List()),
        );
      }
      if (mode == _maskMode) {
        expect(geometry.maskClipEligible, isTrue);
        expect(geometry.cachedMaskClip, isNotNull);
      }
    });

    for (final constant in [false, true]) {
      test('$mode 缓存往返 constant=$constant', () async {
        final geometry = _rect(
          fill: mode == _clipMode ? _red : _white,
          staticX: 10,
          slots: [_translate(constant: constant)],
        );
        final clock = ValueNotifier(Duration.zero);
        addTearDown(clock.dispose);
        final painter = _painter(geometry, clock, mode);
        final sequence = [_times.first, _times[2], _times.last, _times[2]];
        final expected = [10, constant ? 40 : 60, 10, constant ? 40 : 60];
        Object? previousPath;
        for (var i = 0; i < sequence.length; i++) {
          clock.value = sequence[i];
          _expectPosition(await _renderPainter(painter), expected[i]);
          if (mode == _maskMode) {
            expect(geometry.cachedMaskClip, isNot(same(previousPath)));
            previousPath = geometry.cachedMaskClip;
            expect(
              geometry.maskClipSampleKey,
              i.isEven
                  ? [double.negativeInfinity]
                  : [constant ? 40.0 : 60.0, 0.0, 0.0],
            );
            await _renderPainter(painter);
            expect(geometry.cachedMaskClip, same(previousPath));
          }
        }
      });
    }
  }

  for (final mode in [_normalMode, _maskMode, _clipMode]) {
    test('$mode 两个 painter 共享树并交错采样互不污染', () async {
      final geometry = _rect(
        fill: mode == _maskMode ? _white : _red,
        staticX: 10,
        slots: [_translate()],
      );
      final delayClock = ValueNotifier(_times.first);
      final activeClock = ValueNotifier(_times[2]);
      addTearDown(delayClock.dispose);
      addTearDown(activeClock.dispose);
      final delayPainter = _painter(geometry, delayClock, mode);
      final activePainter = _painter(geometry, activeClock, mode);
      for (var i = 0; i < 2; i++) {
        _expectPosition(await _renderPainter(delayPainter), 10);
        _expectPosition(await _renderPainter(activePainter), 60);
      }
    });
  }

  test('派生标记：无槽位为 false', () {
    expect(_rect().replacesStaticTransform, isFalse);
  });
  test('派生标记：仅 SMIL 槽位为 false', () {
    expect(
      _rect(slots: [_translate(replaces: false)]).replacesStaticTransform,
      isFalse,
    );
  });
  test('派生标记：混合槽位包含替换槽位为 true', () {
    expect(
      _rect(slots: [_translate(replaces: false), _translate()])
          .replacesStaticTransform,
      isTrue,
    );
  });
}
