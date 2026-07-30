import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/model/fit.dart';
import '../../core/model/quality.dart';
import '../../core/model/source.dart';
import '../../core/options/theme.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';

/// Composite component for the top control bar: title (expanded) followed
/// by pip / quality / fit / fullscreen / lock buttons, matching 0.1.0's
/// `_topBar()` row order.
///
/// Each child button decides its own visibility independently in its own
/// `build` (returning `SizedBox.shrink()` when not applicable) instead of
/// this parent deciding via `if` — so patching out one button never affects
/// the others.
///
/// 顶部控制条组合组件：标题（撑开）后依次跟 pip / 清晰度 / 观看模式 / 全屏 /
/// 锁定按钮，行序对齐 0.1.0 的 `_topBar()`。
///
/// 每个子按钮在各自 `build` 里独立判断是否显示（不适用时返回
/// `SizedBox.shrink()`），而非由该父组件用 `if` 统一控制——这样 patch 掉某个
/// 按钮不会影响其他按钮。
class TopBarComponent extends VmComponent {
  /// Creates the top-bar composite with its 6 fixed children.
  ///
  /// 创建带 6 个固定子组件的顶栏组合组件。
  TopBarComponent();

  @override
  String get name => 'topBar';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  List<VmComponent> get children => [
        TitleComponent(),
        PipButtonComponent(),
        QualityButtonComponent(),
        FitButtonComponent(),
        FullscreenButtonComponent(),
        LockButtonComponent(),
      ];

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmGradientBar(
      top: true,
      theme: theme,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Expanded(child: children[0]),
          ...children.sublist(1),
        ],
      ),
    );
  }
}

/// Displays the current source's title, ellipsized to one line.
///
/// Reads [VmApi.sourceTitle] (not part of [VmState]/[VmApi.states]), so
/// reactivity is piggybacked on a [VmSelector] watching [VmState.type] —
/// [VmApi.open] always updates `type` as part of the same synchronous state
/// emit that updates the open source, so watching it is sufficient to
/// rebuild this leaf whenever a new source (and thus title) is opened.
///
/// 展示当前源的标题，超一行省略。
///
/// 读取 [VmApi.sourceTitle]（不属于 [VmState]/[VmApi.states]），因此借助
/// 监听 [VmState.type] 的 [VmSelector] 实现响应式重建——[VmApi.open] 总是
/// 在更新已打开源的同一次同步状态发射中更新 `type`，所以监听它足以在每次
/// 打开新源（从而标题变化）时重建该叶子组件。
class TitleComponent extends VmComponent {
  /// Creates the title leaf component.
  ///
  /// 创建标题叶子组件。
  TitleComponent();

  @override
  String get name => 'title';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<VmStreamType>(
      selector: (s) => s.type,
      builder: (context, _) {
        final title = api.sourceTitle ?? '';
        return Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Color(theme.textColor), fontSize: theme.titleFontSize),
        );
      },
    );
  }
}

/// Picture-in-picture entry button.
///
/// GAP: `VmApi` exposes no synchronous "is PiP supported" getter (the
/// underlying `VmPipPort.isSupported()` is async and isn't surfaced on
/// `VmApi` at all), so this component cannot decide its visibility from a
/// capability check the way 0.1.0's `player.dart` did (it probed
/// asynchronously in `initState` and stored the result in local widget
/// state). Per the task brief's documented fallback, the button therefore
/// always shows; tapping calls [VmApi.enterPip], which resolves to `false`
/// and no-ops on unsupported platforms. See the task report for the full
/// writeup.
///
/// 画中画入口按钮。
///
/// 缺口：`VmApi` 未暴露同步的"是否支持画中画" getter（底层
/// `VmPipPort.isSupported()` 是异步的，且完全未在 `VmApi` 上暴露），因此该
/// 组件无法像 0.1.0 的 `player.dart` 那样做能力判断来决定可见性（后者在
/// `initState` 里异步探测并存入本地 widget state）。按任务简报记录的兜底
/// 方案，该按钮始终显示；点击调用 [VmApi.enterPip]，在不支持的平台上会
/// 解析为 `false` 并静默无效果。完整说明见任务报告。
class PipButtonComponent extends VmComponent {
  /// Creates the pip-button leaf component.
  ///
  /// 创建画中画按钮叶子组件。
  PipButtonComponent();

  @override
  String get name => 'pipButton';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmIconButton(
      icon: Icons.picture_in_picture_alt_rounded,
      theme: theme,
      onPressed: () => api.enterPip(),
    );
  }
}

/// Quality-picker button; hides when the current source has no selectable
/// quality variants.
///
/// Reproduces 0.1.0's `showModalBottomSheet` quality picker
/// (`player.dart`'s `_showQualityMenu`): a bottom sheet listing every
/// `VmQuality`, checkmarking the active one, and calling
/// [VmApi.switchQuality] on tap.
///
/// 清晰度选择按钮；当前源无可选清晰度档位时隐藏。
///
/// 复刻 0.1.0 的 `showModalBottomSheet` 清晰度选择器（`player.dart` 的
/// `_showQualityMenu`）：底部弹出列出全部 `VmQuality`，勾选当前档位，点击
/// 调用 [VmApi.switchQuality]。
class QualityButtonComponent extends VmComponent {
  /// Creates the quality-button leaf component.
  ///
  /// 创建清晰度按钮叶子组件。
  QualityButtonComponent();

  @override
  String get name => 'qualityButton';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<List<VmQuality>>(
      selector: (s) => s.qualities,
      builder: (context, qualities) {
        if (qualities.isEmpty) return const SizedBox.shrink();
        return VmSelector<VmQuality?>(
          selector: (s) => s.currentQuality,
          builder: (context, current) {
            return VmIconButton(
              icon: Icons.high_quality_rounded,
              theme: theme,
              caption: current?.label,
              onPressed: () => _showQualityMenu(context, api, qualities, current, theme),
            );
          },
        );
      },
    );
  }

  /// Opens a bottom sheet to pick a quality; tapping an item calls
  /// [VmApi.switchQuality] and dismisses the sheet.
  ///
  /// 打开底部弹出选择清晰度；点击某项调用 [VmApi.switchQuality] 并关闭弹层。
  ///
  /// - [context]: build context used to show the sheet / 用于弹出弹层的构建上下文
  /// - [api]: capability surface to switch quality on / 用于切换清晰度的能力面
  /// - [qualities]: the selectable quality list / 可选清晰度列表
  /// - [current]: the currently active quality, if any / 当前生效的清晰度（若有）
  /// - [theme]: theme used to style the sheet's text / 用于弹层文字样式的主题
  void _showQualityMenu(
    BuildContext context,
    VmApi api,
    List<VmQuality> qualities,
    VmQuality? current,
    VmTheme theme,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xEE1A1A1A),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final q in qualities)
                ListTile(
                  title: Text(q.label, style: TextStyle(color: Color(theme.textColor))),
                  trailing: (current?.uri == q.uri && current?.isAuto == q.isAuto)
                      ? Icon(Icons.check_rounded, color: Color(theme.iconColor))
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    api.switchQuality(q);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Fit-mode cycling button; label reflects [VmApi.options]'s configured
/// [VmStrings], tap cycles `VmFit.contain → cover → fill → contain`.
///
/// 观看模式循环切换按钮；标签取自 [VmApi.options] 配置的 `VmStrings`，点击
/// 循环 `VmFit.contain → cover → fill → contain`。
class FitButtonComponent extends VmComponent {
  /// Creates the fit-button leaf component.
  ///
  /// 创建观看模式按钮叶子组件。
  FitButtonComponent();

  @override
  String get name => 'fitButton';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<VmFit>(
      selector: (s) => s.fit,
      builder: (context, fit) {
        return VmIconButton(
          icon: Icons.aspect_ratio_rounded,
          theme: theme,
          caption: api.options.strings.fitLabel(fit),
          onPressed: () => api.setFit(fit.next),
        );
      },
    );
  }
}

/// Fullscreen toggle button; icon flips between enter/exit fullscreen glyphs
/// based on [VmState.fullscreen].
///
/// 全屏切换按钮；图标依据 [VmState.fullscreen] 在进入/退出全屏两种图形间切换。
class FullscreenButtonComponent extends VmComponent {
  /// Creates the fullscreen-button leaf component.
  ///
  /// 创建全屏按钮叶子组件。
  FullscreenButtonComponent();

  @override
  String get name => 'fullscreenButton';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<bool>(
      selector: (s) => s.fullscreen,
      builder: (context, fullscreen) {
        return VmIconButton(
          icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          theme: theme,
          onPressed: () => api.setFullscreen(!fullscreen),
        );
      },
    );
  }
}

/// Lock toggle button; icon reflects [VmState.locked].
///
/// 锁定切换按钮；图标反映 [VmState.locked]。
class LockButtonComponent extends VmComponent {
  /// Creates the lock-button leaf component.
  ///
  /// 创建锁定按钮叶子组件。
  LockButtonComponent();

  @override
  String get name => 'lockButton';

  @override
  VmSlot get slot => VmSlot.top;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<bool>(
      selector: (s) => s.locked,
      builder: (context, locked) {
        return VmIconButton(
          icon: locked ? Icons.lock_rounded : Icons.lock_open_rounded,
          theme: theme,
          onPressed: () => api.setLocked(!locked),
        );
      },
    );
  }
}
