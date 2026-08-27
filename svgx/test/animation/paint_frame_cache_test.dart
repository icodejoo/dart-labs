// Regression tests for the two per-frame caches `animated_svg_painter.dart`
// keys on "the inputs provably did not change": the reused effective-attribute
// map ([SvgNode.cachedAnimatedAttributes]) and the memoized dashed stroke path
// ([SvgNode.cachedDashedPath]).
//
// Both trade a stale-read hazard for skipped work, and both are only sound
// because their keys are the *sampled values* rather than the timeline
// position. These tests attack that soundness from the directions that would
// actually break: a value that keeps moving (must never reuse), a value that
// has frozen while something else still animates (must reuse *and* still
// render the moving part), and one long-lived node tree painted at
// out-of-order times by different observers (must never serve one observer's
// frame to another).
//
// 针对 `animated_svg_painter.dart` 里两个以"输入可证明没变"为键的逐帧缓存的回归
// 测试：复用的生效属性表（[SvgNode.cachedAnimatedAttributes]）与记忆化的虚线描边
// 路径（[SvgNode.cachedDashedPath]）。
//
// 两者都是用"读到过期数据"的风险换掉一部分工作量，而它们之所以成立，全靠缓存键取
// 的是*采样值*而不是时间线位置。这些测试从真正可能击穿它的方向发起攻击：一直在动
// 的值（绝不能复用）、已经定格但另有动画仍在跑的值（必须复用，且运动部分仍要照常
// 渲染）、以及同一棵长生命周期节点树被不同观察者以乱序时刻绘制（绝不能把一个观察
// 者的帧发给另一个）。

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';

const _size = 100;
const _sizeD = 100.0;

SvgDocument _parse(String body) => parseAnimatedSvgDocument(
  '<svg xmlns="http://www.w3.org/2000/svg" width="$_size" height="$_size" '
  'viewBox="0 0 $_size $_size">$body</svg>',
);

/// Renders [document] at timeline position [t] and returns its raw RGBA
/// pixels, reusing the document's own long-lived node tree across calls — the
/// tree the caches live on, exactly as production does.
///
/// 在时间线位置 [t] 渲染 [document] 并返回其原始 RGBA 像素，跨调用复用该文档自身
/// 的长生命周期节点树——缓存就挂在这棵树上，与生产环境完全一致。
///
/// [document] — the parsed document to paint. / 待绘制的已解析文档。
///
/// [t] — timeline position. / 时间线位置。
///
/// Returns the frame's raw RGBA bytes. / 返回该帧的原始 RGBA 字节。
Future<ByteData> _renderAt(SvgDocument document, Duration t) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AnimatedSvgPainter(
    root: document.root,
    intrinsicSize: Size(document.width, document.height),
    clock: ValueNotifier(t),
    theme: const SvgTheme(),
    fit: BoxFit.fill,
    alignment: Alignment.center,
    gradients: document.gradients,
    clipPaths: document.clipPaths,
    masks: document.masks,
  ).paint(canvas, const Size(_sizeD, _sizeD));
  final image = await recorder.endRecording().toImage(_size, _size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!;
}

int _alphaAt(ByteData pixels, int x, int y) =>
    pixels.getUint8((y * _size + x) * 4 + 3);

/// Number of non-transparent pixels in a frame — a cheap whole-frame signature
/// for "did anything about this render change at all".
///
/// 一帧里非透明像素的数量——一个廉价的整帧签名，用于回答"这次渲染到底有没有变"。
///
/// [pixels] — raw RGBA bytes of the frame. / 该帧的原始 RGBA 字节。
///
/// Returns the covered-pixel count. / 返回被覆盖的像素数。
int _coverage(ByteData pixels) {
  var covered = 0;
  for (var i = 3; i < pixels.lengthInBytes; i += 4) {
    if (pixels.getUint8(i) != 0) covered++;
  }
  return covered;
}

/// Whether two frames are byte-identical. / 两帧是否逐字节相同。
///
/// [a] — first frame. / 第一帧。
///
/// [b] — second frame. / 第二帧。
///
/// Returns true when every byte matches. / 每个字节都相同时返回 true。
bool _samePixels(ByteData a, ByteData b) {
  if (a.lengthInBytes != b.lengthInBytes) return false;
  for (var i = 0; i < a.lengthInBytes; i++) {
    if (a.getUint8(i) != b.getUint8(i)) return false;
  }
  return true;
}

void main() {
  test('a continuously-animated geometry attribute is never served from the '
      'reused attribute map — consecutive frames must differ', () async {
    // `x` moves every frame, so the sample key changes every frame and a
    // fresh map (hence fresh geometry) must be built each time. If the map
    // identity were ever reused here, `_geometryPath`'s identity cache would
    // hand back the first frame's rect forever.
    //
    // `x` 每帧都在动，因此采样键每帧都变，必须每次都构建新表（从而构建新几何）。
    // 若此处复用了表的身份，`_geometryPath` 的身份缓存会永远交回第一帧的矩形。
    final document = _parse(
      '<rect x="0" y="40" width="10" height="10" fill="#ff0000">'
      '<animate attributeName="x" values="0;80" dur="1s" fill="freeze"/>'
      '</rect>',
    );
    final frames = <ByteData>[];
    for (var ms = 100; ms <= 900; ms += 100) {
      frames.add(await _renderAt(document, Duration(milliseconds: ms)));
    }
    for (var i = 1; i < frames.length; i++) {
      expect(
        _samePixels(frames[i - 1], frames[i]),
        isFalse,
        reason:
            'frame ${i - 1} and $i rendered identically, so the moving '
            '<rect> was served from a stale cache',
      );
    }
  });

  test('an animated stroke-dashoffset is never served from the memoized dashed '
      'path — consecutive frames must differ', () async {
    // The dash memo keys on the phase by value, so a moving phase must miss
    // every frame. A stale hit would freeze the reveal at its first frame.
    //
    // 虚线记忆表按值比较相位，因此移动中的相位必须每帧未命中。若错误命中，揭示
    // 动画会冻结在它的第一帧。
    final document = _parse(
      '<path d="M10 50H90" fill="none" stroke="#ff0000" stroke-width="6" '
      'stroke-dasharray="80" stroke-dashoffset="80">'
      '<animate attributeName="stroke-dashoffset" values="80;0" dur="1s" '
      'fill="freeze"/>'
      '</path>',
    );
    final coverages = <int>[];
    for (var ms = 100; ms <= 900; ms += 100) {
      coverages.add(
        _coverage(await _renderAt(document, Duration(milliseconds: ms))),
      );
    }
    // A reveal strictly grows: every frame must cover more than the last.
    // 揭示动画严格增长：每一帧覆盖的像素都必须多于上一帧。
    for (var i = 1; i < coverages.length; i++) {
      expect(
        coverages[i],
        greaterThan(coverages[i - 1]),
        reason:
            'dash reveal stalled between frame ${i - 1} and $i '
            '(${coverages[i - 1]} -> ${coverages[i]} px)',
      );
    }
  });

  test(
    'a frozen dash reveal under a still-running rotation keeps rotating, and '
    'keeps the reveal complete',
    () async {
      // This is the case both caches exist for, and the one that could silently
      // over-cache: the `<animate>` has frozen (so the attribute map and the
      // dashed path are legitimately reusable) while an `<animateTransform>`
      // keeps the icon repainting. The reused *local-space* dashed path must
      // still be re-drawn under a fresh transform every frame.
      //
      // 这正是两个缓存存在的意义所在，也是最可能悄悄过度缓存的场景：`<animate>`
      // 已经定格（因此属性表与虚线路径确实可以复用），而 `<animateTransform>` 仍
      // 在让图标持续重绘。复用的那条*局部空间*虚线路径每帧仍必须在新的变换下重画。
      final document = _parse(
        '<path d="M50 10V50" fill="none" stroke="#ff0000" stroke-width="8" '
        'stroke-dasharray="60" stroke-dashoffset="60">'
        '<animate attributeName="stroke-dashoffset" values="60;0" dur="0.3s" '
        'fill="freeze"/>'
        '<animateTransform attributeName="transform" type="rotate" '
        'dur="1.2s" repeatCount="indefinite" values="0 50 50;360 50 50"/>'
        '</path>',
      );
      // Past 0.3s the dashoffset is frozen at 0, so the stroke is fully
      // revealed from here on and only the rotation is still moving.
      //
      // 0.3s 之后 dashoffset 定格在 0，因此描边从此完全显现，仍在动的只有旋转。
      final up = await _renderAt(document, const Duration(milliseconds: 600));
      final right = await _renderAt(
        document,
        const Duration(milliseconds: 900),
      );
      final down = await _renderAt(
        document,
        const Duration(milliseconds: 1200),
      );

      // The rotation genuinely moved the stroke: at t=600ms (quarter turn) it
      // points one way, at t=900ms (half turn) another.
      //
      // 旋转确实让描边动了：t=600ms（转过四分之一）指向一边，t=900ms（转过一半）
      // 指向另一边。
      expect(
        _samePixels(up, right),
        isFalse,
        reason:
            'the rotation stopped affecting the render once the dash '
            'reveal froze — the dashed path was cached together with its '
            'transform instead of in local space',
      );
      expect(_samePixels(right, down), isFalse);

      // And the reveal stayed complete rather than reverting: a full turn later
      // the stroke covers the same number of pixels as it did a quarter turn
      // in (same shape, different orientation).
      //
      // 且揭示保持完整、没有回退：转满一圈后描边覆盖的像素数与转过四分之一时相同
      // （同一形状，不同朝向）。
      final fullTurn = await _renderAt(
        document,
        const Duration(milliseconds: 1800),
      );
      expect(_coverage(fullTurn), _coverage(up));
      expect(_samePixels(fullTurn, up), isTrue);
    },
  );

  test(
    'one shared node tree painted at out-of-order times gives every observer '
    'the same pixels it would get painting alone',
    () async {
      // Two widgets can share one parsed document (see `SvgDocumentCache`) and
      // sample it at different timeline positions in the same frame, so both
      // caches get overwritten by whichever observer painted last. Keying on
      // sampled values (not on time) is what makes that merely a miss rather
      // than a stale read. Interleaving two timelines must therefore produce
      // byte-identical output to painting each one on its own.
      //
      // 两个控件可以共享同一份已解析文档（见 `SvgDocumentCache`），并在同一帧里以
      // 不同的时间线位置对它采样，于是两个缓存都会被最后绘制的那个观察者覆写。以
      // 采样值（而非时间）为键，才使这种情况只是未命中而不是读到过期数据。因此把
      // 两条时间线交错绘制，输出必须与各自单独绘制逐字节一致。
      const body =
          '<g><rect x="0" y="10" width="20" height="20" fill="#0000ff">'
          '<animate attributeName="x" values="0;70" dur="1s" fill="freeze"/>'
          '</rect>'
          '<path d="M10 70H90" fill="none" stroke="#ff0000" stroke-width="6" '
          'stroke-dasharray="80" stroke-dashoffset="80">'
          '<animate attributeName="stroke-dashoffset" values="80;0" dur="1s" '
          'fill="freeze"/>'
          '</path></g>';
      const early = Duration(milliseconds: 250);
      const late = Duration(milliseconds: 750);

      // Reference: a private tree per observer, so no sharing can occur.
      // 参照：每个观察者各用一棵私有树，因此不可能发生共享。
      final soloEarly = await _renderAt(_parse(body), early);
      final soloLate = await _renderAt(_parse(body), late);

      // Now one shared tree, alternating between the two positions.
      // 现在换成一棵共享树，在两个位置之间来回切换。
      final shared = _parse(body);
      for (var round = 0; round < 3; round++) {
        expect(_samePixels(await _renderAt(shared, early), soloEarly), isTrue);
        expect(_samePixels(await _renderAt(shared, late), soloLate), isTrue);
      }
    },
  );

  test('a non-freezing animate still snaps back to the static value after it '
      'ends, even though the map is now reusable', () async {
    // The sample-key sentinel for "no value at this instant" has to be
    // distinguishable from every real sampled number, or an animation ending
    // without `fill="freeze"` would keep its last value forever. This is the
    // same guarantee `effective_attributes_reuse_test.dart` makes about the
    // uncached implementation, re-asserted against the cached one.
    //
    // 采样键里"此刻无值"的哨兵必须能与任何真实采样数值区分开，否则未设置
    // `fill="freeze"` 的动画结束后会永远保留它的最后一个值。这与
    // `effective_attributes_reuse_test.dart` 对无缓存实现所作的保证相同，此处
    // 针对带缓存的实现重新断言一次。
    final document = _parse(
      '<rect x="5" y="5" width="10" height="10" fill="#ff0000">'
      '<animate attributeName="x" values="0;80" dur="1s"/>'
      '</rect>',
    );
    // Paint several mid-animation frames first, so a cached map and a cached
    // sample key definitely exist before the animation ends.
    //
    // 先绘制若干动画进行中的帧，确保动画结束前确实已经存在缓存表与缓存采样键。
    for (var ms = 200; ms <= 800; ms += 200) {
      await _renderAt(document, Duration(milliseconds: ms));
    }
    final after = await _renderAt(document, const Duration(seconds: 2));
    expect(_alphaAt(after, 10, 10), 255); // static x=5..15
    expect(_alphaAt(after, 85, 10), 0); // not the end value
    expect(_alphaAt(after, 45, 10), 0); // not a mid-animation leftover
  });
}
