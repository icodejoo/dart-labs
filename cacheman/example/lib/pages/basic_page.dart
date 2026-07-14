import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../main.dart';

class BasicPage extends StatefulWidget {
  const BasicPage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<BasicPage> createState() => _BasicPageState();
}

class _BasicPageState extends State<BasicPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'ls (persistent)'),
            Tab(text: 'ss (memory)'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _EngineTab(engine: cache.ls, onChanged: widget.onChanged),
              _EngineTab(engine: cache.ss, onChanged: widget.onChanged),
            ],
          ),
        ),
      ],
    );
  }
}

class _EngineTab extends StatefulWidget {
  const _EngineTab({required this.engine, required this.onChanged});
  final Engine engine;
  final VoidCallback onChanged;

  @override
  State<_EngineTab> createState() => _EngineTabState();
}

class _EngineTabState extends State<_EngineTab> {
  final _keyCtrl = TextEditingController();
  final _valCtrl = TextEditingController();

  void _refresh() {
    setState(() {});
    widget.onChanged();
  }

  void _set() {
    final k = _keyCtrl.text.trim();
    final v = _valCtrl.text.trim();
    if (k.isEmpty) return;
    widget.engine.set(k, v);
    _refresh();
  }

  void _get() {
    final k = _keyCtrl.text.trim();
    if (k.isEmpty) return;
    final v = widget.engine.get<dynamic>(k);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(v == null ? '"$k" not found' : '"$k" = $v')),
    );
  }

  void _remove() {
    final k = _keyCtrl.text.trim();
    if (k.isEmpty) return;
    widget.engine.remove(k);
    _refresh();
  }

  void _clear() {
    widget.engine.clear();
    _refresh();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keys = widget.engine.keys();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(
                labelText: 'Key', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _valCtrl,
            decoration: const InputDecoration(
                labelText: 'Value', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _set, child: const Text('Set')),
              FilledButton.tonal(onPressed: _get, child: const Text('Get')),
              FilledButton.tonal(
                  onPressed: _remove, child: const Text('Remove')),
              FilledButton.tonal(onPressed: _clear, child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: 12),
          Text('${widget.engine.length} entries',
              style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 8),
          Expanded(
            child: keys.isEmpty
                ? const Center(child: Text('(empty)'))
                : ListView.builder(
                    itemCount: keys.length,
                    itemBuilder: (_, i) {
                      final k = keys[i];
                      final v = widget.engine.get<dynamic>(k);
                      return ListTile(
                        dense: true,
                        title: Text(k),
                        subtitle: Text('$v'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () {
                            widget.engine.remove(k);
                            _refresh();
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
