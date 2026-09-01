// Host-side microbenchmark isolating the UI-thread cost of the mask-as-clip
// fast path against the exact mask pipeline, over the 61 mask-bearing icons of
// the real corpus. Exists because the mask approximation moves work from the
// raster thread (two GPU render passes per mask) onto the UI thread (building
// a clip path per frame), and the scrolling real-device benchmark cannot be
// run reliably on a phone that is simultaneously in human use — this measures
// the UI-thread half deterministically so the trade can be reasoned about with
// the timeline's measured 221us-per-render-pass figure.
//
// 主机侧微基准，在真实语料的 61 个带 mask 图标上，把 mask-转-clip 快路径与精确
// mask 管线的 UI 线程开销隔离出来对比。存在的原因：mask 近似把工作从 raster 线程
// （每个 mask 两个 GPU 渲染通道）搬到了 UI 线程（每帧构建一条裁剪路径），而滚动
// 真机基准在一台同时有真人使用的手机上无法稳定跑完——因此这里确定性地量出 UI 线程
// 那一半，以便与 timeline 实测的"每渲染通道 221us"一起推算这笔交易是否划算。

import 'dart:ui' as ui;

import 'package:bench_app/anim_icons_real.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:svgx/src/animation/animated_svg_painter.dart';
import 'package:svgx/src/animation/svg_document_parser.dart';
import 'package:svgx/src/animation/svg_theme.dart';

void main() {
  test('mask-as-clip UI-thread cost vs the exact mask pipeline', () {
    // Only the mask-bearing icons: including the other 338 would dilute the
    // per-mask difference into the noise of unrelated path recording.
    //
    // 只取带 mask 的图标：把其余 338 个也算进来会把逐 mask 的差异稀释到无关路径
    // 录制的噪声里。
    final documents = <SvgDocument>[];
    for (final source in animIconsReal) {
      final document = parseAnimatedSvgDocument(source);
      if (document.masks.isNotEmpty) documents.add(document);
    }

    /// Records every document once per simulated frame and returns the wall
    /// time for [frames] frames.
    ///
    /// 每个模拟帧把所有文档各录制一次，返回 [frames] 帧的墙钟耗时。
    ///
    /// [approximate] — whether the mask-as-clip fast path is enabled.
    ///
    ///   是否启用 mask-转-clip 快路径。
    ///
    /// [frames] — how many frames to simulate. / 模拟多少帧。
    ///
    /// Returns the elapsed time. / 返回耗时。
    Duration run({
      required bool approximate,
      int frames = 60,
      bool advanceTime = true,
    }) {
      final stopwatch = Stopwatch()..start();
      for (var frame = 0; frame < frames; frame++) {
        // Default: advance the timeline like a real 60Hz clock so masks
        // genuinely move between frames, which is the realistic case and the
        // one where the clip path has to be rebuilt.
        //
        // 默认：像真实 60Hz 时钟那样推进时间线，使 mask 在帧间真的在动——这是现实
        // 情形，也是裁剪路径必须重建的那种情形。
        //
        // `advanceTime: false` pins one instant, so every mask samples
        // identically on every frame and the clip-path signature cache hits
        // 100% of the time. Comparing the two isolates how much of the fast
        // path's cost the cache actually removes — the moving case is the
        // realistic one, the pinned case is the cache's best case.
        //
        // `advanceTime: false` 把时刻钉死，于是每个 mask 每帧采样完全相同，裁剪
        // 路径签名缓存 100% 命中。两者对比能隔离出缓存到底消掉了快路径多少开销
        // ——移动的那种是现实情形，钉死的那种是缓存的最好情形。
        final time = advanceTime
            ? Duration(microseconds: frame * 16667)
            : const Duration(milliseconds: 400);
        for (final document in documents) {
          final recorder = ui.PictureRecorder();
          AnimatedSvgPainter(
            root: document.root,
            intrinsicSize: Size(document.width, document.height),
            clock: ValueNotifier(time),
            theme: const SvgxTheme(),
            fit: BoxFit.contain,
            alignment: Alignment.center,
            gradients: document.gradients,
            clipPaths: document.clipPaths,
            masks: document.masks,
            approximateMasks: () => approximate,
          ).paint(Canvas(recorder), const Size(32, 32));
          recorder.endRecording();
        }
      }
      stopwatch.stop();
      return stopwatch.elapsed;
    }

    // Warm both paths (JIT, geometry caches, eligibility flags) before timing.
    // 计时前先预热两条路径（JIT、几何缓存、合格性标志）。
    run(approximate: false, frames: 10);
    run(approximate: true, frames: 10);

    // Min-of-N: the same convention tool/run_micro.ps1 uses, because the
    // minimum converges on the real cost from below while the mean drags in
    // scheduler noise.
    //
    // 取 N 次最小值：与 tool/run_micro.ps1 相同的口径，因为最小值会从下方收敛到
    // 真实开销，而均值会把调度噪声带进来。
    var exactBest = const Duration(days: 1);
    var approxBest = const Duration(days: 1);
    for (var i = 0; i < 5; i++) {
      final exact = run(approximate: false);
      if (exact < exactBest) exactBest = exact;
      final approx = run(approximate: true);
      if (approx < approxBest) approxBest = approx;
    }

    var approxPinnedBest = const Duration(days: 1);
    for (var i = 0; i < 5; i++) {
      final pinned = run(approximate: true, advanceTime: false);
      if (pinned < approxPinnedBest) approxPinnedBest = pinned;
    }

    final perFrameExactUs = exactBest.inMicroseconds / 60;
    final perFrameApproxUs = approxBest.inMicroseconds / 60;
    final perFrameApproxPinnedUs = approxPinnedBest.inMicroseconds / 60;
    // ignore: avoid_print
    print(
      'maskBearingDocuments=${documents.length} '
      'exact_us_per_frame_all_docs=${perFrameExactUs.toStringAsFixed(1)} '
      'approx_us_per_frame_all_docs=${perFrameApproxUs.toStringAsFixed(1)} '
      'delta_us=${(perFrameApproxUs - perFrameExactUs).toStringAsFixed(1)} '
      'delta_us_per_document='
      '${((perFrameApproxUs - perFrameExactUs) / documents.length).toStringAsFixed(2)} '
      'approx_us_per_frame_cacheAlwaysHits='
      '${perFrameApproxPinnedUs.toStringAsFixed(1)} '
      'delta_us_per_document_cacheAlwaysHits='
      '${((perFrameApproxPinnedUs - perFrameExactUs) / documents.length).toStringAsFixed(2)}',
    );

    expect(
      documents.length,
      greaterThan(0),
      reason: 'sanity: the corpus must contain mask-bearing icons',
    );
  });
}
