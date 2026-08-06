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

/// The top-level mova player widget: wires a real (or fake) [MovaApi] to
/// the raw video render surface and a [MovaSkin]'s component tree.
///
/// This widget owns no playback state itself — every visual and behavioral
/// detail flows from [api]'s streams via [MovaScope]/[MovaSelect] down to the
/// components a [MovaSkin] builds. The only things this widget does on its
/// own: publish [api] via [MovaScope], render the video surface (or a
/// placeholder in tests, see [renderHandle] below), rebuild the skin's
/// component tree on every [MovaApi.states] change, and optionally probe HLS
/// quality variants once after mounting.
///
/// mova 的顶层播放器组件：把一个真实（或假的）[MovaApi] 接到原始视频渲染
/// 画面与 [MovaSkin] 的组件树上。
///
/// 本组件自身不持有任何播放状态——每个视觉与行为细节都经由 [api] 的流，
/// 通过 [MovaScope]/[MovaSelect] 流向 [MovaSkin] 构建出的组件。本组件自己只做：
/// 通过 [MovaScope] 发布 [api]、渲染视频画面（测试环境下渲染占位符，见下方
/// [renderHandle] 说明）、在每次 [MovaApi.states] 变化时重建皮肤组件树，以及
/// 挂载后可选地探测一次 HLS 清晰度档位。
class MovaPlayer extends StatefulWidget {
  /// Creates the player widget.
  ///
  /// 创建播放器组件。
  const MovaPlayer({
    super.key,
    required this.api,
    this.skin = const MovaDefSkin(),
    this.autoLoadQualities = true,
    this.surface,
  });

  /// Playback facade driving this widget.
  ///
  /// 驱动本组件的播放能力面。
  final MovaApi api;

  /// Component tree provider.
  ///
  /// 组件树提供者。
  final MovaSkin skin;

  /// Whether to probe HLS quality variants after opening a source.
  ///
  /// 打开源后是否自动探测 HLS 清晰度档位。
  final bool autoLoadQualities;

  /// The widget painted underneath the skin's chrome as the video surface;
  /// defaults to the real media_kit surface (a black placeholder in tests).
  ///
  /// Feed pages pass a placeholder here for a page whose pooled engine isn't
  /// ready yet, so that path still goes through [MovaPlayer] and inherits its
  /// api-identity keying (see the [KeyedSubtree] in [build]) rather than
  /// re-assembling the tree without that safety net.
  ///
  /// 在皮肤 chrome 之下作为视频画面绘制的组件；默认渲染真实的 media_kit 画面
  /// （测试环境下为黑色占位）。
  ///
  /// feed 页会在其池引擎尚未就绪时把占位组件传进来，使这条路径也走 [MovaPlayer]、
  /// 继承其按 api 身份做 key 的保证（见 [build] 里的 [KeyedSubtree]），而不是
  /// 抛开那层安全网自行重装组件树。
  final Widget? surface;

  @override
  State<MovaPlayer> createState() => _MovaPlayerState();
}

/// State for [MovaPlayer]; owns only the one-time post-mount quality probe —
/// everything else is derived on every rebuild from [MovaApi] streams.
///
/// [MovaPlayer] 的状态；仅持有挂载后的一次性清晰度探测——其余一切都在每次
/// 重建时由 [MovaApi] 的流派生而来。
class _MovaPlayerState extends State<MovaPlayer> {
  @override
  void initState() {
    super.initState();
    // `loadQualities()` is a no-op for non-HLS sources (MovaEngine just clears
    // the quality list), so it's always safe to call unconditionally here.
    //
    // 对非 HLS 源，`loadQualities()` 是空操作（MovaEngine 只会清空清晰度
    // 列表），因此这里无条件调用总是安全的。
    if (widget.autoLoadQualities) {
      widget.api.loadQualities();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MovaScope(
      api: widget.api,
      // The tree is static (components() no longer varies by state) — build it
      // once here rather than rebuilding the whole tree on every state change;
      // reactivity lives inside the components' own MovaSelects.
      //
      // 组件树是静态的（components() 不再随状态变化）——在此只构建一次，而非
      // 每次状态变化都重建整棵树；响应式都在组件自身的 MovaSelect 里。
      //
      // Keyed by `widget.api`'s identity (regression fix): a handful of
      // descendants (`_SeekBar`, the gesture layer, the preview bubble, the
      // danmaku track) subscribe to `api`'s streams once in `initState`, not
      // per rebuild. A host that swaps to a new `MovaApi`/engine instance while
      // `MovaPlayer` stays mounted at the same tree position (e.g. switching
      // sources by rebuilding with a fresh `createMovaEngine()`, exactly what
      // this package's own example app does) — without this key — would have
      // Flutter reuse those descendants' existing `State` objects rather than
      // remounting them, since same-type-same-key(null) widgets update in
      // place. Their old subscriptions would then point at the previous,
      // now-disposed engine's closed streams forever, so e.g. the seek bar
      // would freeze on the old engine's last position instead of following
      // the new one. Keying by `api` forces a full remount — fresh
      // `initState`s bound to the new instance — whenever the api reference
      // actually changes.
      //
      // 按 `widget.api` 的身份做 key（回归修复）：少数后代（`_SeekBar`、手势层、
      // 预览气泡、弹幕轨道）只在 `initState` 里订阅一次 `api` 的流，而非每次
      // 重建都订阅。宿主若在 `MovaPlayer` 保持挂载于同一树位置的情况下换了一个
      // 新的 `MovaApi`/引擎实例（例如换源时重新 `createMovaEngine()`——本包自己的
      // example app 就是这么做的）——没有这个 key 的话，Flutter 会认为同类型、
      // key 同为 null 的 widget 该原地更新，而非重新挂载这些后代，于是它们
      // 旧的订阅会永远指向前一个、已经 dispose 的引擎的已关闭的流——进度条就
      // 会卡在旧引擎的最后位置，而不会跟上新引擎。按 `api` 做 key，只要 api
      // 引用真的变了就强制整棵子树重新挂载——所有 `initState` 都会用新实例
      // 重新跑一遍。
      child: KeyedSubtree(
        key: ValueKey(widget.api),
        child: Builder(
          builder: (context) {
            final tree = widget.skin.components();
            final bundle = buildSlots(context, widget.api, tree);
            return widget.skin.assemble(context, bundle, widget.surface ?? const _RenderSurface());
          },
        ),
      ),
    );
  }
}

/// The raw video render surface: a real media_kit [Video] when the current
/// [MovaApi.renderHandle] is a [VideoController], otherwise a black
/// placeholder — the latter lets widget tests exercise the whole skin/scope
/// tree without ever touching a real media_kit player.
///
/// 原始视频渲染画面：当前 [MovaApi.renderHandle] 为 [VideoController] 时渲染
/// 真实的 media_kit [Video]，否则渲染黑色占位符——后者让组件测试无需接触
/// 真实 media_kit 播放器即可跑通整棵皮肤/scope 树。
class _RenderSurface extends StatelessWidget {
  /// Creates the render surface.
  ///
  /// 创建渲染画面。
  const _RenderSurface();

  @override
  Widget build(BuildContext context) {
    final api = MovaScope.of(context);
    return ColoredBox(
      color: const Color(0xFF000000),
      child: MovaSelect<({MovaFit fit, double zoom})>(
        selector: (s) => (fit: s.fit, zoom: s.zoom),
        builder: (context, value) {
          final handle = api.renderHandle;
          final video = handle is VideoController
              ? Video(controller: handle, controls: NoVideoControls, fit: movaBoxFit(value.fit))
              : const ColoredBox(color: Color(0xFF000000));
          return ClipRect(
            child: Transform.scale(scale: value.zoom, child: video),
          );
        },
      ),
    );
  }
}
