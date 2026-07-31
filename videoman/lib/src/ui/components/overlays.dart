import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';
import 'common.dart';

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
/// [VmState.locked] 为真时显示的全尺寸吞点击遮罩，并叠加一个解锁按钮。
///
/// Every other component is hidden while locked (see [VmDefaultSkin.assemble]),
/// so this is the *only* interactive element left on screen — it renders its
/// own unlock button rather than relying on `LockButtonComponent` in the
/// (hidden) top bar, and being in [VmSlot.overlay] — the top-most layer —
/// guarantees the button is never covered by the opaque tap-absorbing mask
/// underneath it.
///
/// [VmState.locked] 为真时显示的全尺寸吞点击遮罩，并叠加解锁按钮。
///
/// 锁定期间其余组件全部隐藏（见 [VmDefaultSkin.assemble]），因此这是屏幕上
/// **唯一**可交互的元素——它自带解锁按钮，而不依赖（已隐藏的）顶栏
/// `LockButtonComponent`；且身处 [VmSlot.overlay]（最上层），保证按钮绝不会
/// 被下方吞点击的不透明遮罩盖住。
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
    final theme = api.options.theme;
    return VmSelector<bool>(
      selector: (s) => s.locked,
      builder: (context, locked) {
        if (!locked) return const SizedBox.shrink();
        return Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const SizedBox.expand(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: VmIconButton(
                  icon: Icons.lock_rounded,
                  theme: theme,
                  onPressed: () => api.setLocked(false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
