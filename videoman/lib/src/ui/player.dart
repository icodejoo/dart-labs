import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/api.dart';
import '../core/model/fit.dart';
import 'fit_ext.dart';
import 'scope/scope.dart';
import 'scope/selector.dart';
import 'skins/default_skin.dart';
import 'skins/skin.dart';
import 'slots/tree.dart';

/// The top-level videoman player widget: wires a real (or fake) [VmApi] to
/// the raw video render surface and a [VmSkin]'s component tree.
///
/// This widget owns no playback state itself — every visual and behavioral
/// detail flows from [api]'s streams via [VmScope]/[VmSelector] down to the
/// components a [VmSkin] builds. The only things this widget does on its
/// own: publish [api] via [VmScope], render the video surface (or a
/// placeholder in tests, see [renderHandle] below), rebuild the skin's
/// component tree on every [VmApi.states] change, and optionally probe HLS
/// quality variants once after mounting.
///
/// videoman 的顶层播放器组件：把一个真实（或假的）[VmApi] 接到原始视频渲染
/// 画面与 [VmSkin] 的组件树上。
///
/// 本组件自身不持有任何播放状态——每个视觉与行为细节都经由 [api] 的流，
/// 通过 [VmScope]/[VmSelector] 流向 [VmSkin] 构建出的组件。本组件自己只做：
/// 通过 [VmScope] 发布 [api]、渲染视频画面（测试环境下渲染占位符，见下方
/// [renderHandle] 说明）、在每次 [VmApi.states] 变化时重建皮肤组件树，以及
/// 挂载后可选地探测一次 HLS 清晰度档位。
class VmPlayer extends StatefulWidget {
  /// Creates the player widget.
  ///
  /// 创建播放器组件。
  const VmPlayer({
    super.key,
    required this.api,
    this.skin = const VmDefaultSkin(),
    this.autoLoadQualities = true,
  });

  /// Playback facade driving this widget.
  ///
  /// 驱动本组件的播放能力面。
  final VmApi api;

  /// Component tree provider.
  ///
  /// 组件树提供者。
  final VmSkin skin;

  /// Whether to probe HLS quality variants after opening a source.
  ///
  /// 打开源后是否自动探测 HLS 清晰度档位。
  final bool autoLoadQualities;

  @override
  State<VmPlayer> createState() => _VmPlayerState();
}

/// State for [VmPlayer]; owns only the one-time post-mount quality probe —
/// everything else is derived on every rebuild from [VmApi] streams.
///
/// [VmPlayer] 的状态；仅持有挂载后的一次性清晰度探测——其余一切都在每次
/// 重建时由 [VmApi] 的流派生而来。
class _VmPlayerState extends State<VmPlayer> {
  @override
  void initState() {
    super.initState();
    // `loadQualities()` is a no-op for non-HLS sources (VmEngine just clears
    // the quality list), so it's always safe to call unconditionally here.
    //
    // 对非 HLS 源，`loadQualities()` 是空操作（VmEngine 只会清空清晰度
    // 列表），因此这里无条件调用总是安全的。
    if (widget.autoLoadQualities) {
      widget.api.loadQualities();
    }
  }

  @override
  Widget build(BuildContext context) {
    return VmScope(
      api: widget.api,
      // The tree is static (components() no longer varies by state) — build it
      // once here rather than rebuilding the whole tree on every state change;
      // reactivity lives inside the components' own VmSelectors.
      //
      // 组件树是静态的（components() 不再随状态变化）——在此只构建一次，而非
      // 每次状态变化都重建整棵树；响应式都在组件自身的 VmSelector 里。
      child: Builder(
        builder: (context) {
          final tree = widget.skin.components();
          final bundle = buildSlots(context, widget.api, tree);
          return widget.skin.assemble(context, bundle, const _RenderSurface());
        },
      ),
    );
  }
}

/// The raw video render surface: a real media_kit [Video] when the current
/// [VmApi.renderHandle] is a [VideoController], otherwise a black
/// placeholder — the latter lets widget tests exercise the whole skin/scope
/// tree without ever touching a real media_kit player.
///
/// 原始视频渲染画面：当前 [VmApi.renderHandle] 为 [VideoController] 时渲染
/// 真实的 media_kit [Video]，否则渲染黑色占位符——后者让组件测试无需接触
/// 真实 media_kit 播放器即可跑通整棵皮肤/scope 树。
class _RenderSurface extends StatelessWidget {
  /// Creates the render surface.
  ///
  /// 创建渲染画面。
  const _RenderSurface();

  @override
  Widget build(BuildContext context) {
    final api = VmScope.of(context);
    return ColoredBox(
      color: const Color(0xFF000000),
      child: VmSelector<({VmFit fit, double zoom})>(
        selector: (s) => (fit: s.fit, zoom: s.zoom),
        builder: (context, value) {
          final handle = api.renderHandle;
          final video = handle is VideoController
              ? Video(controller: handle, controls: NoVideoControls, fit: vmBoxFit(value.fit))
              : const ColoredBox(color: Color(0xFF000000));
          return ClipRect(
            child: Transform.scale(scale: value.zoom, child: video),
          );
        },
      ),
    );
  }
}
