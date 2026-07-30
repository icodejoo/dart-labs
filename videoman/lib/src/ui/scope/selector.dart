import 'package:flutter/widgets.dart';

import '../../core/state/progress.dart';
import '../../core/state/state.dart';
import '../../core/state/ui_state.dart';
import 'scope.dart';

/// Rebuilds [builder] only when the field picked by [selector] out of the
/// current [VmState] changes.
///
/// 仅当从当前 [VmState] 中由 [selector] 取出的字段发生变化时才重建
/// [builder]。
class VmSelector<T> extends StatelessWidget {
  /// Creates a selector watching a field of [VmState].
  ///
  /// [selector] projects the full [VmState] down to the watched field.
  /// [builder] renders the widget for the current value of that field.
  ///
  /// 创建一个观察 [VmState] 某字段的选择器。
  ///
  /// [selector] 将完整 [VmState] 投影为被观察字段。[builder] 依据该字段
  /// 当前值渲染组件。
  const VmSelector({required this.selector, required this.builder, super.key});

  /// Projects the full state down to the field this widget watches.
  ///
  /// 将完整状态投影为该组件所观察的字段。
  final T Function(VmState state) selector;

  /// Renders the widget for the current value of the watched field.
  ///
  /// 依据被观察字段的当前值渲染组件。
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    final api = VmScope.of(context);
    return StreamBuilder<T>(
      stream: api.states.map(selector).distinct(),
      initialData: selector(api.state),
      builder: (context, snapshot) => builder(context, snapshot.data as T),
    );
  }
}

/// Rebuilds [builder] only when the field picked by [selector] out of the
/// current [VmProgress] changes.
///
/// 仅当从当前 [VmProgress] 中由 [selector] 取出的字段发生变化时才重建
/// [builder]。
class VmProgressSelector<T> extends StatelessWidget {
  /// Creates a selector watching a field of [VmProgress].
  ///
  /// [selector] projects the full [VmProgress] down to the watched field.
  /// [builder] renders the widget for the current value of that field.
  ///
  /// 创建一个观察 [VmProgress] 某字段的选择器。
  ///
  /// [selector] 将完整 [VmProgress] 投影为被观察字段。[builder] 依据该
  /// 字段当前值渲染组件。
  const VmProgressSelector({required this.selector, required this.builder, super.key});

  /// Projects the full progress snapshot down to the field this widget
  /// watches.
  ///
  /// 将完整进度快照投影为该组件所观察的字段。
  final T Function(VmProgress progress) selector;

  /// Renders the widget for the current value of the watched field, or
  /// `null` before the first tick arrives (progress has no synchronous
  /// snapshot to seed with).
  ///
  /// 依据被观察字段的当前值渲染组件；在首个 tick 到达前为 `null`（进度
  /// 无同步快照可用作初值）。
  final Widget Function(BuildContext context, T? value) builder;

  @override
  Widget build(BuildContext context) {
    final api = VmScope.of(context);
    return StreamBuilder<T>(
      stream: api.progress.map(selector).distinct(),
      builder: (context, snapshot) => builder(context, snapshot.data),
    );
  }
}

/// Rebuilds [builder] only when the field picked by [selector] out of the
/// current [VmUiState] changes.
///
/// 仅当从当前 [VmUiState] 中由 [selector] 取出的字段发生变化时才重建
/// [builder]。
class VmUiSelector<T> extends StatelessWidget {
  /// Creates a selector watching a field of [VmUiState].
  ///
  /// [selector] projects the full [VmUiState] down to the watched field.
  /// [builder] renders the widget for the current value of that field.
  ///
  /// 创建一个观察 [VmUiState] 某字段的选择器。
  ///
  /// [selector] 将完整 [VmUiState] 投影为被观察字段。[builder] 依据该
  /// 字段当前值渲染组件。
  const VmUiSelector({required this.selector, required this.builder, super.key});

  /// Projects the full UI state down to the field this widget watches.
  ///
  /// 将完整 UI 状态投影为该组件所观察的字段。
  final T Function(VmUiState state) selector;

  /// Renders the widget for the current value of the watched field.
  ///
  /// 依据被观察字段的当前值渲染组件。
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    final api = VmScope.of(context);
    return StreamBuilder<T>(
      stream: api.uiStates.map(selector).distinct(),
      initialData: selector(api.uiState),
      builder: (context, snapshot) => builder(context, snapshot.data as T),
    );
  }
}
