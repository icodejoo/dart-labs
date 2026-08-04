import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/options/theme.dart';
import '../../core/state/progress.dart';
import '../../core/stt/cue.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';

/// STT subtitle overlay: renders the cue covering the current playback
/// position, or nothing when none does.
///
/// Hidden entirely when no engine is configured (`VmApi.stt.languages` is
/// empty) — mirrors [PipButtonComponent]'s "don't render a dead control"
/// convention, just for an overlay instead of a button.
///
/// STT 字幕叠加层：渲染覆盖当前播放位置的字幕；没有则不渲染任何内容。
///
/// 未配置引擎时（`VmApi.stt.languages` 为空）整体不渲染——对应
/// [PipButtonComponent]"不渲染一个死掉的控件"的约定，只是这里换成了叠加层
/// 而非按钮。
class SubtitleOverlayComponent extends VmComponent {
  /// Creates the subtitle-overlay component.
  ///
  /// 创建字幕叠加层组件。
  SubtitleOverlayComponent();

  @override
  String get name => 'subtitleOverlay';

  @override
  VmSlot get slot => VmSlot.overlay;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    if (api.stt.languages.isEmpty) return const SizedBox.shrink();
    return _SubtitleOverlay(api: api);
  }
}

/// Stateful body of [SubtitleOverlayComponent]: re-reads `VmApi.stt.current`
/// whenever a new cue arrives or playback position ticks, since a cue can
/// stop covering the position (its `end` passed) without a new cue arriving.
///
/// [SubtitleOverlayComponent] 的有状态主体：每当新字幕产出或播放位置推进时
/// 都重新读取 `VmApi.stt.current`——因为字幕可能在没有新字幕产出的情况下
/// 就不再覆盖当前位置（其 `end` 已经过去）。
class _SubtitleOverlay extends StatefulWidget {
  /// Creates the overlay widget.
  ///
  /// 创建叠加层 widget。
  const _SubtitleOverlay({required this.api});

  /// The capability surface this overlay reads from.
  ///
  /// 该叠加层读取的能力面。
  final VmApi api;

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
  VmSttCue? _cue;

  StreamSubscription<VmSttCue>? _cueSub;
  StreamSubscription<VmProgress>? _progressSub;

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

  /// Re-reads `VmApi.stt.current` and rebuilds only if it actually changed.
  ///
  /// 重新读取 `VmApi.stt.current`，只有真的变化了才重建。
  void _refresh() {
    if (!mounted) return;
    final next = widget.api.stt.current;
    if (next == _cue) return;
    setState(() => _cue = next);
  }

  @override
  Widget build(BuildContext context) {
    final cue = _cue;
    if (cue == null) return const SizedBox.shrink();
    final theme = widget.api.options.theme;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 72),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Color(theme.barGradientColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              cue.text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(theme.textColor), fontSize: theme.titleFontSize),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtitle entry button; renders nothing when no STT engine is configured
/// (`VmApi.stt.languages` is empty), matching [PipButtonComponent]'s
/// unsupported-capability convention.
///
/// Tap opens a picker listing every language the configured engine covers
/// (a single joint entry for a bilingual engine like the default Zipformer,
/// not one row per language — see
/// `doc/notes/2026-08-04-stt-engine-decision.md`: only one engine is
/// supported per player in this version) plus a "turn off" row.
///
/// 字幕入口按钮；未配置 STT 引擎时（`VmApi.stt.languages` 为空）不渲染任何
/// 内容，对应 [PipButtonComponent] 的"能力不支持"约定。
///
/// 点击弹出选择器，列出已配置引擎覆盖的语言（像默认 Zipformer 这样的双语引擎
/// 是一整条联合入口，不是每个语言一行——见
/// `doc/notes/2026-08-04-stt-engine-decision.md`：本版本每个播放器只支持一个
/// 引擎），外加一行"关闭字幕"。
class SubtitleButtonComponent extends VmComponent {
  /// Creates the subtitle-button leaf component.
  ///
  /// 创建字幕按钮叶子组件。
  SubtitleButtonComponent();

  @override
  String get name => 'subtitleButton';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    if (api.stt.languages.isEmpty) return const SizedBox.shrink();
    return _SubtitleButton(api: api);
  }
}

/// Stateful body of [SubtitleButtonComponent]: tracks whether this session
/// turned subtitles on, purely as local UI state (`VmApi.stt` exposes no
/// "is running" flag to select on — see the port's doc comment).
///
/// [SubtitleButtonComponent] 的有状态主体：跟踪本次会话是否已开启字幕，纯属
/// 本地 UI 状态（`VmApi.stt` 没有暴露"是否在运行"的字段可供 selector 使用——
/// 见该端口的文档注释）。
class _SubtitleButton extends StatefulWidget {
  /// Creates the button widget.
  ///
  /// 创建按钮 widget。
  const _SubtitleButton({required this.api});

  /// The capability surface this button drives.
  ///
  /// 该按钮驱动的能力面。
  final VmApi api;

  @override
  State<_SubtitleButton> createState() => _SubtitleButtonState();
}

/// State for [_SubtitleButton].
///
/// [_SubtitleButton] 的状态。
class _SubtitleButtonState extends State<_SubtitleButton> {
  /// Whether this session has turned subtitles on.
  ///
  /// 本次会话是否已开启字幕。
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.api.options.theme;
    return VmIconButton(
      icon: _on ? Icons.subtitles_rounded : Icons.subtitles_off_rounded,
      theme: theme,
      onPressed: () => _showMenu(theme),
    );
  }

  /// Opens a bottom sheet offering the configured engine's languages (as one
  /// joint entry) or turning subtitles off.
  ///
  /// 弹出底部选择器，提供已配置引擎的语言（作为一整条联合入口）或关闭字幕。
  ///
  /// - [theme]: theme used to style the sheet's text / 用于弹层文字样式的主题
  void _showMenu(VmTheme theme) {
    final languages = widget.api.stt.languages;
    final strings = widget.api.options.strings;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Color(theme.sheetBackgroundColor),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(languages.join('/'), style: TextStyle(color: Color(theme.textColor))),
                trailing:
                    _on ? Icon(Icons.check_rounded, color: Color(theme.iconColor)) : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await widget.api.stt.start();
                  if (mounted) setState(() => _on = true);
                },
              ),
              ListTile(
                title: Text(strings.subtitleOff, style: TextStyle(color: Color(theme.textColor))),
                trailing:
                    !_on ? Icon(Icons.check_rounded, color: Color(theme.iconColor)) : null,
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await widget.api.stt.stop();
                  if (mounted) setState(() => _on = false);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
