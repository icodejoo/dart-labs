// The 9 mutation methods each get a small self-contained card: its own
// isolated corpus + a button that triggers the mutation, so cards never
// interfere with each other.
//
// 9 个增删改方法各自一张独立小卡片：自带独立 corpus 实例 + 一个触发变更的
// 按钮，卡片之间互不干扰。
import 'package:flutter/material.dart';
import 'package:ffuzzy/ffuzzy.dart';

import '../widgets/demo_card.dart';

class AddCard extends StatefulWidget {
  const AddCard({super.key, required this.id});
  final String id;
  @override
  State<AddCard> createState() => _AddCardState();
}

class _AddCardState extends State<AddCard> {
  final _corpus = FuzzyCorpus.strings(['a', 'b', 'c']);
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'add',
        code: "corpus.add('d')",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _corpus.add('d')),
              child: const Text("add('d')"),
            ),
            Text('length: ${_corpus.length}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class AddAllCard extends StatefulWidget {
  const AddAllCard({super.key, required this.id});
  final String id;
  @override
  State<AddAllCard> createState() => _AddAllCardState();
}

class _AddAllCardState extends State<AddAllCard> {
  final _corpus = FuzzyCorpus.strings(const <String>[]);
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'addAll',
        code: "corpus.addAll(['x', 'y'])",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _corpus.addAll(['x', 'y'])),
              child: const Text("addAll(['x','y'])"),
            ),
            Text('length: ${_corpus.length}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class AddKeyCard extends StatefulWidget {
  const AddKeyCard({super.key, required this.id});
  final String id;
  @override
  State<AddKeyCard> createState() => _AddKeyCardState();
}

class _AddKeyCardState extends State<AddKeyCard> {
  final _corpus = FuzzyCorpus.strings(const []);
  bool _keyed = false;
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }

  void _addKey() {
    _corpus.addKey('中文搜索引擎', [
      FuzzyKey.kind('zhongwen', FuzzyKeyKind.pinyin),
    ]);
    setState(() => _keyed = true);
  }

  @override
  Widget build(BuildContext context) {
    final matched = _keyed ? _corpus.fuzzy('zhongwen') : const <FuzzyHit<String>>[];
    return DemoCard(
      id: widget.id,
      title: 'addKey',
      code: "corpus.addKey('中文搜索引擎',\n  [FuzzyKey.kind('zhongwen', pinyin)])",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ElevatedButton(
            onPressed: _keyed ? null : _addKey,
            child: Text(_keyed ? 'added' : 'addKey (pinyin)'),
          ),
          if (_keyed)
            Text(
              matched.isNotEmpty
                  ? "fuzzy('zhongwen') → matched via ${matched.first.matchedKind.name}"
                  : 'no match',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key, required this.id});
  final String id;
  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  final _corpus = FuzzyCorpus.strings(['alpha', 'beta', 'gamma']);
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'update',
        code: "corpus.update(0, 'ALPHA')",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () => setState(() => _corpus.update(0, 'ALPHA')),
              child: const Text('update(0, ALPHA)'),
            ),
            Text("exact('ALPHA'): ${_corpus.exact('ALPHA').isNotEmpty}",
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class RemoveAtCard extends StatefulWidget {
  const RemoveAtCard({super.key, required this.id});
  final String id;
  @override
  State<RemoveAtCard> createState() => _RemoveAtCardState();
}

class _RemoveAtCardState extends State<RemoveAtCard> {
  final _corpus = FuzzyCorpus.strings(['a', 'b', 'c']);
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'removeAt',
        code: 'corpus.removeAt(0)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _corpus.length == 0 ? null : () => setState(() => _corpus.removeAt(0)),
              child: const Text('removeAt(0)'),
            ),
            Text('length: ${_corpus.length}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class RemoveWhereCard extends StatefulWidget {
  const RemoveWhereCard({super.key, required this.id});
  final String id;
  @override
  State<RemoveWhereCard> createState() => _RemoveWhereCardState();
}

class _RemoveWhereCardState extends State<RemoveWhereCard> {
  final _corpus = FuzzyCorpus.strings(['a1', 'a2', 'b1']);
  int? _removed;
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'removeWhere',
        code: "corpus.removeWhere(\n  (s) => s.startsWith('a'))",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: () => setState(
                  () => _removed = _corpus.removeWhere((s) => s.startsWith('a'))),
              child: const Text("removeWhere(startsWith 'a')"),
            ),
            Text('removed: ${_removed ?? '-'}, length: ${_corpus.length}',
                style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class RefreshCard extends StatefulWidget {
  const RefreshCard({super.key, required this.id});
  final String id;
  @override
  State<RefreshCard> createState() => _RefreshCardState();
}

class _RefreshCardState extends State<RefreshCard> {
  var _current = const ['old1', 'old2'];
  late final _corpus = FuzzyCorpus.strings(_current);
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }

  void _refresh() {
    _current = const ['new1', 'new2', 'new3'];
    _corpus.refresh(_current);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'refresh',
        code: "corpus.refresh(['new1', 'new2', 'new3'])",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(onPressed: _refresh, child: const Text('refresh([...])')),
            ResultList(_current),
          ],
        ),
      );
}

class ClearCard extends StatefulWidget {
  const ClearCard({super.key, required this.id});
  final String id;
  @override
  State<ClearCard> createState() => _ClearCardState();
}

class _ClearCardState extends State<ClearCard> {
  final _corpus = FuzzyCorpus.strings(['x', 'y', 'z']);
  @override
  void dispose() { _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'clear',
        code: 'corpus.clear()',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _corpus.length == 0 ? null : () => setState(_corpus.clear),
              child: const Text('clear()'),
            ),
            Text('length: ${_corpus.length}', style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}

class DisposeCard extends StatefulWidget {
  const DisposeCard({super.key, required this.id});
  final String id;
  @override
  State<DisposeCard> createState() => _DisposeCardState();
}

class _DisposeCardState extends State<DisposeCard> {
  final _corpus = FuzzyCorpus.strings(['p', 'q']);
  bool _disposed = false;
  @override
  void dispose() { if (!_disposed) _corpus.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => DemoCard(
        id: widget.id,
        title: 'dispose',
        code: 'corpus.dispose()',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElevatedButton(
              onPressed: _disposed
                  ? null
                  : () {
                      _corpus.dispose();
                      setState(() => _disposed = true);
                    },
              child: Text(_disposed ? 'disposed' : 'dispose()'),
            ),
            if (_disposed)
              const Text('further use throws StateError',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
}
