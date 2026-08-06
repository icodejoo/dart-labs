import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/model/fit.dart';
import '../../core/model/orientation.dart';
import '../../core/model/quality.dart';
import '../../core/options/theme.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';
import 'subtitle.dart';

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
class TopBarComponent extends MovaComp {
  /// Creates the top-bar composite with its 6 fixed children.
  ///
  /// 创建带 6 个固定子组件的顶栏组合组件。
  TopBarComponent();

  @override
  String get name => 'topBar';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  List<MovaComp> get children => [
        TitleComponent(),
        PipButtonComponent(),
        QualityButtonComponent(),
        SubtitleButtonComponent(),
        FitButtonComponent(),
        OrientationButtonComponent(),
        FullscreenButtonComponent(),
      ];

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaGradBar(
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
/// Reads [MovaState.sourceTitle] directly via a [MovaSelect], so it rebuilds
/// whenever the title itself changes — including re-opening a different
/// source of the *same* [MovaState.type] (e.g. VOD → VOD), which does not
/// change `type` and would otherwise be missed if watching `type` instead.
///
/// 展示当前源的标题，超一行省略。
///
/// 通过 [MovaSelect] 直接读取 [MovaState.sourceTitle]，因此标题本身变化时即
/// 会重建——包括重新打开同一 [MovaState.type]（例如点播换点播）的另一个源，
/// 此时 `type` 不会变化，若改为监听 `type` 则会漏掉这种情况。
class TitleComponent extends MovaComp {
  /// Creates the title leaf component.
  ///
  /// 创建标题叶子组件。
  TitleComponent();

  @override
  String get name => 'title';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<String?>(
      selector: (s) => s.sourceTitle,
      builder: (context, sourceTitle) {
        final title = sourceTitle ?? '';
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

/// Picture-in-picture entry button; renders nothing where PiP is unsupported.
///
/// Visibility follows [MovaState.pipSupported], which the engine resolves once
/// from `MovaPipPort.isSupported()` shortly after construction — so on desktop
/// the button never appears at all, rather than appearing and doing nothing.
///
/// 画中画入口按钮；平台不支持画中画时不渲染任何内容。
///
/// 可见性跟随 [MovaState.pipSupported]——engine 在构造后不久用
/// `MovaPipPort.isSupported()` 解析一次。因此桌面端该按钮根本不会出现，而不是
/// 出现了点了没反应。
class PipButtonComponent extends MovaComp {
  /// Creates the pip-button leaf component.
  ///
  /// 创建画中画按钮叶子组件。
  PipButtonComponent();

  @override
  String get name => 'pipButton';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<bool>(
      selector: (s) => s.pipSupported,
      builder: (context, supported) {
        if (!supported) return const SizedBox.shrink();
        return MovaIconButton(
          icon: Icons.picture_in_picture_alt_rounded,
          theme: theme,
          onPressed: () => api.enterPip(),
        );
      },
    );
  }
}

/// Quality-picker button; hides when the current source has no selectable
/// quality variants.
///
/// Reproduces 0.1.0's `showModalBottomSheet` quality picker
/// (`player.dart`'s `_showQualityMenu`): a bottom sheet listing every
/// `MovaQual`, checkmarking the active one, and calling
/// [MovaApi.switchQuality] on tap.
///
/// 清晰度选择按钮；当前源无可选清晰度档位时隐藏。
///
/// 复刻 0.1.0 的 `showModalBottomSheet` 清晰度选择器（`player.dart` 的
/// `_showQualityMenu`）：底部弹出列出全部 `MovaQual`，勾选当前档位，点击
/// 调用 [MovaApi.switchQuality]。
class QualityButtonComponent extends MovaComp {
  /// Creates the quality-button leaf component.
  ///
  /// 创建清晰度按钮叶子组件。
  QualityButtonComponent();

  @override
  String get name => 'qualityButton';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<List<MovaQual>>(
      selector: (s) => s.qualities,
      builder: (context, qualities) {
        if (qualities.isEmpty) return const SizedBox.shrink();
        return MovaSelect<MovaQual?>(
          selector: (s) => s.currentQuality,
          builder: (context, current) {
            return MovaIconButton(
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
  /// [MovaApi.switchQuality] and dismisses the sheet.
  ///
  /// 打开底部弹出选择清晰度；点击某项调用 [MovaApi.switchQuality] 并关闭弹层。
  ///
  /// - [context]: build context used to show the sheet / 用于弹出弹层的构建上下文
  /// - [api]: capability surface to switch quality on / 用于切换清晰度的能力面
  /// - [qualities]: the selectable quality list / 可选清晰度列表
  /// - [current]: the currently active quality, if any / 当前生效的清晰度（若有）
  /// - [theme]: theme used to style the sheet's text / 用于弹层文字样式的主题
  void _showQualityMenu(
    BuildContext context,
    MovaApi api,
    List<MovaQual> qualities,
    MovaQual? current,
    MovaTheme theme,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Color(theme.sheetBackgroundColor),
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

/// Fit-mode cycling button; label reflects [MovaApi.options]'s configured
/// [MovaStrs], tap cycles `MovaFit.contain → cover → fill → contain`.
///
/// 观看模式循环切换按钮；标签取自 [MovaApi.options] 配置的 `MovaStrs`，点击
/// 循环 `MovaFit.contain → cover → fill → contain`。
class FitButtonComponent extends MovaComp {
  /// Creates the fit-button leaf component.
  ///
  /// 创建观看模式按钮叶子组件。
  FitButtonComponent();

  @override
  String get name => 'fitButton';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<MovaFit>(
      selector: (s) => s.fit,
      builder: (context, fit) {
        return MovaIconButton(
          icon: Icons.aspect_ratio_rounded,
          theme: theme,
          caption: api.options.strings.fitLabel(fit),
          onPressed: () => api.setFit(fit.next),
        );
      },
    );
  }
}

/// Forced-orientation toggle button; tap switches the device between forced
/// landscape and portrait via [MovaApi.setOrientation], independent of
/// fullscreen.
///
/// Renders nothing off mobile (`defaultTargetPlatform` not Android/iOS), where
/// forcing device orientation has no effect — mirroring how the pip button
/// hides where PiP is unsupported. Watches [MovaState.orientation] so its toggle
/// target follows the current forced state.
///
/// 强制方向切换按钮；点击经 [MovaApi.setOrientation] 在强制横屏与竖屏间切换，与
/// 全屏无关。
///
/// 非移动端（`defaultTargetPlatform` 不是 Android/iOS）不渲染任何内容——那里
/// 强制设备方向本就无效，与画中画按钮在不支持处隐藏一致。监听
/// [MovaState.orientation]，使切换目标跟随当前强制状态。
class OrientationButtonComponent extends MovaComp {
  /// Creates the orientation-button leaf component.
  ///
  /// 创建方向按钮叶子组件。
  OrientationButtonComponent();

  @override
  String get name => 'orientationButton';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (!isMobile) return const SizedBox.shrink();
    final theme = api.options.theme;
    return MovaSelect<MovaOrient>(
      selector: (s) => s.orientation,
      builder: (context, orientation) {
        return MovaIconButton(
          icon: Icons.screen_rotation_rounded,
          theme: theme,
          onPressed: () => api.setOrientation(orientation.toggled),
        );
      },
    );
  }
}

/// Fullscreen toggle button; icon flips between enter/exit fullscreen glyphs
/// based on [MovaState.fullscreen].
///
/// 全屏切换按钮；图标依据 [MovaState.fullscreen] 在进入/退出全屏两种图形间切换。
class FullscreenButtonComponent extends MovaComp {
  /// Creates the fullscreen-button leaf component.
  ///
  /// 创建全屏按钮叶子组件。
  FullscreenButtonComponent();

  @override
  String get name => 'fullscreenButton';

  @override
  MovaSlot get slot => MovaSlot.top;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<bool>(
      selector: (s) => s.fullscreen,
      builder: (context, fullscreen) {
        return MovaIconButton(
          icon: fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
          theme: theme,
          onPressed: () => api.setFullscreen(!fullscreen),
        );
      },
    );
  }
}

