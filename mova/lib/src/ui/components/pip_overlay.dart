import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/api.dart';
import '../../core/options/theme.dart';
import 'common.dart';

/// Builds the mini video surface fed into [MovaPipOverlay.show]: the same
/// [VideoController] the main player renders, wrapped for a small window
/// (fixed `contain` fit — no need for the main surface's fit-mode selector at
/// this size) or a black placeholder when [MovaApi.renderHandle] isn't a
/// [VideoController] (e.g. widget tests).
///
/// 构建喂给 [MovaPipOverlay.show] 的迷你视频画面：与主播放器渲染的同一个
/// [VideoController]，为小窗做了简化包装（固定 `contain` 填充——这个尺寸下无需
/// 主画面那套填充模式选择器）；当 [MovaApi.renderHandle] 不是 [VideoController]
/// 时（例如组件测试）则渲染黑色占位符。
///
/// - [api]: capability surface to read the render handle from / 用于读取
///   渲染句柄的能力面
///
/// Returns the widget to pass as [MovaPipOverlay.show]'s `video` argument /
/// 返回可作为 [MovaPipOverlay.show] `video` 参数传入的 widget。
///
/// Example / 示例:
/// ```dart
/// MovaPipOverlay.show(context, api: api, video: movaPipMiniSurface(api));
/// ```
Widget movaPipMiniSurface(MovaApi api) {
  final handle = api.renderHandle;
  if (handle is VideoController) {
    return Video(controller: handle, controls: NoVideoControls, fit: BoxFit.contain);
  }
  return const ColoredBox(color: Color(0xFF000000));
}

/// In-app floating "mini player" fallback for platforms without real OS-level
/// picture-in-picture (see `doc/notes/2026-07-31-ios-pip-feasibility.md` §3
/// "降级方案" and §8 阶段3).
///
/// This is NOT system PiP — it disappears when the app itself is
/// backgrounded, since it is just a widget inserted into this app's own root
/// [Overlay]. It exists so `MovaApi.enterPip()` has *something* to do on
/// platforms where `MovaApi.pipSupported` is false (desktop today, iOS until
/// its native skeleton lands): [PipButtonComponent] in `top_bar.dart` calls
/// [show] instead of `enterPip()` in that case, reusing the same video
/// surface in a small draggable/resizable window docked above the current
/// page while the rest of the app stays interactive underneath.
///
/// 没有真正系统级画中画的平台上的应用内悬浮"迷你播放器"降级方案（参见
/// `doc/notes/2026-07-31-ios-pip-feasibility.md` §3"降级方案"与§8 阶段3）。
///
/// 这不是系统 PiP——应用本身退到后台时它就会消失，因为它只是插入本应用自己
/// 根 [Overlay] 的一个 widget。它存在的意义是让 `MovaApi.pipSupported` 为
/// false 的平台（当前的桌面端、原生骨架落地前的 iOS）上 `MovaApi.enterPip()`
/// 有事可做：`top_bar.dart` 里的 [PipButtonComponent] 在这种情况下会调用
/// [show] 而非 `enterPip()`，复用同一份视频画面，把它放进一个悬浮在当前页面
/// 之上、可拖动/可缩放的小窗里，同时应用其余部分仍可正常交互。
class MovaPipOverlay {
  MovaPipOverlay._();

  static OverlayEntry? _entry;

  /// Whether the fallback overlay is currently shown.
  ///
  /// 该降级悬浮窗当前是否处于显示状态。
  static bool get isShown => _entry != null;

  /// Shows the fallback overlay hosting [video], or does nothing if one is
  /// already shown.
  ///
  /// Inserted into the root [Overlay] (via `Overlay.of(context, rootOverlay:
  /// true)`) so it floats above the current route rather than being scoped to
  /// wherever [MovaPlayer] happens to sit in the tree.
  ///
  /// - [context]: any context under a [Navigator] / 任意处于 [Navigator] 之下
  ///   的 context
  /// - [api]: capability surface, used to read [MovaTheme] and to close the
  ///   overlay from within it / 能力面，用于读取 [MovaTheme] 及从悬浮窗内部
  ///   关闭它
  /// - [video]: the widget rendering the live video surface (e.g. the same
  ///   `Video(controller: ...)` the main player uses) / 渲染实时视频画面的
  ///   widget（例如主播放器所用的同一个 `Video(controller: ...)`）
  ///
  /// Example / 示例:
  /// ```dart
  /// MovaPipOverlay.show(context, api: api, video: myVideoWidget);
  /// ```
  static void show(BuildContext context, {required MovaApi api, required Widget video}) {
    if (_entry != null) return;
    final overlayState = Overlay.of(context, rootOverlay: true);
    final entry = OverlayEntry(
      builder: (_) => _MovaPipOverlayWidget(theme: api.options.theme, video: video, onClose: hide),
    );
    _entry = entry;
    overlayState.insert(entry);
  }

  /// Hides the fallback overlay if one is shown; safe to call when none is
  /// showing.
  ///
  /// 关闭当前显示的降级悬浮窗；未显示时调用也是安全的。
  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}

/// Draggable/resizable floating window content for [MovaPipOverlay]; owns its
/// own position and size, clamped to the current [MediaQuery] bounds.
///
/// [MovaPipOverlay] 悬浮窗的可拖动/可缩放内容；自行持有位置与尺寸，并按当前
/// [MediaQuery] 边界做夹取。
class _MovaPipOverlayWidget extends StatefulWidget {
  const _MovaPipOverlayWidget({required this.theme, required this.video, required this.onClose});

  final MovaTheme theme;
  final Widget video;
  final VoidCallback onClose;

  @override
  State<_MovaPipOverlayWidget> createState() => _MovaPipOverlayWidgetState();
}

class _MovaPipOverlayWidgetState extends State<_MovaPipOverlayWidget> {
  /// Default/minimum/maximum width of the floating window; height follows a
  /// fixed 16:9 aspect ratio derived from it.
  ///
  /// 悬浮窗的默认/最小/最大宽度；高度按固定 16:9 比例由宽度推导。
  static const double _defaultWidth = 180.0;
  static const double _minWidth = 120.0;
  static const double _maxWidth = 360.0;
  static const double _aspectRatio = 16 / 9;
  static const double _margin = 12.0;

  late double _width = _defaultWidth;
  Offset? _topLeft;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = _width / _aspectRatio;
    // Default to the bottom-right corner on first build; re-clamp on every
    // build so a window resize (e.g. device rotation) can't strand it
    // off-screen.
    //
    // 首次构建时默认停靠右下角；此后每次构建都重新夹取，避免窗口尺寸变化
    // （如设备旋转）把它甩到屏幕外。
    final initial = Offset(size.width - _width - _margin, size.height - height - _margin);
    final topLeft = _clamp(_topLeft ?? initial, size, height);

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: _width,
      height: height,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _topLeft = _clamp(topLeft + d.delta, size, height)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border.all(color: Color(widget.theme.iconColor), width: 1),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 8)],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRect(child: widget.video),
              Positioned(
                right: 0,
                top: 0,
                child: MovaIconButton(
                  icon: Icons.close_rounded,
                  theme: widget.theme,
                  onPressed: widget.onClose,
                ),
              ),
              Positioned(
                left: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (d) => setState(
                    () => _width = (_width + d.delta.dx - d.delta.dy).clamp(_minWidth, _maxWidth),
                  ),
                  child: Icon(Icons.open_in_full_rounded, color: Color(widget.theme.iconColor), size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Keeps the window's top-left corner within the current viewport.
  ///
  /// 把悬浮窗左上角约束在当前视窗范围内。
  Offset _clamp(Offset offset, Size viewport, double height) => Offset(
        offset.dx.clamp(0.0, (viewport.width - _width).clamp(0.0, double.infinity)),
        offset.dy.clamp(0.0, (viewport.height - height).clamp(0.0, double.infinity)),
      );
}
