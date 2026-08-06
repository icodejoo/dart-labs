import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../scope/selector.dart';
import '../slots/component.dart';
import '../slots/slot.dart';

/// Buffering spinner overlay; shown only while [MovaState.buffering] is true.
///
/// New in this refactor plan — 0.1.0 never surfaced a visual buffering
/// indicator (buffering was only consumed internally to drive ABR
/// downgrades). Styling is a plain [CircularProgressIndicator], deliberately
/// simple since there is no 0.1.0 baseline to match.
///
/// 缓冲中转圈叠加层；仅当 [MovaState.buffering] 为真时显示。
///
/// 本次重构计划中新增——0.1.0 从未展示过可见的缓冲指示（缓冲仅内部用于驱动
/// ABR 降档）。样式为普通 [CircularProgressIndicator]，刻意保持简单，因为
/// 没有 0.1.0 基线可对齐。
class BufferingComponent extends MovaComp {
  /// Creates the buffering-overlay leaf component.
  ///
  /// 创建缓冲叠加层叶子组件。
  BufferingComponent();

  @override
  String get name => 'buffering';

  @override
  MovaSlot get slot => MovaSlot.center;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<bool>(
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

/// Playback-error overlay; shown whenever [MovaState.error] is non-null, with
/// the error's text and a retry button that calls [MovaApi.reload].
///
/// New in this refactor plan — 0.1.0 had no error-state UI at all. Layout
/// and copy are a reasonable, simple default, not a 0.1.0 port.
///
/// 播放错误叠加层；[MovaState.error] 非空时显示，含错误文案与调用
/// [MovaApi.reload] 的重试按钮。
///
/// 本次重构计划中新增——0.1.0 完全没有错误态 UI。布局与文案为合理的简单
/// 默认实现，并非移植自 0.1.0。
class ErrorComponent extends MovaComp {
  /// Creates the error-overlay leaf component.
  ///
  /// 创建错误叠加层叶子组件。
  ErrorComponent();

  @override
  String get name => 'error';

  @override
  MovaSlot get slot => MovaSlot.center;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    final theme = api.options.theme;
    return MovaSelect<Object?>(
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

/// Full-size tap-swallowing mask shown while [MovaState.locked] is true.
///
/// Only absorbs taps so gestures/buttons underneath don't receive them while
/// locked; when not locked it renders nothing. The unlock affordance itself
/// is a separate, always-on-top layer (see [MovaDefSkin.assemble]) so it
/// can never end up underneath this mask regardless of slot/stacking order.
///
/// [MovaState.locked] 为真时显示的全尺寸吞点击遮罩。
///
/// 只负责吞掉点击，使下层手势/按钮在锁定期间收不到事件；未锁定时不渲染任何
/// 内容。解锁入口本身是独立的、恒定处于最上层的一层（见
/// [MovaDefSkin.assemble]），因此无论槽位/层叠顺序如何，都不会被本遮罩盖住。
class LockMaskComponent extends MovaComp {
  /// Creates the lock-mask leaf component.
  ///
  /// 创建锁定遮罩叶子组件。
  LockMaskComponent();

  @override
  String get name => 'lockMask';

  @override
  MovaSlot get slot => MovaSlot.overlay;

  @override
  Widget build(BuildContext context, MovaApi api, List<Widget> children) {
    return MovaSelect<bool>(
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
