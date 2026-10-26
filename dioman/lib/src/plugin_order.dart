import 'dioman_plugin.dart';

/// 插件顺序声明：描述一个插件与其它插件之间的先后约束与必需依赖。
///
/// 约束只在对方也被安装时才生效；指向未安装插件的 [before]/[after] 会被忽略
/// （即"可选依赖"）。一对插件的约束只需在任意一侧声明一次。
///
/// 通过覆写 [DiomanPlugin.ordering] 提供：
///
/// ```dart
/// class TimingPlugin extends DiomanPlugin {
///   @override
///   String get name => 'timing';
///
///   @override
///   DiomanPluginOrder get ordering => DiomanPluginOrder(
///         after: {DiomanKey.pluginName},   // 必须排在 key 之后
///         before: {DiomanCache.pluginName}, // 必须排在 cache 之前
///       );
/// }
/// ```
class DiomanPluginOrder {
  /// 创建顺序声明，三个集合默认都为空。
  ///
  /// - [before]：本插件必须排在这些名字的插件之前。
  /// - [after]：本插件必须排在这些名字的插件之后。
  /// - [requires]：这些名字的插件必须同时被安装（只要求存在，不隐含顺序；
  ///   需要顺序请同时写入 [before]/[after]）。
  const DiomanPluginOrder({
    this.before = const {},
    this.after = const {},
    this.requires = const {},
  });

  /// 无任何约束的空声明，[DiomanPlugin.ordering] 的默认值。
  static const none = DiomanPluginOrder();

  /// 本插件必须排在其之前的插件名；未安装的名字被忽略。
  final Set<String> before;

  /// 本插件必须排在其之后的插件名；未安装的名字被忽略。
  final Set<String> after;

  /// 必须同时安装的插件名；缺失时报 [DiomanPluginOrderIssue.missingDependency]。
  final Set<String> requires;
}

/// [DiomanPluginOrderException] 的问题类别。
enum DiomanPluginOrderIssue {
  /// 两个插件的 [DiomanPlugin.name] 相同。
  duplicateName,

  /// 顺序约束形成环（含自指）。
  cycle,

  /// [DiomanPluginOrder.requires] 指向的插件没有安装。
  missingDependency,

  /// 给定的顺序违反了某条 before/after 约束。
  misordered,
}

/// 插件顺序校验失败时抛出，消息和 [plugins] 都带上涉及的插件名。
///
/// [plugins] 的含义随 [issue] 而定：
/// - duplicateName：重复的那个名字（一个元素）。
/// - cycle：环上的插件名，按约束方向（前者须在后者之前）排列。
/// - missingDependency：`[依赖方, 缺失的插件]`。
/// - misordered：`[应在前的插件, 应在后的插件]`。
class DiomanPluginOrderException implements Exception {
  /// 创建异常；一般由 `Dioman.sort` / `Dioman.validate` / 安装与动态插入抛出，无需手动构造。
  const DiomanPluginOrderException(this.issue, this.plugins, this.message);

  /// 问题类别。
  final DiomanPluginOrderIssue issue;

  /// 涉及的插件名，含义见类注释。
  final List<String> plugins;

  /// 人类可读的说明。
  final String message;

  @override
  String toString() => 'DiomanPluginOrderException(${issue.name}): $message';
}

/// 约束图：`edges[u]` 是必须排在 u 之后的节点下标集合。
typedef _Graph = List<Set<int>>;

/// 重复名检查；有重复则抛 [DiomanPluginOrderException]。
void _checkDuplicates(List<DiomanPlugin> plugins) {
  final seen = <String>{};
  for (final p in plugins) {
    if (!seen.add(p.name)) {
      throw DiomanPluginOrderException(
        DiomanPluginOrderIssue.duplicateName,
        [p.name],
        "duplicate plugin name '${p.name}'; each plugin name must be unique "
        '(two instances would also share the same extra state keys).',
      );
    }
  }
}

/// 必需依赖检查；缺失则抛 [DiomanPluginOrderException]。
void _checkRequires(List<DiomanPlugin> plugins) {
  final names = {for (final p in plugins) p.name};
  for (final p in plugins) {
    for (final r in p.ordering.requires) {
      if (!names.contains(r)) {
        throw DiomanPluginOrderException(
          DiomanPluginOrderIssue.missingDependency,
          [p.name, r],
          "plugin '${p.name}' requires '$r', which is not installed.",
        );
      }
    }
  }
}

/// 把全部 before/after 声明展开成约束图（只保留双方都存在的约束）。
_Graph _buildGraph(List<DiomanPlugin> plugins) {
  final index = {for (var i = 0; i < plugins.length; i++) plugins[i].name: i};
  final edges = List.generate(plugins.length, (_) => <int>{});
  for (var i = 0; i < plugins.length; i++) {
    final o = plugins[i].ordering;
    for (final n in o.before) {
      final j = index[n];
      if (j != null) edges[i].add(j);
    }
    for (final n in o.after) {
      final j = index[n];
      if (j != null) edges[j].add(i);
    }
  }
  return edges;
}

/// 稳定拓扑排序（深度优先、按输入顺序）：依次处理每个插件，放置它之前先
/// 放好它尚未放置的前驱（前驱之间也按输入顺序）。因此无约束的插件保持输入
/// 顺序，被需要的插件只会被"提前"到刚好满足约束的位置。
///
/// 返回排好的下标；有环时抛 [DiomanPluginOrderException]。
List<int> _sortOrThrow(List<DiomanPlugin> plugins) {
  final edges = _buildGraph(plugins);
  final n = plugins.length;
  // 反向边：preds[v] 是必须排在 v 之前的节点（升序，保证稳定）。
  final preds = List.generate(n, (_) => <int>[]);
  for (var u = 0; u < n; u++) {
    for (final v in edges[u]) {
      preds[v].add(u);
    }
  }
  for (final p in preds) {
    p.sort();
  }

  final done = List.filled(n, false);
  final onStack = <int>[];
  final result = <int>[];

  void visit(int v) {
    if (done[v]) return;
    final at = onStack.indexOf(v);
    if (at >= 0) {
      // 栈沿"前驱"方向增长；环部分反转后即约束方向（前者须在后者之前）。
      final cycle = [
        for (final i in onStack.sublist(at).reversed) plugins[i].name,
      ];
      throw DiomanPluginOrderException(
        DiomanPluginOrderIssue.cycle,
        cycle,
        'plugin order constraints form a cycle: '
        "${[...cycle, cycle.first].map((x) => "'$x'").join(' -> ')}.",
      );
    }
    onStack.add(v);
    for (final u in preds[v]) {
      visit(u);
    }
    onStack.removeLast();
    done[v] = true;
    result.add(v);
  }

  for (var i = 0; i < n; i++) {
    visit(i);
  }
  return result;
}

/// 对 [plugins] 做稳定拓扑排序并返回新列表，不修改入参。
///
/// 无约束的插件保持输入顺序；有约束时按输入顺序处理，并把被需要的前驱提前到
/// 刚好满足约束的位置。依次校验重复名、缺失依赖、环，失败抛
/// [DiomanPluginOrderException]。
///
/// 参数：[plugins] 待排序的插件。返回：满足全部约束的新顺序。
///
/// ```dart
/// final ordered = sortPlugins([logPlugin, keyPlugin, cachePlugin]);
/// ```
List<DiomanPlugin> sortPlugins(Iterable<DiomanPlugin> plugins) {
  final list = plugins.toList();
  _checkDuplicates(list);
  _checkRequires(list);
  return [for (final i in _sortOrThrow(list)) list[i]];
}

/// 校验 [ordered]（按链顺序给出）：无重复名、依赖齐全、无环，且每条
/// before/after 约束都被满足。失败抛 [DiomanPluginOrderException]。
///
/// 参数：[ordered] 按实际执行顺序排列的插件。无返回值。
///
/// ```dart
/// validatePluginOrder(handle.plugins); // 通过即无异常
/// ```
void validatePluginOrder(List<DiomanPlugin> ordered) {
  _checkDuplicates(ordered);
  _checkRequires(ordered);
  _sortOrThrow(ordered); // 先排除环：有环时任何顺序都违规，错误应指向环。
  final edges = _buildGraph(ordered);
  for (var u = 0; u < ordered.length; u++) {
    for (final v in edges[u]) {
      if (v < u) {
        throw DiomanPluginOrderException(
          DiomanPluginOrderIssue.misordered,
          [ordered[u].name, ordered[v].name],
          "plugin '${ordered[u].name}' must come before '${ordered[v].name}', "
          "but is placed after it.",
        );
      }
    }
  }
}

/// 校验"若移除 [removed] 后其余插件的必需依赖仍然齐全"；缺失则抛
/// [DiomanPluginOrderException]。供 [DiomanHandle.remove] 使用。
void checkRemovable(List<DiomanPlugin> plugins, DiomanPlugin removed) {
  for (final p in plugins) {
    if (identical(p, removed)) continue;
    if (p.ordering.requires.contains(removed.name)) {
      throw DiomanPluginOrderException(
        DiomanPluginOrderIssue.missingDependency,
        [p.name, removed.name],
        "cannot remove '${removed.name}': plugin '${p.name}' requires it.",
      );
    }
  }
}
