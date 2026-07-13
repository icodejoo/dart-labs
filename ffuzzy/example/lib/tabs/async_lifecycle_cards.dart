// The 3 async lifecycle methods (build / mutate / dispose on a background
// isolate) don't fit the shared-query pattern — each gets its own small,
// self-contained interactive card.
//
// 3 个异步生命周期方法（在后台 isolate 上构建/变更/释放）不适合共享查询框的
// 模式，各自用一张独立的小型交互卡片演示。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../widgets/demo_card.dart';

class AsyncBuildCard extends StatefulWidget {
  const AsyncBuildCard({super.key, required this.id});
  final String id;
  @override
  State<AsyncBuildCard> createState() => _AsyncBuildCardState();
}

class _AsyncBuildCardState extends State<AsyncBuildCard> {
  FuzzyCorpus<String>? _corpus;
  bool _building = false;

  @override
  void dispose() {
    _corpus?.dispose();
    super.dispose();
  }

  Future<void> _build() async {
    setState(() => _building = true);
    final sw = Stopwatch()..start();
    final c = await FuzzyCorpus.asyncBuild(
      List.generate(3000, (i) => 'item_$i'),
      stringOf: (s) => s,
    );
    sw.stop();
    _corpus?.dispose();
    if (!mounted) return;
    setState(() {
      _corpus = c;
      _building = false;
      _elapsedMs = sw.elapsedMilliseconds;
    });
  }

  int? _elapsedMs;

  @override
  Widget build(BuildContext context) {
    return DemoCard(
      id: widget.id,
      title: 'asyncBuild',
      code: 'await FuzzyCorpus.asyncBuild(\n  3000 items, stringOf: ...)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: _building ? null : _build,
            child: Text(_building ? 'Building…' : 'Build 3000-item corpus'),
          ),
          if (_corpus != null)
            Text('length: ${_corpus!.length}  (${_elapsedMs}ms)',
                style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class AsyncAddAllCard extends StatefulWidget {
  const AsyncAddAllCard({super.key, required this.id});
  final String id;
  @override
  State<AsyncAddAllCard> createState() => _AsyncAddAllCardState();
}

class _AsyncAddAllCardState extends State<AsyncAddAllCard> {
  late final FuzzyCorpus<String> _corpus =
      FuzzyCorpus.strings(['alpha', 'beta', 'gamma']);
  bool _busy = false;

  @override
  void dispose() {
    _corpus.dispose();
    super.dispose();
  }

  Future<void> _addAll() async {
    setState(() => _busy = true);
    await _corpus.asyncAddAll(['delta', 'epsilon']);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return DemoCard(
      id: widget.id,
      title: 'asyncAddAll',
      code: "await corpus.asyncAddAll(['delta', 'epsilon'])",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: _busy ? null : _addAll,
            child: Text(_busy ? 'Adding…' : 'asyncAddAll'),
          ),
          Text('length: ${_corpus.length}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class AsyncDisposeCard extends StatefulWidget {
  const AsyncDisposeCard({super.key, required this.id});
  final String id;
  @override
  State<AsyncDisposeCard> createState() => _AsyncDisposeCardState();
}

class _AsyncDisposeCardState extends State<AsyncDisposeCard> {
  final _corpus = FuzzyCorpus.strings(['x', 'y', 'z']);
  bool _disposed = false;

  @override
  void dispose() {
    if (!_disposed) _corpus.dispose();
    super.dispose();
  }

  Future<void> _disposeCorpus() async {
    await _corpus.asyncDispose();
    if (!mounted) return;
    setState(() => _disposed = true);
  }

  @override
  Widget build(BuildContext context) {
    return DemoCard(
      id: widget.id,
      title: 'asyncDispose',
      code: 'await corpus.asyncDispose()',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: _disposed ? null : _disposeCorpus,
            child: Text(_disposed ? 'Disposed' : 'asyncDispose'),
          ),
          if (_disposed)
            const Text('corpus released; further use throws StateError',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
