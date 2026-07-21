/// Engine: plugin registry, topological sort, error boundary.
///
/// Ported from `src/core/engine.ts`. The TS version of `createEngine` keeps `async` signature only to
/// be compatible with old callers (internally completely synchronous); Dart version has no such historical baggage, directly synchronous function.
library;

import 'game_specs/baccarat.dart';
import 'roads/index.dart';
import 'stream.dart';
import 'types.dart';

/// Engine compute output.
///
/// Errored plugins do not interrupt other roads, but are recorded in [errors].
class ComputeOutput {
  /// Gridded layout output for each road (errored roads absent).
  final Map<String, RoadLayout> layouts;

  /// Derive data for each road (errored roads absent).
  final Map<String, Object?> data;

  /// Prediction results for each road (errored roads absent).
  final Map<String, PredictionForRoad> predictions;

  /// Plugin error map (id -> error). Errored plugins and their downstream cascading plugins are recorded here, other roads proceed normally.
  final Map<String, Object> errors;

  const ComputeOutput({
    required this.layouts,
    required this.data,
    required this.predictions,
    required this.errors,
  });
}

/// Engine.
class Engine {
  /// Loaded plugin map (read-only).
  final Map<String, RoadPlugin> plugins;

  final GameSpec _spec;
  final List<String> _sorted;
  final List<String> _enabledIds;

  Engine._(this.plugins, this._spec, this._sorted, this._enabledIds);

  /// Last compute input parameters (compared by reference) and output -- store produces a new
  /// results list with each append, reference is version number; unrelated recomputation on UI side (toggle switches, rebuild panel)
  /// directly hits when recomputing the same results+cfg, layout objects remain the same instance, downstream
  /// identity cache (RoadPanel instruction list / Picture cache) is therefore not pierced.
  List<RawResult>? _lastResults;
  LayoutConfig? _lastCfg;
  ComputeOutput? _lastOutput;

  /// Fully compute the layout output of all enabled plugins.
  ///
  /// [results] is all round results of the current shoe, [cfg] is layout configuration (cellSize/rows/theme).
  /// Repeated calls with the same [results] and [cfg] (compared by reference) directly return the previous output.
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

    // Preheat cache in topological order, record and skip downstream if error.
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
        // Check if this is a cascade error caused by a dependency error.
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

/// Create engine: expand transitive dependencies from [roadRegistry] according to [enabledIds], topologically sort, return
/// a [Engine] instance that can synchronously compute.
///
/// ```dart
/// final engine = createEngine(['beadPlate', 'bigRoad']);
/// final output = engine.compute(results, cfg);
///
/// // Use custom spec
/// final engine2 = createEngine(['beadPlate', 'bigRoad'], spec: dragonTigerSpec);
/// ```
Engine createEngine(List<String> enabledIds, {GameSpec? spec}) {
  final resolvedSpec = spec ?? baccaratSpec;

  // Load enabled plugins and their transitive dependencies from the registry (dependencies are validated before being enqueued, top-level id is validated here).
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

/// Topologically sort loaded plugins (Kahn's algorithm). Throw error if circular dependency exists.
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
