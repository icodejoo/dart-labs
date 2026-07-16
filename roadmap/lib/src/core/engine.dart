/// 引擎：插件注册表、拓扑排序、错误边界。
///
/// 移植自 `src/core/engine.ts`。TS 版本的 `createEngine` 保留 `async` 签名只是
/// 为了兼容旧调用方（内部完全同步）；Dart 版本没有这个历史包袱，直接是同步函数。
library;

import 'game_specs/baccarat.dart';
import 'roads/index.dart';
import 'stream.dart';
import 'types.dart';

/// 引擎 compute 输出。
///
/// 出错插件不中断其他路，而是记入 [errors]。
class ComputeOutput {
  /// 各路的格子化布局输出（出错路缺席）。
  final Map<String, RoadLayout> layouts;

  /// 各路的 derive 数据（出错路缺席）。
  final Map<String, Object?> data;

  /// 各路的问路结果（出错路缺席）。
  final Map<String, PredictionForRoad> predictions;

  /// 插件错误 Map（id -> 错误）。出错的插件及其下游级联插件均记录在此，其他路照常。
  final Map<String, Object> errors;

  const ComputeOutput({
    required this.layouts,
    required this.data,
    required this.predictions,
    required this.errors,
  });
}

/// 引擎。
class Engine {
  /// 已加载的插件 Map（只读）。
  final Map<String, RoadPlugin> plugins;

  final GameSpec _spec;
  final List<String> _sorted;
  final List<String> _enabledIds;

  Engine._(this.plugins, this._spec, this._sorted, this._enabledIds);

  /// 上次 compute 的入参（按引用比较）与输出——store 每次 append 都产生新的
  /// results 列表，引用即版本号；UI 侧的无关重算（切换开关、重建面板）用同一份
  /// results+cfg 再次 compute 时直接命中，布局对象保持同一实例，下游的
  /// identity 缓存（RoadPanel 的指令列表/Picture 缓存）也因此不被击穿。
  List<RawResult>? _lastResults;
  LayoutConfig? _lastCfg;
  ComputeOutput? _lastOutput;

  /// 全量计算所有已启用插件的布局输出。
  ///
  /// [results] 是当前靴的全部局结果，[cfg] 是布局配置（cellSize/rows/theme）。
  /// 同一份 [results] 与 [cfg]（按引用比较）重复调用直接返回上次的输出。
  ComputeOutput compute(List<RawResult> results, LayoutConfig cfg) {
    if (identical(results, _lastResults) && identical(cfg, _lastCfg)) {
      return _lastOutput!;
    }
    final cache = <String, Object?>{};
    final errors = <String, Object>{};

    late final _EngineContext ctx;
    ctx = _EngineContext(
      results: results,
      spec: _spec,
      plugins: plugins,
      cache: cache,
      errors: errors,
    );

    // 按拓扑序预热缓存，出错则记录并跳过下游。
    for (final id in _sorted) {
      if (errors.containsKey(id)) continue;
      try {
        ctx.get<Object?>(id);
      } catch (err) {
        errors[id] = err;
      }
    }

    final layouts = <String, RoadLayout>{};
    final data = <String, Object?>{};
    final predictions = <String, PredictionForRoad>{};

    for (final id in _enabledIds) {
      if (errors.containsKey(id)) continue;
      final plugin = plugins[id]!;
      try {
        final d = ctx.get<Object?>(id);
        data[id] = d;
        final layout = plugin.layout(d, cfg, ctx);
        if (layout != null) layouts[id] = layout;
        final prediction = plugin.predict(ctx);
        if (prediction != null) predictions[id] = prediction;
      } catch (err) {
        // 检查是否因依赖出错导致的级联。
        final cascadeFrom = plugin.dependsOn.where(errors.containsKey).firstOrNull;
        errors[id] = cascadeFrom != null ? 'Cascaded from "$cascadeFrom": ${errors[cascadeFrom]}' : err;
      }
    }

    final output = ComputeOutput(layouts: layouts, data: data, predictions: predictions, errors: errors);
    _lastResults = results;
    _lastCfg = cfg;
    _lastOutput = output;
    return output;
  }
}

/// 创建引擎：按 [enabledIds] 从 [roadRegistry] 展开传递依赖、拓扑排序，返回
/// 可同步 compute 的 [Engine] 实例。
///
/// ```dart
/// final engine = createEngine(['beadPlate', 'bigRoad']);
/// final output = engine.compute(results, cfg);
///
/// // 使用自定义规格
/// final engine2 = createEngine(['beadPlate', 'bigRoad'], spec: dragonTigerSpec);
/// ```
Engine createEngine(List<String> enabledIds, {GameSpec? spec}) {
  final resolvedSpec = spec ?? baccaratSpec;

  // 从注册表加载启用的插件及其传递依赖（依赖入队前已校验，顶层 id 在这里校验）。
  final plugins = <String, RoadPlugin>{};
  final toLoad = [...enabledIds];
  while (toLoad.isNotEmpty) {
    final id = toLoad.removeLast();
    if (plugins.containsKey(id)) continue;
    final plugin = roadRegistry[id];
    if (plugin == null) throw StateError('Unknown road plugin: "$id"');
    plugins[id] = plugin;
    for (final dep in plugin.dependsOn) {
      if (!plugins.containsKey(dep)) {
        if (!roadRegistry.containsKey(dep)) {
          throw StateError('Unknown road plugin dependency: "$dep" (required by "$id")');
        }
        toLoad.add(dep);
      }
    }
  }

  final sorted = _topoSort(plugins);

  return Engine._(plugins, resolvedSpec, sorted, enabledIds);
}

/// 对已加载插件进行拓扑排序（Kahn 算法）。存在循环依赖时抛错。
List<String> _topoSort(Map<String, RoadPlugin> plugins) {
  final inDegree = <String, int>{};
  final dependents = <String, List<String>>{};

  for (final id in plugins.keys) {
    inDegree.putIfAbsent(id, () => 0);
    dependents.putIfAbsent(id, () => []);
  }

  for (final entry in plugins.entries) {
    for (final dep in entry.value.dependsOn) {
      if (!plugins.containsKey(dep)) continue;
      inDegree[entry.key] = (inDegree[entry.key] ?? 0) + 1;
      dependents[dep]!.add(entry.key);
    }
  }

  final queue = inDegree.entries.where((e) => e.value == 0).map((e) => e.key).toList();
  final result = <String>[];

  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    result.add(id);
    for (final dep in dependents[id] ?? const <String>[]) {
      final d = (inDegree[dep] ?? 0) - 1;
      inDegree[dep] = d;
      if (d == 0) queue.add(dep);
    }
  }

  if (result.length != plugins.length) {
    throw StateError('Circular dependency detected in road plugins');
  }
  return result;
}

class _EngineContext implements RoadContext {
  @override
  final List<RawResult> results;

  @override
  final GameSpec spec;

  final Map<String, RoadPlugin> plugins;
  final Map<String, Object?> cache;
  final Map<String, Object> errors;

  _EngineContext({
    required this.results,
    required this.spec,
    required this.plugins,
    required this.cache,
    required this.errors,
  });

  @override
  StreamDef stream(String id) => getStreamDef(spec, id);

  @override
  T get<T>(String pluginId) {
    if (errors.containsKey(pluginId)) {
      throw StateError('Plugin "$pluginId" is in error state (root cause: ${errors[pluginId]})');
    }
    if (!cache.containsKey(pluginId)) {
      final plugin = plugins[pluginId];
      if (plugin == null) throw StateError('Plugin "$pluginId" not loaded');
      cache[pluginId] = plugin.derive(this);
    }
    return cache[pluginId] as T;
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
