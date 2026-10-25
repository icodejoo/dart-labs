import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Whether the video surface should opt out of page-transition snapshots on the
/// current platform: only Windows, where Flutter 3.47.0/3.47.1 (Impeller) crashes
/// natively when a snapshot contains an external GPU texture.
///
/// 当前平台的视频画面是否要退出页面转场快照：只有 Windows——Flutter 3.47.0/3.47.1（Impeller）
/// 在快照里带外部 GPU 纹理时会原生崩溃。
bool movaSnapshotGuardNeeded() => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// Keeps [child] out of [SnapshotWidget] snapshots (the Material page transitions, e.g.
/// `ZoomPageTransitionsBuilder`, snapshot the page while a route is pushed or popped).
///
/// Why: `TextureLayer` reports that it supports rasterization, so a permissive
/// [SnapshotWidget] hands the video texture to the engine's `LayerTree::Flatten`. On Windows
/// with Impeller, Flutter 3.47.0 and 3.47.1 dereference a null context there and the process dies
/// with `0xC0000005` in `flutter_windows.dll` (flutter/flutter#190774, fixed in 3.47.2). With the
/// guard on, the subtree adds a layer whose `supportsRasterization()` is `false` (the same signal a
/// platform view gives), so a permissive snapshot silently falls back to normal painting.
/// With the guard off this widget is a plain pass-through.
///
/// 让 [child] 不进 [SnapshotWidget] 的快照（Material 页面转场如 `ZoomPageTransitionsBuilder`
/// 会在 push/pop 路由时给页面拍快照）。
///
/// 原因：`TextureLayer` 声明自己支持栅格化，宽松模式的 [SnapshotWidget] 会把视频纹理交给引擎的
/// `LayerTree::Flatten`；Windows + Impeller 下 Flutter 3.47.0/3.47.1 在那里解引用空上下文，进程在
/// `flutter_windows.dll` 里以 `0xC0000005` 退出（flutter/flutter#190774，3.47.2 已修）。开启后子树会
/// 加一层 `supportsRasterization()` 为 `false` 的图层（和平台视图给出的信号一致），宽松快照于是悄悄
/// 退回正常绘制。关闭时本组件就是原样透传。
///
/// Example / 示例:
/// ```dart
/// MovaSnapshotGuard(enabled: movaSnapshotGuardNeeded(), child: video)
/// ```
class MovaSnapshotGuard extends SingleChildRenderObjectWidget {
  /// Creates the guard; [enabled] `false` makes it a pass-through.
  ///
  /// 创建守卫；[enabled] 为 `false` 时原样透传。
  const MovaSnapshotGuard({super.key, required this.enabled, super.child});

  /// Whether the subtree opts out of snapshots.
  ///
  /// 子树是否退出快照。
  final bool enabled;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMovaSnapshotGuard(enabled: enabled);

  @override
  void updateRenderObject(BuildContext context, RenderMovaSnapshotGuard renderObject) {
    renderObject.enabled = enabled;
  }
}

/// Render object behind [MovaSnapshotGuard].
///
/// [MovaSnapshotGuard] 背后的渲染对象。
@visibleForTesting
class RenderMovaSnapshotGuard extends RenderProxyBox {
  /// Creates the render object.
  ///
  /// 创建渲染对象。
  // ignore: prefer_initializing_formals
  RenderMovaSnapshotGuard({required bool enabled}) : _enabled = enabled;

  bool _enabled;

  /// The marker layer, kept across frames so repainting does not allocate.
  ///
  /// 标记图层，跨帧复用，重绘时不再分配。
  final LayerHandle<_NoRasterizationLayer> _layerHandle = LayerHandle<_NoRasterizationLayer>();

  /// Whether the subtree opts out of snapshots.
  ///
  /// 子树是否退出快照。
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _enabled;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_enabled) {
      _layerHandle.layer = null;
      super.paint(context, offset);
      return;
    }
    final layer = _layerHandle.layer ??= _NoRasterizationLayer();
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _layerHandle.layer = null;
    super.dispose();
  }
}

/// A container layer that tells [SnapshotWidget] it cannot be rasterized.
///
/// 告诉 [SnapshotWidget] 自己不能被栅格化的容器图层。
class _NoRasterizationLayer extends ContainerLayer {
  @override
  bool supportsRasterization() => false;
}
