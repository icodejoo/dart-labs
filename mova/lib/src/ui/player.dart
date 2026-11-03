import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/api.dart';
import '../core/kernel/restart_observer.dart';
import '../core/model/fit.dart';
import '../core/model/source.dart';
import 'fit_ext.dart';
import 'poster.dart';
import 'scope/scope.dart';
import 'scope/selector.dart';
import 'scope/video_rect_scope.dart';
import 'skins/default_skin.dart';
import 'snapshot_guard.dart';
import 'skins/skin.dart';
import 'slots/tree.dart';
import 'slots/component.dart';
import 'video_rect.dart';

/// The top-level mova player widget: wires a real (or fake) [MovaApi] to
/// the raw video render surface and a [MovaSkin]'s component tree.
///
/// This widget owns no playback state itself — every visual and behavioral
/// detail flows from [api]'s streams via [MovaScope]/[MovaSelect] down to the
/// components a [MovaSkin] builds. The only things this widget does on its
/// own: publish [api] via [MovaScope], render the video surface (or a
/// placeholder in tests, see [renderHandle] below), cache the skin's
/// component tree until the skin or api changes, and optionally probe HLS
/// quality variants once after mounting.
///
/// mova 的顶层播放器组件：把一个真实（或假的）[MovaApi] 接到原始视频渲染
/// 画面与 [MovaSkin] 的组件树上。
///
/// 本组件自身不持有任何播放状态——每个视觉与行为细节都经由 [api] 的流，
/// 通过 [MovaScope]/[MovaSelect] 流向 [MovaSkin] 构建出的组件。本组件自己只做：
/// 通过 [MovaScope] 发布 [api]、渲染视频画面（测试环境下渲染占位符，见下方
/// [renderHandle] 说明）、缓存皮肤组件树直到 skin 或 api 改变，以及
/// 挂载后可选地探测一次 HLS 清晰度档位。
class MovaPlayer extends StatefulWidget {
  /// Creates the player widget.
  ///
  /// 创建播放器组件。
  const MovaPlayer({
    super.key,
    required this.api,
    this.skin = const MovaDefaultSkin(),
    this.autoLoadQualities = true,
    this.surface,
    this.fit,
    this.poster,
    this.posterFade = const Duration(milliseconds: 300),
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

  /// Declarative fit for [api]. `null` leaves the engine untouched. Otherwise it
  /// is applied when this widget mounts and again only when this value changes
  /// (or [api] changes) — a user's fit-button choice survives unrelated rebuilds
  /// until the parent passes a *different* fit.
  ///
  /// [api] 的声明式填充模式。`null` 表示不碰引擎。否则在本组件挂载时应用一次，之后
  /// 只有该值变化（或换了 [api]）才再应用——用户用 fit 按钮选的值在无关重建中保留，
  /// 直到父组件传入一个**不同的** fit。
  ///
  /// Example / 示例:
  /// ```dart
  /// MovaPlayer(api: engine, fit: MovaFit.cover)
  /// ```
  final MovaFit? fit;

  /// A widget painted over the video surface until the current source shows
  /// its first frame, then faded out; re-covers instantly on every source
  /// change. Sits *under* the skin's chrome (buffering spinner, error, bars).
  /// Stays visible for sources/engines without a picture (audio-only).
  /// `null` (the default) adds nothing to the tree.
  ///
  /// 盖在视频画面上的组件，当前源出首帧后淡出；每次换源立即重新盖上。位于皮肤
  /// chrome（缓冲转圈、错误层、控制条）**之下**。没有画面的源/引擎（仅音频）时
  /// 常驻。默认 `null`，不向树中添加任何节点。
  ///
  /// Example / 示例:
  /// ```dart
  /// MovaPlayer(api: engine, poster: Image.network(coverUrl, fit: BoxFit.cover))
  /// ```
  final Widget? poster;

  /// How long the poster takes to fade out; re-covering is always instant.
  ///
  /// 封面淡出的时长；重新盖上始终是瞬间完成。
  final Duration posterFade;

  @override
  State<MovaPlayer> createState() => _MovaPlayerState();
}

/// State for [MovaPlayer]: caches skin structure and owns view-local keyboard focus.
/// Playback remains derived from [MovaApi] streams.
///
/// [MovaPlayer] 的状态：缓存皮肤结构并持有当前视图的键盘焦点；播放状态仍来自 API。
class _MovaPlayerState extends State<MovaPlayer> {
  /// 当前 api/皮肤对应的静态组件定义。
  late List<MovaComponent> _components;

  /// 复用构建子树，避免宿主无关重建引发组件重新构建和订阅。
  Widget? _skinTree;

  /// 当前视图的快捷键焦点；不与其他播放器共享。
  final FocusNode _shortcutFocus = FocusNode(debugLabel: 'MovaPlayer');

  @override
  void initState() {
    super.initState();
    _components = widget.skin.components();
    // `loadQualities()` is a no-op for non-HLS sources (MovaEngine just clears
    // the quality list), so it's always safe to call unconditionally here.
    //
    // 对非 HLS 源，`loadQualities()` 是空操作（MovaEngine 只会清空清晰度
    // 列表），因此这里无条件调用总是安全的。
    if (widget.autoLoadQualities) {
      widget.api.loadQualities();
    }
    _observePosterRestarts();
    _applyFit(apiChanged: true);
  }

  @override
  void didUpdateWidget(MovaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.api, widget.api) ||
        !identical(oldWidget.skin, widget.skin)) {
      _components = widget.skin.components();
      _skinTree = null;
    }
    if (oldWidget.surface != widget.surface ||
        oldWidget.poster != widget.poster ||
        oldWidget.posterFade != widget.posterFade) {
      _skinTree = null;
    }
    _observePosterRestarts();
    _applyFit(previous: oldWidget.fit, apiChanged: oldWidget.api != widget.api);
  }

  /// 挂封面时请求精确首帧，支持在 open 后才挂载的播放器。
  void _observePosterRestarts() {
    final api = widget.api;
    if (widget.poster != null && api is MovaRestartObserver) {
      (api as MovaRestartObserver).observeRestarts();
    }
  }

  /// 离场时释放视图持有的焦点。
  @override
  void dispose() {
    _shortcutFocus.dispose();
    super.dispose();
  }

  /// 是否允许快捷键，避免影响编辑控件及隐藏的页面播放器。
  bool _canHandleShortcut() {
    final state = widget.api.state;
    final context = FocusManager.instance.primaryFocus?.context;
    final editing =
        context?.findAncestorStateOfType<EditableTextState>() != null ||
        context?.widget is EditableText;
    return widget.api.options.controls.shortcuts &&
        !editing &&
        !state.locked &&
        !state.pip &&
        !state.mini;
  }

  /// 将 [command] 转为公开 API 意图；不直接修改播放状态。
  Future<void> _runShortcut(_PlayerCommand command) async {
    if (!_canHandleShortcut()) return;
    final api = widget.api;
    switch (command) {
      case _PlayerCommand.toggle:
        await api.playOrPause();
      case _PlayerCommand.backward:
      case _PlayerCommand.forward:
        if (api.state.type == MovaStreamType.live && !api.state.liveSeekable) {
          return;
        }
        await api.seekBy(
          Duration(seconds: command == _PlayerCommand.forward ? 10 : -10),
        );
      case _PlayerCommand.louder:
      case _PlayerCommand.quieter:
        final delta = command == _PlayerCommand.louder ? 5 : -5;
        await api.setVolume((api.state.volume + delta).clamp(0, 100));
      case _PlayerCommand.fullscreen:
        await api.setFullscreen(!api.state.fullscreen);
      case _PlayerCommand.exitFullscreen:
        if (api.state.fullscreen) await api.setFullscreen(false);
    }
    if (mounted) api.showControls();
  }

  /// 鼠标进入或移动时唤出当前页面的控制条。
  void _showOnHover() {
    final state = widget.api.state;
    if (!state.locked && !state.pip && !state.mini) widget.api.showControls();
  }

  /// Applies [MovaPlayer.fit] to the api when it is new (first mount, a changed
  /// value, or a different api); a no-op for `null`.
  ///
  /// 在 [MovaPlayer.fit] 属于"新值"（首次挂载、值变化、或换了 api）时应用到 api；
  /// 为 `null` 时什么都不做。
  ///
  /// - [previous]: the fit of the previous widget configuration / 上一份配置的 fit
  /// - [apiChanged]: whether the api instance is new to this state / api 实例是否是新的
  void _applyFit({MovaFit? previous, bool apiChanged = false}) {
    final f = widget.fit;
    if (f == null) return;
    if (!apiChanged && previous == f) return;
    if (widget.api.state.fit != f) widget.api.setFit(f);
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
      child: MouseRegion(
        onEnter: (_) => _showOnHover(),
        onHover: (_) => _showOnHover(),
        child: Shortcuts(
          shortcuts: widget.api.options.controls.shortcuts
              ? _playerShortcuts
              : const {},
          child: Actions(
            actions: {
              _PlayerIntent: _PlayerAction(
                _canHandleShortcut,
                (command) => unawaited(_runShortcut(command)),
              ),
            },
            child: Focus(
              focusNode: _shortcutFocus,
              onFocusChange: (focused) {
                if (focused) _showOnHover();
              },
              canRequestFocus: widget.api.options.controls.shortcuts,
              skipTraversal: !widget.api.options.controls.shortcuts,
              child: Listener(
                onPointerDown: (_) {
                  if (widget.api.options.controls.shortcuts) {
                    _shortcutFocus.requestFocus();
                  }
                },
                child: KeyedSubtree(
                  key: ValueKey(widget.api),
                  child: _skinTree ??= Builder(
                    builder: (context) {
                      final bundle = buildSlots(
                        context,
                        widget.api,
                        _components,
                      );
                      final surface = widget.surface ?? const _RenderSurface();
                      final poster = widget.poster;
                      // The poster lives inside the `video` handed to the skin, so every
                      // skin's chrome (spinner, error, bars) paints above it.
                      //
                      // 封面放在交给皮肤的 `video` 里面，因此所有皮肤的 chrome（转圈、错误层、
                      // 控制条）都画在它之上。
                      final video = poster == null
                          ? surface
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                surface,
                                MovaPosterLayer(
                                  poster: poster,
                                  fade: widget.posterFade,
                                ),
                              ],
                            );
                      final assembled = widget.skin.assemble(
                        context,
                        bundle,
                        video,
                      );
                      // Publishes the video content's actual (letterboxed) display rect
                      // to descendants of the assembled tree, so overlay components
                      // (e.g. the STT subtitle) can align to the picture itself rather
                      // than to the whole player box. Wraps the *whole* assembled tree
                      // (playback + operable + persistent layers are Stack siblings —
                      // see MovaDefaultSkin.assemble) so every layer shares the same
                      // coordinate space as the video surface, which fills the same
                      // constraints.
                      //
                      // 向已装配树的后代发布视频内容的实际（letterbox 后）显示矩形，使
                      // 叠加层组件（如 STT 字幕）能对齐画面本身而非整个播放器容器。包裹
                      // 的是*整棵*已装配树（播放层/操作层/常驻层是同一 Stack 的兄弟节点，
                      // 见 MovaDefaultSkin.assemble），使每一层都与视频画面共享同一坐标
                      // 系——两者填充的是同一份约束。
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          return MovaSelect<
                            ({MovaFit fit, int width, int height})
                          >(
                            selector: (s) =>
                                (fit: s.fit, width: s.width, height: s.height),
                            builder: (context, value) {
                              final videoSize =
                                  value.width > 0 && value.height > 0
                                  ? Size(
                                      value.width.toDouble(),
                                      value.height.toDouble(),
                                    )
                                  : null;
                              final rect = computeVideoContentRect(
                                container: constraints.biggest,
                                videoSize: videoSize,
                                fit: value.fit,
                              );
                              return MovaVideoRectScope(
                                rect: rect,
                                child: assembled,
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 当前视图支持的快捷键动作。
enum _PlayerCommand {
  /// 切换播放。
  toggle,

  /// 后退十秒。
  backward,

  /// 前进十秒。
  forward,

  /// 增加音量。
  louder,

  /// 降低音量。
  quieter,

  /// 切换全屏。
  fullscreen,

  /// 退出全屏。
  exitFullscreen,
}

/// 携带一个播放器动作的键盘意图。
class _PlayerIntent extends Intent {
  /// 创建 [command] 对应的键盘意图。
  const _PlayerIntent(this.command);

  /// 待执行的播放器动作。
  final _PlayerCommand command;
}

/// 将本视图允许处理的快捷键交给 API，禁用时向上层放行。
class _PlayerAction extends Action<_PlayerIntent> {
  /// 绑定可用性检查 [allowed] 与动作处理 [run]。
  _PlayerAction(this.allowed, this.run);

  /// 当前焦点与状态是否允许处理。
  final bool Function() allowed;

  /// 动作处理回调。
  final void Function(_PlayerCommand) run;

  /// 返回当前意图是否可执行。
  @override
  bool isEnabled(_PlayerIntent intent) => allowed();

  /// 执行 [intent] 中的动作，返回空结果。
  @override
  Object? invoke(_PlayerIntent intent) {
    run(intent.command);
    return null;
  }
}

/// 局限在当前播放器焦点子树内的默认快捷键映射。
const Map<ShortcutActivator, Intent> _playerShortcuts = {
  SingleActivator(LogicalKeyboardKey.space, includeRepeats: false):
      _PlayerIntent(_PlayerCommand.toggle),
  SingleActivator(LogicalKeyboardKey.arrowLeft): _PlayerIntent(
    _PlayerCommand.backward,
  ),
  SingleActivator(LogicalKeyboardKey.arrowRight): _PlayerIntent(
    _PlayerCommand.forward,
  ),
  SingleActivator(LogicalKeyboardKey.arrowUp): _PlayerIntent(
    _PlayerCommand.louder,
  ),
  SingleActivator(LogicalKeyboardKey.arrowDown): _PlayerIntent(
    _PlayerCommand.quieter,
  ),
  SingleActivator(LogicalKeyboardKey.keyF, includeRepeats: false):
      _PlayerIntent(_PlayerCommand.fullscreen),
  SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false):
      _PlayerIntent(_PlayerCommand.exitFullscreen),
};

/// The raw video render surface: a real media_kit [Video] when the current
/// [MovaApi.renderHandle] is a [VideoController], otherwise a black
/// placeholder — the latter lets widget tests exercise the whole skin/scope
/// tree without ever touching a real media_kit player.
///
/// 原始视频渲染画面：当前 [MovaApi.renderHandle] 为 [VideoController] 时渲染
/// 真实的 media_kit [Video]，否则渲染黑色占位符——后者让组件测试无需接触
/// 真实 media_kit 播放器即可跑通整棵皮肤/scope 树。
/// A key wrapping the current [MovaApi.renderHandle], distinct from any key a
/// skin might place elsewhere in the tree — lets tests confirm the render
/// surface actually re-read the handle after a rebuild.
///
/// 包裹当前 [MovaApi.renderHandle] 的 key，与皮肤在树中别处可能使用的 key
/// 区分——供测试确认渲染面在重建后确实重新读取了句柄。
class _RenderHandleKey extends ValueKey<Object?> {
  /// Creates the key from [handle].
  ///
  /// 用 [handle] 创建该 key。
  const _RenderHandleKey(super.handle);
}

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
      child: MovaSelect<({MovaFit fit, double zoom, int epoch})>(
        selector: (s) => (fit: s.fit, zoom: s.zoom, epoch: s.renderEpoch),
        builder: (context, value) {
          final handle = api.renderHandle;
          // Keyed by the handle's identity so tests can observe whether a
          // cutover's new handle was actually picked up on rebuild (see
          // MovaState.renderEpoch).
          //
          // 按句柄身份做 key，使测试能观察到重建时是否真的读取了切换后的新
          // 句柄（见 MovaState.renderEpoch）。
          final video = handle is VideoController
              ? Video(
                  key: _RenderHandleKey(handle),
                  controller: handle,
                  controls: NoVideoControls,
                  fit: movaBoxFit(value.fit),
                )
              : ColoredBox(
                  key: _RenderHandleKey(handle),
                  color: const Color(0xFF000000),
                );
          return ClipRect(
            // Windows: keep the texture out of page-transition snapshots, see MovaSnapshotGuard.
            // Windows：别让纹理进页面转场快照，见 MovaSnapshotGuard。
            child: Transform.scale(
              scale: value.zoom,
              child: MovaSnapshotGuard(
                enabled: movaSnapshotGuardNeeded(),
                child: video,
              ),
            ),
          );
        },
      ),
    );
  }
}
