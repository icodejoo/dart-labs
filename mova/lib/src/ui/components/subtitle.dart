import '../style/style.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/options/theme.dart';
import '../../core/state/progress.dart';
import '../../core/stt/cue.dart';
import '../../core/stt/api.dart';
import '../scope/video_rect_scope.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';

/// Shares the picker visibility choice across overlays of the same service.
///
/// 在同一字幕服务的叠加层之间共享选择器的显隐选择。
final _subtitleChoices = Expando<ValueNotifier<bool>>();

/// Returns the UI visibility signal for [stt], initially visible.
///
/// 返回 [stt] 的 UI 显隐信号，初始允许显示。
ValueNotifier<bool> _subtitleChoice(IMovaSttApi stt) =>
    _subtitleChoices[stt] ??= ValueNotifier(true);

/// STT subtitle overlay: renders the cue covering the current playback
/// position, or nothing when none does.
///
/// Hidden entirely when no recognizer is configured (`IMovaApi.stt.languages` is
/// empty) — mirrors [MovaPipButtonComponent]'s "don't render a dead control"
/// convention, just for an overlay instead of a button.
///
/// STT 字幕叠加层：渲染覆盖当前播放位置的字幕；没有则不渲染任何内容。
///
/// 未配置识别器时（`IMovaApi.stt.languages` 为空）整体不渲染——对应
/// [MovaPipButtonComponent]"不渲染一个死掉的控件"的约定，只是这里换成了叠加层
/// 而非按钮。
class MovaSubtitleOverlayComponent extends MovaComponent {
  /// Creates the subtitle-overlay component.
  ///
  /// 创建字幕叠加层组件。
  MovaSubtitleOverlayComponent();

  /// This component's path segment for `MovaPatch` addressing.
  ///
  /// 该组件在 `MovaPatch` 寻址体系里的路径片段。
  static const String componentName = 'subtitleOverlay';

  @override
  String get name => componentName;

  @override
  MovaSlot get slot => MovaSlot.overlay;

  @override
  Widget build(BuildContext context, IMovaApi api, List<Widget> children) {
    if (api.stt.languages.isEmpty) return const SizedBox.shrink();
    return _SubtitleOverlay(api: api);
  }
}

/// Stateful body of [MovaSubtitleOverlayComponent]: re-reads `IMovaApi.stt.current`
/// whenever a new cue arrives or playback position ticks, since a cue can
/// stop covering the position (its `end` passed) without a new cue arriving.
///
/// [MovaSubtitleOverlayComponent] 的有状态主体：每当新字幕产出或播放位置推进时
/// 都重新读取 `IMovaApi.stt.current`——因为字幕可能在没有新字幕产出的情况下
/// 就不再覆盖当前位置（其 `end` 已经过去）。
class _SubtitleOverlay extends StatefulWidget {
  /// Creates the overlay widget.
  ///
  /// 创建叠加层 widget。
  const _SubtitleOverlay({required this.api});

  /// The capability surface this overlay reads from.
  ///
  /// 该叠加层读取的能力面。
  final IMovaApi api;

  @override
  State<_SubtitleOverlay> createState() => _SubtitleOverlayState();
}

/// State for [_SubtitleOverlay].
///
/// [_SubtitleOverlay] 的状态。
class _SubtitleOverlayState extends State<_SubtitleOverlay> {
  /// The cue currently rendered, or null when none covers the position.
  ///
  /// 当前渲染的字幕；无字幕覆盖当前位置时为 null。
  MovaSttCue? _cue;

  StreamSubscription<MovaSttCue>? _cueSub;
  StreamSubscription<MovaProg>? _progressSub;

  @override
  void initState() {
    super.initState();
    _cue = widget.api.stt.current;
    _cueSub = widget.api.stt.cues.listen((_) => _refresh());
    _progressSub = widget.api.progress.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _cueSub?.cancel();
    _progressSub?.cancel();
    super.dispose();
  }

  /// Re-reads `IMovaApi.stt.current` and rebuilds only if it actually changed.
  ///
  /// 重新读取 `IMovaApi.stt.current`，只有真的变化了才重建。
  void _refresh() {
    if (!mounted) return;
    final next = widget.api.stt.current;
    if (next == _cue) return;
    setState(() => _cue = next);
  }

  /// Gap kept between the subtitle bubble and the video content's actual
  /// bottom edge (not the whole player box's edge — see [MovaVideoRectScope]).
  ///
  /// 字幕气泡与视频内容实际底边（而非整个播放器容器底边，见
  /// [MovaVideoRectScope]）之间保留的间距。
  static const double _bottomGap = 24;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _subtitleChoice(widget.api.stt),
      builder: (context, visible, _) =>
          visible ? _buildCue(context) : const SizedBox.shrink(),
    );
  }

  /// Builds the retained cue while subtitles are enabled in the picker.
  ///
  /// 在选择器允许显示字幕时构建保留的字幕。
  Widget _buildCue(BuildContext context) {
    final cue = _cue;
    if (cue == null) return const SizedBox.shrink();
    final theme = MovaPlayerStyle.themeOf(context);
    return IgnorePointer(
      // A LayoutBuilder rather than Positioned: this widget is a plain
      // (non-Positioned) child of the overlay slot's Stack, so it already
      // receives the full container's loose constraints — same box
      // MovaVideoRectScope's rect was computed against. Positioned cannot be
      // used here directly: it requires its nearest ancestor RenderObject to
      // be the Stack itself, and a LayoutBuilder in between breaks that
      // ParentData chain (confirmed by a failed attempt at this simplification
      // during review — see git history).
      //
      // 用 LayoutBuilder 而非 Positioned：本组件是叠加层槽位 Stack 里的普通
      // （非 Positioned）子节点，天然拿到整个容器的宽松约束——与
      // MovaVideoRectScope 的矩形所依据的是同一个盒子。这里不能直接用
      // Positioned：它要求最近的祖先 RenderObject 就是 Stack 本身，中间隔一层
      // LayoutBuilder 会打断这条 ParentData 链（review 阶段试过这个简化写法，
      // 实测直接崩溃，见 git 历史）。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final container = constraints.biggest;
          // Falls back to the whole container when no MovaVideoRectScope is
          // in scope (e.g. this widget rendered outside MovaPlayer in a
          // test), reproducing the pre-fix "align to whole box" behavior.
          //
          // 找不到 MovaVideoRectScope 时（例如本组件在测试里被脱离
          // MovaPlayer 单独渲染）退化为整个容器，复刻修复前"对齐整个容器"的
          // 行为。
          final rect = MovaVideoRectScope.of(
            context,
            fallback: Offset.zero & container,
          );
          return Padding(
            padding: EdgeInsets.only(
              left: rect.left,
              right: (container.width - rect.right).clamp(0, double.infinity),
              bottom: (container.height - rect.bottom + _bottomGap).clamp(
                0,
                double.infinity,
              ),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                // Stable key so tests/verification probes can locate the
                // rendered bubble's RenderBox without matching on text.
                //
                // 固定 key，便于测试/验证探针在不匹配文本内容的情况下定位到
                // 渲染出的气泡 RenderBox。
                key: const ValueKey('movaSubtitleCueBubble'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Color(theme.barGradientColor),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  cue.text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(theme.textColor),
                    fontSize: theme.titleFontSize,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Subtitle entry button; renders nothing when no STT recognizer is configured
/// (`IMovaApi.stt.languages` is empty), matching [MovaPipButtonComponent]'s
/// unsupported-capability convention.
///
/// Tap opens a picker listing every language the configured recognizer covers
/// (a single joint entry for a bilingual recognizer like the default Zipformer,
/// not one row per language — see
/// `doc/notes/2026-08-04-stt-recognizer-decision.md`: only one recognizer is
/// supported per player in this version) plus a "turn off" row.
///
/// 字幕入口按钮；未配置 STT 识别器时（`IMovaApi.stt.languages` 为空）不渲染任何
/// 内容，对应 [MovaPipButtonComponent] 的"能力不支持"约定。
///
/// 点击弹出选择器，列出已配置识别器覆盖的语言（像默认 Zipformer 这样的双语识别器
/// 是一整条联合入口，不是每个语言一行——见
/// `doc/notes/2026-08-04-stt-recognizer-decision.md`：本版本每个播放器只支持一个
/// 识别器），外加一行"关闭字幕"。
class MovaSubtitleButtonComponent extends MovaComponent {
  /// Creates the subtitle-button leaf component.
  ///
  /// 创建字幕按钮叶子组件。
  MovaSubtitleButtonComponent();

  /// This component's path segment for `MovaPatch` addressing.
  ///
  /// 该组件在 `MovaPatch` 寻址体系里的路径片段。
  static const String componentName = 'subtitleButton';

  @override
  String get name => componentName;

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, IMovaApi api, List<Widget> children) {
    if (api.stt.languages.isEmpty) return const SizedBox.shrink();
    return _SubtitleButton(api: api);
  }
}

/// Stateful body of [MovaSubtitleButtonComponent], reading the STT service's
/// actual running state on builds and after commands.
///
/// [MovaSubtitleButtonComponent] 的有状态主体，在构建与命令完成后读取 STT
/// 服务的实际运行状态。
class _SubtitleButton extends StatefulWidget {
  /// Creates the button widget.
  ///
  /// 创建按钮 widget。
  const _SubtitleButton({required this.api});

  /// The capability surface this button drives.
  ///
  /// 该按钮驱动的能力面。
  final IMovaApi api;

  @override
  State<_SubtitleButton> createState() => _SubtitleButtonState();
}

/// State for [_SubtitleButton].
///
/// [_SubtitleButton] 的状态。
class _SubtitleButtonState extends State<_SubtitleButton> {
  /// Whether the current service is actually running.
  ///
  /// 当前服务是否实际处于运行状态。
  bool get _on => widget.api.stt.isRunning;

  @override
  Widget build(BuildContext context) {
    final theme = MovaPlayerStyle.themeOf(context);
    return StreamBuilder<MovaProg>(
      stream: widget.api.progress,
      builder: (context, _) => MovaIconButton(
        label: MovaPlayerStyle.stringsOf(context).subtitles,
        icon: _on
            ? MovaPlayerStyle.iconsOf(context).subtitles
            : MovaPlayerStyle.iconsOf(context).subtitlesOff,
        theme: theme,
        onPressed: () => _showMenu(theme),
      ),
    );
  }

  /// Opens a bottom sheet offering the configured recognizer's languages (as one
  /// joint entry) or turning subtitles off.
  ///
  /// 弹出底部选择器，提供已配置识别器的语言（作为一整条联合入口）或关闭字幕。
  ///
  /// - [theme]: theme used to style the sheet's text / 用于弹层文字样式的主题
  void _showMenu(MovaTheme theme) {
    final stt = widget.api.stt;
    final languages = stt.languages;
    final strings = MovaPlayerStyle.stringsOf(context);
    showMovaOptionSheet(context, theme, [
      MovaSheetItem(
        label: languages.join('/'),
        checked: _on,
        onSelected: () async {
          await stt.start();
          _subtitleChoice(stt).value = stt.isRunning;
          if (mounted) setState(() {});
        },
      ),
      MovaSheetItem(
        label: strings.subtitleOff,
        checked: !_on,
        onSelected: () async {
          await stt.stop();
          _subtitleChoice(stt).value = false;
          if (mounted) setState(() {});
        },
      ),
    ]);
  }
}
