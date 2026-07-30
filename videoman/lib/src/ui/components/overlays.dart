import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Buffering spinner overlay; shown only while [VmState.buffering] is true.
///
/// New in this refactor plan — 0.1.0 never surfaced a visual buffering
/// indicator (buffering was only consumed internally to drive ABR
/// downgrades). Styling is a plain [CircularProgressIndicator], deliberately
/// simple since there is no 0.1.0 baseline to match.
///
/// 缓冲中转圈叠加层；仅当 [VmState.buffering] 为真时显示。
///
/// 本次重构计划中新增——0.1.0 从未展示过可见的缓冲指示（缓冲仅内部用于驱动
/// ABR 降档）。样式为普通 [CircularProgressIndicator]，刻意保持简单，因为
/// 没有 0.1.0 基线可对齐。
class BufferingComponent extends VmComponent {
  /// Creates the buffering-overlay leaf component.
  ///
  /// 创建缓冲叠加层叶子组件。
  BufferingComponent();

  @override
  String get name => 'buffering';

  @override
  VmSlot get slot => VmSlot.center;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<bool>(
      selector: (s) => s.buffering,
      builder: (context, buffering) {
        if (!buffering) return const SizedBox.shrink();
        return Center(
          child: CircularProgressIndicator(color: Color(theme.accentColor)),
        );
      },
    );
  }
}

/// Playback-error overlay; shown whenever [VmState.error] is non-null, with
/// the error's text and a retry button that calls [VmApi.reload].
///
/// New in this refactor plan — 0.1.0 had no error-state UI at all. Layout
/// and copy are a reasonable, simple default, not a 0.1.0 port.
///
/// 播放错误叠加层；[VmState.error] 非空时显示，含错误文案与调用
/// [VmApi.reload] 的重试按钮。
///
/// 本次重构计划中新增——0.1.0 完全没有错误态 UI。布局与文案为合理的简单
/// 默认实现，并非移植自 0.1.0。
class ErrorComponent extends VmComponent {
  /// Creates the error-overlay leaf component.
  ///
  /// 创建错误叠加层叶子组件。
  ErrorComponent();

  @override
  String get name => 'error';

  @override
  VmSlot get slot => VmSlot.center;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    final theme = api.options.theme;
    return VmSelector<Object?>(
      selector: (s) => s.error,
      builder: (context, error) {
        if (error == null) return const SizedBox.shrink();
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(theme.textColor), fontSize: theme.timeFontSize),
              ),
              const SizedBox(height: 8),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: Color(theme.iconColor)),
                onPressed: () => api.reload(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Full-size tap-swallowing mask shown while [VmState.locked] is true.
///
/// SCOPE NOTE: this deliberately does not reproduce 0.1.0's richer lock flow
/// (tap-while-locked flashing a temporary unlock button that auto-hides) —
/// that UX is deferred to later polish. This component only absorbs taps so
/// gestures/buttons underneath do not receive them while locked; when not
/// locked it renders nothing.
///
/// [VmState.locked] 为真时显示的全尺寸吞点击遮罩。
///
/// 范围说明：本组件刻意不复刻 0.1.0 更丰富的锁定流程（锁定态下点击会短暂
/// 闪现解锁按钮、随后自动隐藏）——该体验留待后续打磨。本组件仅在锁定期间
/// 吞掉点击，使下层手势/按钮收不到事件；未锁定时不渲染任何内容。
class LockMaskComponent extends VmComponent {
  /// Creates the lock-mask leaf component.
  ///
  /// 创建锁定遮罩叶子组件。
  LockMaskComponent();

  @override
  String get name => 'lockMask';

  @override
  VmSlot get slot => VmSlot.overlay;

  @override
  Widget build(BuildContext context, VmApi api, List<Widget> children) {
    return VmSelector<bool>(
      selector: (s) => s.locked,
      builder: (context, locked) {
        if (!locked) return const SizedBox.shrink();
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
