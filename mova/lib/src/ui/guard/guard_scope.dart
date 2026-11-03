import 'package:flutter/widgets.dart';

import '../../core/api.dart';

/// 标记子树的 [api] 已由 MovaAutoPause 接管可见性与后台（包内）。
class MovaGuardScope extends InheritedWidget {
  /// 为 [child] 标记守卫接管的 [api]。示例：`MovaGuardScope(api: api, child: child)`。
  const MovaGuardScope({super.key, required this.api, required super.child});

  /// 当前守卫接管的播放能力面。
  final MovaApi api;

  /// 仅在接管对象改变时通知子树。
  @override
  bool updateShouldNotify(MovaGuardScope oldWidget) => !identical(oldWidget.api, api);
}

/// 返回 [context] 的祖先守卫是否接管同一 [api]，不建立构建依赖。
/// 示例：`if (movaGuardedBy(context, api)) return;`。
bool movaGuardedBy(BuildContext context, MovaApi api) {
  final scope = context.getInheritedWidgetOfExactType<MovaGuardScope>();
  return scope != null && identical(scope.api, api);
}
