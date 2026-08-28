// Opt-out-able performance trade-offs for the animated SVG path. The lossy
// ones trade animation fidelity for frame throughput, apply only above a
// concurrency threshold, and are documented with exactly what they give up.
// Original implementation.
//
// 动画 SVG 路径上可关闭的性能取舍。其中有损的那些是拿动画保真度换帧吞吐，只在
// 并发量超过阈值后才生效，并明确写清放弃了什么。
// 原创实现。

import 'package:flutter/foundation.dart';

/// Controls how aggressively `SvgxAnimated` is allowed to degrade animation
/// smoothness-per-icon in exchange for overall frame throughput when many
/// animated icons play at once.
///
/// ## What this actually gives up
///
/// Nothing at all at or below [frameSkipThreshold] concurrently-animating
/// icons — both degradations below are gated on exceeding it, so a UI showing
/// a handful of animated icons renders exactly as it did before this existed.
/// Above the threshold, two things change.
///
/// **1. Per-icon sample rate ([maxFrameDivisor],
/// [offscreenLayerFrameDivisor]).** Each icon advances its SMIL timeline (and
/// repaints) on every Nth display frame rather than every frame, with each
/// icon assigned a different phase so the work spreads evenly instead of
/// every icon landing on the same frame. On a 60Hz display with the defaults
/// a plain icon samples at 30Hz, and an icon whose document needs an
/// offscreen layer (`mask`/blur — see [SvgDocument.usesOffscreenLayers])
/// at 20Hz.
///
/// The cost is temporal, not spatial: geometry, colour, stroke widths,
/// gradients and mask coverage are still computed *exactly* — a degraded icon
/// renders the same pixels it always did, just at fewer distinct points in
/// time. What you can notice is slightly coarser motion on fast animations (a
/// 0.2s `stroke-dashoffset` reveal gets ~6 distinct steps at 30Hz instead of
/// ~12), and a fast-spinning `animateTransform` looking marginally less
/// fluid. Nothing shifts position, changes colour, or drops out.
///
/// **2. Simple masks drawn as clips ([approximateSimpleMasksAsClip]).**
/// Opt-in — this one is NOT part of the default profile; see that field for
/// the measured reason. A `<mask>` whose content is nothing but fully-opaque
/// pure-black/pure-white fills describes a binary coverage region, which is what a clip path is, so
/// it is drawn as one — skipping the two `saveLayer` offscreen render passes
/// the exact pipeline needs. The cost is **edge antialiasing along the mask
/// boundary**: the exact pipeline multiplies a rasterized coverage ramp into
/// the content's alpha, a clip antialiases the boundary itself, and on
/// Impeller those ramps differ slightly. At icon sizes that is a sub-pixel
/// difference on the mask outline and nothing more. Any mask that would lose
/// more than that — a stroke, any opacity, a non-binary or gradient fill,
/// text, a nested clip/mask/blur — is rejected and keeps the exact pipeline.
///
/// ## Why offscreen layers are the thing being avoided
///
/// A `<mask>` or `feGaussianBlur` forces `canvas.saveLayer`, and each such
/// layer costs a GPU render-target allocation plus a separate render pass.
/// Real-device timeline capture (Huawei STG-AL00, Impeller GLES, 1000
/// concurrently-animating icons) attributed ~10.9ms of a 21.7ms raster frame
/// to ~49 such passes at ~221us each — the single largest line item in the
/// budget, and the reason both degradations above target them: one produces
/// fewer of those frames, the other emits fewer passes per frame. See
/// `doc/performance-benchmarks.md` for the full attribution.
///
/// ## Turning it off
///
/// Globally: `SvgxAnimationQuality.defaultQuality = SvgxAnimationQuality.exact;`
///
/// Per widget: `SvgxAnimated.string(src, quality: SvgxAnimationQuality.exact)`
///
/// 控制"同时播放大量动画图标"时，`SvgxAnimated` 可以多激进地牺牲单图标的动画
/// 流畅度，来换取整体帧吞吐。
///
/// ## 到底牺牲了什么
///
/// 并发动画图标数在 [frameSkipThreshold] 及以下时**什么都不降级**——下面两项
/// 降级都以"超过该阈值"为前置条件，因此只显示少量动画图标的界面，渲染结果与本
/// 机制不存在时完全一致。超过阈值后，有两件事会变。
///
/// **1. 单图标采样率（[maxFrameDivisor]、[offscreenLayerFrameDivisor]）。** 每个
/// 图标改为每 N 个显示帧才推进一次自己的 SMIL 时间线（并重绘一次），而不是每帧
/// 都推进；且每个图标分到不同的相位，使工作量均摊到各帧，而不是所有图标挤在同
/// 一帧。按默认值、在 60Hz 屏幕上，普通图标按 30Hz 采样，文档需要离屏图层的图标
/// （`mask`/模糊——见 [SvgDocument.usesOffscreenLayers]）按 20Hz 采样。
///
/// 这个代价是**时间维度**的，不是空间维度的：几何、颜色、描边宽度、渐变、
/// mask 覆盖度全部仍然*精确*计算——降级后的图标画出来的像素和以前一模一样，
/// 只是时间上采样点少了。能察觉到的是快动画的运动稍微变粗糙（0.2s 的
/// `stroke-dashoffset` 展开在 30Hz 下约 6 个离散步，而不是约 12 步），以及高速
/// 旋转的 `animateTransform` 看起来略欠顺滑。没有任何东西会位移、变色或消失。
///
/// **2. 简单 mask 改画成裁剪（[approximateSimpleMasksAsClip]）。** 需手动开启
/// ——这一项不属于默认配置，实测理由见该字段。内容只有完全不透明的纯黑/纯白填充的
/// `<mask>`，描述的是一个二值覆盖区域，而裁剪路径正是
/// 这个东西，于是就把它画成裁剪——跳过精确管线所需的两个 `saveLayer` 离屏渲染
/// 通道。代价是**mask 边界处的边缘抗锯齿**：精确管线把光栅化出的覆盖度斜坡乘进
/// 内容的 alpha，裁剪则对边界本身做抗锯齿，在 Impeller 上两条斜坡略有差异。在
/// 图标尺寸下，这就是 mask 轮廓上的一个亚像素差异，别无其它。任何会损失更多的
/// mask——带描边、带任何不透明度、非二值或渐变填充、文本、嵌套的 clip/mask/模糊
/// ——都会被拒掉并保持精确管线。
///
/// ## 为什么被规避的目标是离屏图层
///
/// `<mask>` 或 `feGaussianBlur` 会强制 `canvas.saveLayer`，而每个这样的图层都要
/// 付一次 GPU 渲染目标分配加一个独立渲染通道。真机 timeline 抓取（华为
/// STG-AL00，Impeller GLES，1000 个并发动画图标）把 21.7ms 的 raster 帧里约
/// 10.9ms 归因到约 49 个这样的通道、每个约 221us——是整个预算里最大的单项，也正是
/// 上面两项降级都瞄准它的原因：一个让这类帧产生得更少，另一个让每帧发出的通道更少。
/// 完整归因见 `doc/performance-benchmarks.md`。
///
/// ## 怎么关掉
///
/// 全局：`SvgxAnimationQuality.defaultQuality = SvgxAnimationQuality.exact;`
///
/// 单个控件：`SvgxAnimated.string(src, quality: SvgxAnimationQuality.exact)`
///
/// Example:
/// ```dart
/// // Never degrade — exact 60Hz sampling for every icon, at any count.
/// SvgxAnimationQuality.defaultQuality = SvgxAnimationQuality.exact;
///
/// // Degrade sooner and harder on low-end hardware.
/// SvgxAnimationQuality.defaultQuality = const SvgxAnimationQuality(
///   frameSkipThreshold: 8,
///   maxFrameDivisor: 3,
///   offscreenLayerFrameDivisor: 4,
/// );
/// ```
@immutable
class SvgxAnimationQuality {
  /// Creates a quality profile.
  ///
  /// 创建一份画质/性能配置。
  ///
  /// [adaptiveFrameSkipping] — master switch; false means never skip a frame
  ///   for any icon at any concurrency (exact sampling).
  ///
  ///   总开关；false 表示任何并发量下都不为任何图标跳帧（精确采样）。
  ///
  /// [frameSkipThreshold] — number of concurrently-animating `SvgxAnimated`
  ///   instances at or below which nothing is degraded.
  ///
  ///   并发播放的 `SvgxAnimated` 实例数在此值及以下时不做任何降级。
  ///
  /// [maxFrameDivisor] — sample one display frame in N for an ordinary
  ///   document once the threshold is exceeded. 1 disables skipping for them.
  ///
  ///   超过阈值后，普通文档每 N 个显示帧采样一次。为 1 表示对它们不跳帧。
  ///
  /// [offscreenLayerFrameDivisor] — the same, for a document that needs a
  ///   `saveLayer` (`mask`/blur). The effective divisor is the larger of this
  ///   and [maxFrameDivisor].
  ///
  ///   同上，但用于需要 `saveLayer` 的文档（`mask`/模糊）。实际生效的除数取本
  ///   值与 [maxFrameDivisor] 的较大者。
  ///
  /// [approximateSimpleMasksAsClip] — replace a `<mask>` with an equivalent
  ///   clip path when (and only when) the mask's content is pure opaque
  ///   black/white fills, which removes both of that mask's `saveLayer`
  ///   offscreen render passes. Also concurrency-gated by
  ///   [frameSkipThreshold]. **Defaults to false** — see
  ///   [approximateSimpleMasksAsClip] for why this one ships opt-in while
  ///   frame skipping ships on.
  ///
  ///   当 `<mask>` 的内容是纯不透明黑/白填充时（且仅在此时），用等价的裁剪路径
  ///   替代它，从而去掉该 mask 的两个 `saveLayer` 离屏渲染通道。同样受
  ///   [frameSkipThreshold] 的并发门控。**默认为 false**——为什么这一项默认关闭
  ///   而跳帧默认开启，见 [approximateSimpleMasksAsClip]。
  ///
  const SvgxAnimationQuality({
    this.adaptiveFrameSkipping = true,
    this.frameSkipThreshold = 24,
    this.maxFrameDivisor = 2,
    this.offscreenLayerFrameDivisor = 3,
    this.approximateSimpleMasksAsClip = false,
  }) : assert(frameSkipThreshold >= 0),
       assert(maxFrameDivisor >= 1),
       assert(offscreenLayerFrameDivisor >= 1);

  /// The shipped default: exact rendering up to [frameSkipThreshold]
  /// concurrent icons, then per-icon frame skipping as described on the class.
  ///
  /// Chosen as the default (rather than [exact]) because the degradation is
  /// invisible in the case it does not apply — a UI showing a handful of
  /// animated icons never reaches the threshold and behaves identically — and
  /// because a grid of hundreds of animated icons is the case where the
  /// alternative is not "more fidelity" but "dropped frames for everyone".
  ///
  /// 出厂默认：并发图标数在 [frameSkipThreshold] 以内时精确渲染，超过后按类
  /// 注释所述做单图标跳帧。
  ///
  /// 之所以选它（而不是 [exact]）作为默认：在降级不生效的场景里它是不可见的
  /// ——只显示少量动画图标的界面永远达不到阈值，行为完全一致；而在成百个动画
  /// 图标的网格场景里，不降级的替代结果并不是"更高保真"，而是"所有人一起掉帧"。
  static const SvgxAnimationQuality balanced = SvgxAnimationQuality();

  /// No degradation ever: every icon samples its timeline on every display
  /// frame regardless of how many are playing.
  ///
  /// 永不降级：无论多少图标在播放，每个图标都在每个显示帧采样自己的时间线。
  static const SvgxAnimationQuality exact = SvgxAnimationQuality(
    adaptiveFrameSkipping: false,
    approximateSimpleMasksAsClip: false,
  );

  /// Profile used by any `SvgxAnimated` that does not pass its own. Assign to
  /// change it process-wide; takes effect on the next frame.
  ///
  /// 任何未自带配置的 `SvgxAnimated` 所使用的配置。赋值即可全进程修改，下一帧
  /// 生效。
  static SvgxAnimationQuality defaultQuality = balanced;

  /// Master switch — see the constructor. / 总开关——见构造函数。
  final bool adaptiveFrameSkipping;

  /// Concurrency below which nothing degrades — see the constructor.
  ///
  /// 低于此并发量不做任何降级——见构造函数。
  final int frameSkipThreshold;

  /// Frame divisor for ordinary documents — see the constructor.
  ///
  /// 普通文档的帧除数——见构造函数。
  final int maxFrameDivisor;

  /// Frame divisor for `saveLayer`-needing documents — see the constructor.
  ///
  /// Known simplification, documented rather than hidden: this is decided from
  /// [SvgDocument.usesOffscreenLayers], which is a *parse-time* fact ("this
  /// document references a mask or a blur"). When
  /// [approximateSimpleMasksAsClip] then turns that document's masks into clip
  /// paths, the document no longer opens any layer, yet it still gets the
  /// harder divisor — so such an icon samples at a lower rate than its actual
  /// cost warrants. Deliberately not refined: a document can hold both
  /// approximable and non-approximable masks, and whether the approximation is
  /// even active depends on runtime concurrency, so a precise answer would
  /// have to be recomputed per frame per document. The cost of being
  /// conservative here is a little fidelity above the concurrency threshold;
  /// the cost of being wrong the other way is dropped frames.
  ///
  /// 需要 `saveLayer` 的文档的帧除数——见构造函数。
  ///
  /// 已知的简化，如实记录而非隐藏：本项依据 [SvgDocument.usesOffscreenLayers]
  /// 判定，而那是一个*解析期*事实（"这份文档引用了 mask 或模糊"）。当
  /// [approximateSimpleMasksAsClip] 随后把该文档的 mask 变成裁剪路径后，它其实
  /// 已经不再开任何图层，却仍然吃到更狠的除数——于是这类图标的采样率低于其真实
  /// 成本所应得的水平。刻意不做细化：一份文档可能同时含可近似与不可近似的 mask，
  /// 而近似是否生效还取决于运行时并发数，因此精确答案得逐帧逐文档重算。在这里保守
  /// 的代价是并发阈值之上损失一点保真度；反方向判断错的代价是掉帧。
  final int offscreenLayerFrameDivisor;

  /// Whether a trivially-simple `<mask>` may be drawn as a clip path instead,
  /// skipping its two offscreen render passes — see the constructor and
  /// [approximatesMasksAt].
  ///
  /// **Ships opt-in (false), unlike frame skipping**, and the reason is
  /// evidence rather than caution about correctness (correctness is covered by
  /// `test/animation/mask_clip_approximation_test.dart`). What is measured:
  ///
  ///  - it removes 47.7% of the offscreen render passes on the real 399-icon
  ///    corpus (deterministic survey), each worth ~221us of GPU time on a
  ///    Huawei STG-AL00;
  ///  - but it moves work onto the UI thread, and the direction depends on
  ///    whether the mask is moving: host-side, a *moving* mask costs +29us per
  ///    icon per frame to rebuild its clip path, while a *frozen* one (every
  ///    SMIL `fill="freeze"` reveal ends up here) is 7.6us per icon per frame
  ///    **cheaper** than the exact pipeline.
  ///
  /// The end-to-end effect of that two-sided trade WAS measured, on a Huawei
  /// STG-AL00 over 4 same-binary paired runs of the 1000-icon scrolling
  /// benchmark: raster 26.06ms -> 23.28ms (-2.78ms, distributions disjoint)
  /// but build 14.01ms -> 16.56ms (+2.55ms, also disjoint), netting
  /// real_fps 34.58 -> 33.74 (-2.4%). Trading 2.78ms of GPU time for 2.55ms of
  /// CPU time does not pay on that device, so it is not the default.
  ///
  /// It may well pay on a device whose GPU is weaker relative to its CPU —
  /// offscreen render passes cost more there, path construction costs less, and
  /// the sign flips. Re-decide it with the benchmark's three-arm mode
  /// (`--dart-define=QUALITYAB=true`), which exists for exactly this. See
  /// `doc/performance-benchmarks.md`.
  ///
  /// **与跳帧不同，本项默认关闭（opt-in）**，原因是证据不足，而不是对正确性没底
  /// （正确性由 `test/animation/mask_clip_approximation_test.dart` 覆盖）。已实测
  /// 的部分：
  ///
  ///  - 在真实 399 图标语料上它去掉了 47.7% 的离屏渲染通道（确定性统计），而在
  ///    华为 STG-AL00 上每个通道约值 221us 的 GPU 时间；
  ///  - 但它把工作搬到了 UI 线程，方向取决于 mask 是否在动：主机侧实测，*在动*的
  ///    mask 每图标每帧要多花 29us 重建裁剪路径，而*已定格*的 mask（所有 SMIL
  ///    `fill="freeze"` 揭示动画最终都会到这个状态）反而比精确管线**便宜**
  ///    7.6us/图标/帧。
  ///
  /// 这笔双向交易的端到端净效果**已经实测**：华为 STG-AL00 上,千图标滚动基准的
  /// 4 次同二进制配对运行显示 raster 26.06ms → 23.28ms（−2.78ms，两臂分布不重叠），
  /// 但 build 14.01ms → 16.56ms（+2.55ms，同样不重叠），净得 real_fps
  /// 34.58 → 33.74（−2.4%）。把 2.78ms 的 GPU 时间换成 2.55ms 的 CPU 时间，在那台
  /// 设备上不赚钱，所以它不是默认值。
  ///
  /// 但在 GPU 相对 CPU 更弱的设备上它很可能是赚的——那里离屏渲染通道更贵、路径构建
  /// 更便宜，符号就会翻转。用基准的三臂模式（`--dart-define=QUALITYAB=true`）在新
  /// 设备上重新判定即可，它就是为此存在的。见 `doc/performance-benchmarks.md`。
  final bool approximateSimpleMasksAsClip;

  /// Whether the mask-as-clip approximation is in force at [concurrency]
  /// concurrently-animating icons.
  ///
  /// Gated on the same threshold as frame skipping so that a UI showing a
  /// handful of animated icons is rendered by the exact mask pipeline, byte
  /// for byte as before — the approximation only appears in the batch case it
  /// was measured to help.
  ///
  /// 在 [concurrency] 个并发动画图标下，mask-转-clip 近似是否生效。
  ///
  /// 与跳帧共用同一个阈值，因此只显示少量动画图标的界面走的仍是精确 mask 管线、
  /// 与此前逐字节一致——近似只出现在实测证明它有用的批量场景里。
  ///
  /// [concurrency] — how many icons are animating right now.
  ///
  ///   当前有多少图标在播放动画。
  ///
  /// Returns true when masks may be approximated.
  ///
  ///   可以近似 mask 时返回 true。
  bool approximatesMasksAt(int concurrency) =>
      approximateSimpleMasksAsClip && concurrency > frameSkipThreshold;

  /// The number of display frames per timeline sample for one icon, given how
  /// many icons are currently animating and whether this icon's document
  /// needs an offscreen layer. 1 means "sample every frame" (no degradation).
  ///
  /// 给定当前正在播放动画的图标总数、以及本图标的文档是否需要离屏图层，返回该
  /// 图标每采样一次时间线要经过多少个显示帧。1 表示"每帧都采样"（不降级）。
  ///
  /// [concurrency] — how many icons are animating right now.
  ///
  ///   当前有多少图标在播放动画。
  ///
  /// [usesOffscreenLayers] — whether this icon's document needs `saveLayer`.
  ///
  ///   本图标的文档是否需要 `saveLayer`。
  ///
  /// Returns the frame divisor, always >= 1.
  ///
  ///   返回帧除数，恒 >= 1。
  int frameDivisorFor({
    required int concurrency,
    required bool usesOffscreenLayers,
  }) {
    if (!adaptiveFrameSkipping) return 1;
    if (concurrency <= frameSkipThreshold) return 1;
    if (!usesOffscreenLayers) return maxFrameDivisor;
    return offscreenLayerFrameDivisor > maxFrameDivisor
        ? offscreenLayerFrameDivisor
        : maxFrameDivisor;
  }

  @override
  bool operator ==(Object other) =>
      other is SvgxAnimationQuality &&
      other.adaptiveFrameSkipping == adaptiveFrameSkipping &&
      other.frameSkipThreshold == frameSkipThreshold &&
      other.maxFrameDivisor == maxFrameDivisor &&
      other.offscreenLayerFrameDivisor == offscreenLayerFrameDivisor &&
      other.approximateSimpleMasksAsClip == approximateSimpleMasksAsClip;

  @override
  int get hashCode => Object.hash(
    adaptiveFrameSkipping,
    frameSkipThreshold,
    maxFrameDivisor,
    offscreenLayerFrameDivisor,
    approximateSimpleMasksAsClip,
  );

  @override
  String toString() =>
      'SvgxAnimationQuality(adaptiveFrameSkipping: $adaptiveFrameSkipping, '
      'frameSkipThreshold: $frameSkipThreshold, '
      'maxFrameDivisor: $maxFrameDivisor, '
      'offscreenLayerFrameDivisor: $offscreenLayerFrameDivisor, '
      'approximateSimpleMasksAsClip: $approximateSimpleMasksAsClip)';
}
