import 'package:flutter/widgets.dart';

import '../../core/state/progress.dart';
import '../../core/state/state.dart';
import '../../core/state/ui_state.dart';
import 'scope.dart';

/// Rebuilds [builder] only when the field picked by [selector] out of the
/// current [MovaState] changes.
///
/// 仅当从当前 [MovaState] 中由 [selector] 取出的字段发生变化时才重建
/// [builder]。
class MovaSelect<T> extends StatelessWidget {
  /// Creates a selector watching a field of [MovaState].
  ///
  /// [selector] projects the full [MovaState] down to the watched field.
  /// [builder] renders the widget for the current value of that field.
  ///
  /// 创建一个观察 [MovaState] 某字段的选择器。
  ///
  /// [selector] 将完整 [MovaState] 投影为被观察字段。[builder] 依据该字段
  /// 当前值渲染组件。
  const MovaSelect({required this.selector, required this.builder, super.key});

  /// Projects the full state down to the field this widget watches.
  ///
  /// 将完整状态投影为该组件所观察的字段。
  final T Function(MovaState state) selector;

  /// Renders the widget for the current value of the watched field.
  ///
  /// 依据被观察字段的当前值渲染组件。
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    final api = MovaScope.of(context);
    return StreamBuilder<T>(
      stream: api.states.map(selector).distinct(),
      initialData: selector(api.state),
      builder: (context, snapshot) => builder(context, snapshot.data as T),
    );
  }
}

/// Rebuilds [builder] only when the field picked by [selector] out of the
/// current [MovaProg] changes.
///
/// 仅当从当前 [MovaProg] 中由 [selector] 取出的字段发生变化时才重建
/// [builder]。
class MovaProgSelect<T> extends StatelessWidget {
  /// Creates a selector watching a field of [MovaProg].
  ///
  /// [selector] projects the full [MovaProg] down to the watched field.
  /// [builder] renders the widget for the current value of that field.
  ///
  /// 创建一个观察 [MovaProg] 某字段的选择器。
  ///
  /// [selector] 将完整 [MovaProg] 投影为被观察字段。[builder] 依据该
  /// 字段当前值渲染组件。
  const MovaProgSelect({required this.selector, required this.builder, super.key});

  /// Projects the full progress snapshot down to the field this widget
  /// watches.
  ///
  /// 将完整进度快照投影为该组件所观察的字段。
  final T Function(MovaProg progress) selector;

  /// Renders the widget for the current value of the watched field, or
  /// `null` before the first tick arrives (progress has no synchronous
  /// snapshot to seed with).
  ///
  /// 依据被观察字段的当前值渲染组件；在首个 tick 到达前为 `null`（进度
  /// 无同步快照可用作初值）。
  final Widget Function(BuildContext context, T? value) builder;

  @override
  Widget build(BuildContext context) {
    final api = MovaScope.of(context);
    return StreamBuilder<T>(
      stream: api.progress.map(selector).distinct(),
      builder: (context, snapshot) => builder(context, snapshot.data),
    );
  }
}

/// Rebuilds [builder] only when the field picked by [selector] out of the
/// current [MovaUiState] changes.
///
/// 仅当从当前 [MovaUiState] 中由 [selector] 取出的字段发生变化时才重建
/// [builder]。
class MovaUiSelect<T> extends StatelessWidget {
  /// Creates a selector watching a field of [MovaUiState].
  ///
  /// [selector] projects the full [MovaUiState] down to the watched field.
  /// [builder] renders the widget for the current value of that field.
  ///
  /// 创建一个观察 [MovaUiState] 某字段的选择器。
  ///
  /// [selector] 将完整 [MovaUiState] 投影为被观察字段。[builder] 依据该
  /// 字段当前值渲染组件。
  const MovaUiSelect({required this.selector, required this.builder, super.key});

  /// Projects the full UI state down to the field this widget watches.
  ///
  /// 将完整 UI 状态投影为该组件所观察的字段。
  final T Function(MovaUiState state) selector;

  /// Renders the widget for the current value of the watched field.
  ///
  /// 依据被观察字段的当前值渲染组件。
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) {
    final api = MovaScope.of(context);
    return StreamBuilder<T>(
      stream: api.uiStates.map(selector).distinct(),
      initialData: selector(api.uiState),
      builder: (context, snapshot) => builder(context, snapshot.data as T),
    );
  }
}
