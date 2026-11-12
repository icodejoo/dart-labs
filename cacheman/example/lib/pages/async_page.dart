import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';

import '../main.dart';

/// Example-only asynchronous backend, deliberately kept out of the package.
/// 仅示例使用的异步内存后端，不进入包的实现。
class _MemoryAsync extends AsyncCacheman {
  /// Isolates the demo's large values. / 隔离示例的大值。
  _MemoryAsync() : super(options: const CachemanOptions(namespace: 'large'));

  /// Demonstration storage, not a disk backend. / 演示存储，并非磁盘后端。
  final _data = <String, String>{};

  @override
  Future<Object?> getRaw(CacheContext ctx, String storageKey) async =>
      _data[storageKey];

  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) async {
    _data[storageKey] = value;
  }

  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) async {
    _data.remove(storageKey);
  }

  @override
  Future<Iterable<String>> keysRaw(CacheContext ctx) async => _data.keys;
}

/// Example-only synchronous backend built with [Cacheman.custom]; no get_storage involved.
/// 仅示例使用、基于 [Cacheman.custom] 的同步后端，不涉及 get_storage。
class _MemorySync extends Cacheman {
  /// Isolates the demo's custom-backend values. / 隔离示例的自定义后端值。
  _MemorySync() : super.custom(options: const CachemanOptions(namespace: 'custom'));

  /// Demonstration storage; mutations update it before returning. / 演示存储，变更在返回前更新。
  final _data = <String, String>{};

  @override
  Object? getRaw(CacheContext ctx, String storageKey) => _data[storageKey];

  @override
  Future<void> setRaw(CacheContext ctx, String storageKey, String value) {
    _data[storageKey] = value;
    return Future<void>.value();
  }

  @override
  Future<void> removeRaw(CacheContext ctx, String storageKey) {
    _data.remove(storageKey);
    return Future<void>.value();
  }

  @override
  Iterable<String> keysRaw(CacheContext ctx) => _data.keys;

  @override
  Future<void> clearRaw(CacheContext ctx) {
    _data.clear();
    return Future<void>.value();
  }
}

/// Runs synchronous small-value and asynchronous large-value caches together.
/// 同时演示同步小值缓存与异步大值缓存。
class AsyncPage extends StatefulWidget {
  /// Creates the demo page. / 创建演示页面。
  const AsyncPage({super.key, required this.onChanged});

  /// Refreshes the global synchronous-cache count. / 刷新全局同步缓存计数。
  final VoidCallback onChanged;

  @override
  State<AsyncPage> createState() => _AsyncPageState();
}

/// Keeps the example's asynchronous cache local to this page. / 异步示例缓存仅在本页存活。
class _AsyncPageState extends State<AsyncPage> {
  /// Large-data semantic layer backed by a demo Map. / 演示 Map 支撑的大数据语义层。
  final _large = _MemoryAsync();

  /// Synchronous custom backend built with Cacheman.custom. / 用 Cacheman.custom 构建的同步自定义后端。
  final _custom = _MemorySync();

  /// Last run's visible result. / 最近一次运行的可见结果。
  Future<String>? _result;

  /// Uses identical logical keys across independent backends. / 独立后端使用相同逻辑键。
  static const _reportKey = 'layered_report';

  /// Exercises both APIs without adding a library backend/dependency.
  /// 不新增包内后端/依赖即可演示两套 API。
  Future<String> _run() async {
    await _large.ensureInitialized();
    await _custom.ensureInitialized();
    const rows = 1000;
    const ttl = 60000;
    cache.write(_reportKey, rows, ttl: ttl);
    await _large.write(
      _reportKey,
      List.generate(rows, (i) => {'row': i}),
      ttl: ttl,
    );
    final report = await _large.read<List<dynamic>>(_reportKey);
    final count = await _large.length();
    _custom.write(_reportKey, rows, ttl: ttl);
    widget.onChanged();
    return 'Small summary (sync): ${cache.read<int>(_reportKey)} rows\n'
        'Large report (async): ${report?.length} rows, $count key\n'
        'Custom sync backend: ${_custom.read<int>(_reportKey)} rows, '
        '${_custom.length} key';
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Layered storage', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text(
        'Keep small summaries in Cacheman and large reports in your '
        'AsyncCacheman subclass. Both can use the same logical key.',
      ),
      const SizedBox(height: 8),
      const Text(
        'This demo also runs a Cacheman.custom subclass (synchronous, in-memory). '
        'It uses in-memory Maps. Use LazyBox or file primitives '
        'in your app for on-demand disk reads without retaining large values.',
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => setState(() {
          _result = _run();
        }),
        child: const Text('Run both caches'),
      ),
      const SizedBox(height: 16),
      FutureBuilder<String>(
        future: _result,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text('Error: ${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return Text(snapshot.data ?? 'Run the demo to read both results.');
        },
      ),
    ],
  );
}
