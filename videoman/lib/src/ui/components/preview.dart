import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/preview/models.dart';
import '../../core/state/ui_state.dart';
import '../format.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// The scrub-preview bubble: a thumbnail plus the target timestamp, floating
/// directly above the seek bar while a drag is in progress.
///
/// Driven purely by [VmUiState.previewAt] — both drag sources (the seek bar's
/// `onChanged` and the gesture layer's horizontal drag) already publish it via
/// `VmApi.setDragging`, so this component needs no knowledge of either.
/// Replace it wholesale with `VmPatch.replace('preview', MyBubble())`.
///
/// 拖动预览气泡：一张缩略图加目标时间戳，拖动过程中浮在进度条正上方。
///
/// 完全由 [VmUiState.previewAt] 驱动——两个拖动来源（进度条的 `onChanged`
/// 与手势层的横滑）都已经通过 `VmApi.setDragging` 发布该字段，因此本组件
/// 无需感知它们中的任何一个。可用 `VmPatch.replace('preview', MyBubble())`
/// 整块替换。
class PreviewComponent extends VmComponent {
  /// Creates the preview-bubble component.
  ///
  /// 创建预览气泡组件。
  PreviewComponent();

  @override
  String get name => 'preview';

  @override
  VmSlot get slot => VmSlot.bottomAbove;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) =>
      _PreviewBubble(api: api);
}

/// Stateful body of [PreviewComponent]: tracks the scrub position from
/// [VmApi.uiStates] and the resolved thumbnail from `VmApi.preview.thumbs`.
///
/// [PreviewComponent] 的有状态主体：从 [VmApi.uiStates] 跟踪拖动位置，从
/// `VmApi.preview.thumbs` 跟踪已解析的缩略图。
class _PreviewBubble extends StatefulWidget {
  /// Creates the bubble widget.
  ///
  /// 创建气泡 widget。
  ///
  /// [api] is the capability surface to request thumbnails through.
  ///
  /// [api] 为用于请求缩略图的能力面。
  const _PreviewBubble({required this.api});

  /// The capability surface this bubble reads from.
  ///
  /// 该气泡读取的能力面。
  final VmApi api;

  @override
  State<_PreviewBubble> createState() => _PreviewBubbleState();
}

/// State for [_PreviewBubble].
///
/// [_PreviewBubble] 的状态。
class _PreviewBubbleState extends State<_PreviewBubble> {
  /// The current scrub position, or null when no drag is in progress.
  ///
  /// 当前拖动位置；无拖动时为 null。
  Duration? _at;

  /// The thumbnail to render, or null while none has resolved yet.
  ///
  /// 要渲染的缩略图；尚未解析出来时为 null。
  VmThumb? _thumb;

  /// Subscription feeding [_at]; cancelled on dispose.
  ///
  /// 为 [_at] 供数的订阅；在 dispose 时取消。
  StreamSubscription<VmUiState>? _uiSub;

  /// Subscription feeding [_thumb]; cancelled on dispose.
  ///
  /// 为 [_thumb] 供数的订阅；在 dispose 时取消。
  StreamSubscription<VmThumb?>? _thumbSub;

  @override
  void initState() {
    super.initState();
    // Seed synchronously from the current snapshot without setState — the
    // first build has not run yet, so assigning the fields directly is both
    // correct and flicker-free.
    //
    // 同步从当前快照播种，不走 setState——首帧尚未构建，直接赋值既正确又不闪。
    final at = widget.api.uiState.previewAt;
    if (at != null) {
      _at = at;
      _thumb = widget.api.preview.peekAt(at);
      widget.api.preview.requestAt(at);
    }
    _uiSub = widget.api.uiStates.listen((s) => _apply(s.previewAt));
    _thumbSub = widget.api.preview.thumbs.listen((t) {
      if (!mounted) return;
      setState(() => _thumb = t);
    });
  }

  @override
  void dispose() {
    _uiSub?.cancel();
    _thumbSub?.cancel();
    super.dispose();
  }

  /// Reacts to a new scrub position: hides on null, otherwise takes the
  /// synchronous cache hit (if any) and asks for the real thumbnail.
  ///
  /// 响应新的拖动位置：为 null 时隐藏；否则先取同步缓存命中（若有），再请求
  /// 真正的缩略图。
  ///
  /// - [at]: the new scrub position, or null when the drag ended / 新的拖动
  ///   位置；拖动结束时为 null
  void _apply(Duration? at) {
    if (at == _at) return;
    if (!mounted) return;
    if (at == null) {
      widget.api.preview.cancel();
      setState(() {
        _at = null;
        _thumb = null;
      });
      return;
    }
    // Take the synchronous cache hit first so an already-resident bucket
    // renders in this very frame; keep the previous frame otherwise, so the
    // bubble shows a stale image rather than blinking to an empty box.
    //
    // 先取同步缓存命中，让已驻留的桶就在本帧渲染出来；没命中则保留上一帧，
    // 让气泡显示一张旧图而不是闪成空框。
    final hit = widget.api.preview.peekAt(at);
    widget.api.preview.requestAt(at);
    setState(() {
      _at = at;
      _thumb = hit ?? _thumb;
    });
  }

  @override
  Widget build(BuildContext context) {
    final at = _at;
    if (at == null) return const SizedBox.shrink();
    final theme = widget.api.options.theme;
    final width = widget.api.options.preview.frameWidth.toDouble();
    final crop = _thumb?.crop;
    final height = crop == null ? width * 9 / 16 : width * crop.h / crop.w;
    // Caption line height is an estimate (font size plus typical leading) —
    // exact glyph metrics aren't known before layout, and a few logical
    // pixels of slack here never causes visible clipping.
    //
    // 字幕行高是估算值（字号加上常见行距）——布局前拿不到精确字形度量，这里
    // 留几个逻辑像素的余量不会造成可见裁切。
    final bubbleHeight = height + 2 + theme.captionFontSize + 6;

    final bubble = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _frame(width, height, crop),
        const SizedBox(height: 2),
        Text(
          formatDuration(at),
          style: TextStyle(
            color: Color(theme.textColor),
            fontSize: theme.captionFontSize,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: bubbleHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            final left = _horizontalOffset(trackWidth, width, at);
            return Stack(
              clipBehavior: Clip.none,
              children: [Positioned(left: left, bottom: 0, child: bubble)],
            );
          },
        ),
      ),
    );
  }

  /// Computes the bubble's horizontal offset so it tracks the scrub position
  /// along the seek bar, clamped so it never overflows either edge.
  ///
  /// 计算气泡的水平偏移，使其沿进度条跟随拖动位置，并钳制到两端不超出边界。
  ///
  /// - [trackWidth]: available width to position within (the full-width
  ///   `bottomAbove` slot, which lines up with the seek bar below it) /
  ///   可用定位宽度（撑满宽度的 `bottomAbove` 槽位，与其下方的进度条对齐）
  /// - [bubbleWidth]: the bubble's own width / 气泡自身宽度
  /// - [at]: the scrub position to project onto the track / 要投影到进度条上的
  ///   拖动位置
  ///
  /// Returns the left offset in logical pixels; centred when the duration
  /// isn't known yet or the track has no measurable width.
  ///
  /// 返回逻辑像素单位的左偏移；总时长未知或轨道宽度不可测时回退为居中。
  double _horizontalOffset(double trackWidth, double bubbleWidth, Duration at) {
    if (!trackWidth.isFinite || trackWidth <= 0) return 0;
    final duration = widget.api.state.duration;
    final centered = (trackWidth - bubbleWidth) / 2;
    if (duration <= Duration.zero) return centered.clamp(0.0, trackWidth);
    final frac = (at.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    final maxLeft = (trackWidth - bubbleWidth).clamp(0.0, trackWidth);
    return (frac * trackWidth - bubbleWidth / 2).clamp(0.0, maxLeft);
  }

  /// Builds the image frame: the whole bitmap, the crop window into a sprite
  /// sheet, or an empty placeholder box while nothing has resolved.
  ///
  /// 构建图像框：整张位图、雪碧图上的裁剪窗口，或尚未解析出内容时的空占位框。
  ///
  /// - [width]: bubble width in logical pixels / 气泡宽度（逻辑像素）
  /// - [height]: bubble height in logical pixels / 气泡高度（逻辑像素）
  /// - [crop]: sprite sub-rectangle, or null for the whole image /
  ///   雪碧图子矩形；为 null 表示整张图
  ///
  /// Returns the framed image widget.
  ///
  /// 返回带边框的图像 widget。
  Widget _frame(double width, double height, VmThumbCrop? crop) {
    final theme = widget.api.options.theme;
    final thumb = _thumb;
    final border = Border.all(color: Color(theme.textColor), width: 1);

    if (thumb == null) {
      return Container(
        key: const ValueKey('vmPreviewPlaceholder'),
        width: width,
        height: height,
        decoration: BoxDecoration(color: Color(theme.barGradientColor), border: border),
      );
    }

    final Widget image = crop == null
        ? Image.memory(
            thumb.bytes,
            width: width,
            height: height,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          )
        : FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: crop.w.toDouble(),
              height: crop.h.toDouble(),
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: Transform.translate(
                  offset: Offset(-crop.x.toDouble(), -crop.y.toDouble()),
                  child: Image.memory(
                    thumb.bytes,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            ),
          );

    return Container(
      decoration: BoxDecoration(border: border),
      child: ClipRect(
        key: const ValueKey('vmPreviewClip'),
        child: SizedBox(width: width, height: height, child: image),
      ),
    );
  }
}
