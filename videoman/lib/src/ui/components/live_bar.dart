import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';

/// Composite component for the live-stream bottom control bar: the LIVE
/// badge, a spacer, then the back-to-edge button — matching 0.1.0's
/// `LiveControls._bottomBar()` row order.
///
/// Phase A only ports 0.1.0's equivalent functionality (badge + back-to-
/// edge); timeshift-specific components are added in Phase C.
///
/// 直播底部控制条组合组件：LIVE 角标、撑开间隔、回到边缘按钮，行序对齐
/// 0.1.0 的 `LiveControls._bottomBar()`。
///
/// 阶段 A 只移植 0.1.0 的等价功能（角标 + 回到边缘）；时移相关组件在阶段 C
/// 补充。
class LiveBarComponent extends VmComponent {
  /// Creates the live-bar composite with its 2 fixed children.
  ///
  /// 创建带 2 个固定子组件的直播底栏组合组件。
  LiveBarComponent();

  @override
  String get name => 'bottomBar';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  List<VmComponent> get children => [
        LiveBadgeComponent(),
        BackToEdgeComponent(),
      ];

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmGradientBar(
      top: false,
      theme: theme,
      child: Row(
        children: [
          const SizedBox(width: 8),
          children[0],
          const Spacer(),
          children[1],
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// The "LIVE" badge; a small filled pill using [VmTheme.accentColor] as
/// background and [VmStrings.live] as its text.
///
/// "LIVE" 角标；使用 [VmTheme.accentColor] 作为背景色、[VmStrings.live]
/// 作为文案的小胶囊。
class LiveBadgeComponent extends VmComponent {
  /// Creates the live-badge leaf component.
  ///
  /// 创建 LIVE 角标叶子组件。
  LiveBadgeComponent();

  @override
  String get name => 'liveBadge';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Color(theme.accentColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        strings.live,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}

/// Button that jumps a live stream back to the live edge by reloading the
/// current source, mirroring 0.1.0's "回到边缘" behaviour exactly.
///
/// 跳回直播边缘的按钮；通过重新加载当前源实现，与 0.1.0 的"回到边缘"行为
/// 完全一致。
class BackToEdgeComponent extends VmComponent {
  /// Creates the back-to-edge leaf component.
  ///
  /// 创建回到边缘叶子组件。
  BackToEdgeComponent();

  @override
  String get name => 'backToEdge';

  @override
  VmSlot get slot => VmSlot.bottom;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    final strings = api.options.strings;
    return VmIconButton(
      icon: Icons.sync_rounded,
      caption: strings.backToEdge,
      theme: theme,
      onPressed: api.reload,
    );
  }
}
