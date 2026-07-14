import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../main.dart';

class NamespacePage extends StatefulWidget {
  const NamespacePage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<NamespacePage> createState() => _NamespacePageState();
}

class _NamespacePageState extends State<NamespacePage> {
  final _keyCtrlA = TextEditingController(text: 'profile');
  final _valCtrlA = TextEditingController(text: 'alice@example.com');
  final _keyCtrlB = TextEditingController(text: 'profile');
  final _valCtrlB = TextEditingController(text: 'bob@example.com');

  List<String> _keysA = [];
  List<String> _keysB = [];
  String _statusMsg = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Engine get _nsA {
    cache.ls.setNamespace('account_a');
    return cache.ls;
  }

  Engine get _nsB {
    cache.ls.setNamespace('account_b');
    return cache.ls;
  }

  void _reload() {
    cache.ls.setNamespace('account_a');
    final kA = cache.ls.keys();
    cache.ls.setNamespace('account_b');
    final kB = cache.ls.keys();
    cache.ls.setNamespace(null);
    setState(() {
      _keysA = kA;
      _keysB = kB;
    });
    widget.onChanged();
  }

  void _setA() {
    final k = _keyCtrlA.text.trim();
    final v = _valCtrlA.text.trim();
    if (k.isEmpty) return;
    _nsA.set(k, v);
    cache.ls.setNamespace(null);
    _reload();
    setState(() => _statusMsg = 'Set "$k" in account_a');
  }

  void _getA() {
    final k = _keyCtrlA.text.trim();
    cache.ls.setNamespace('account_a');
    final v = cache.ls.get<dynamic>(k);
    cache.ls.setNamespace(null);
    setState(() =>
        _statusMsg = v == null ? 'account_a: "$k" not found' : 'account_a "$k" = $v');
  }

  void _setB() {
    final k = _keyCtrlB.text.trim();
    final v = _valCtrlB.text.trim();
    if (k.isEmpty) return;
    _nsB.set(k, v);
    cache.ls.setNamespace(null);
    _reload();
    setState(() => _statusMsg = 'Set "$k" in account_b');
  }

  void _getB() {
    final k = _keyCtrlB.text.trim();
    cache.ls.setNamespace('account_b');
    final v = cache.ls.get<dynamic>(k);
    cache.ls.setNamespace(null);
    setState(() =>
        _statusMsg = v == null ? 'account_b: "$k" not found' : 'account_b "$k" = $v');
  }

  void _clearA() {
    cache.ls.setNamespace('account_a');
    cache.ls.clear();
    cache.ls.setNamespace(null);
    _reload();
    setState(() => _statusMsg = 'Cleared account_a — account_b untouched');
  }

  @override
  void dispose() {
    _keyCtrlA.dispose();
    _valCtrlA.dispose();
    _keyCtrlB.dispose();
    _valCtrlB.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_statusMsg.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_statusMsg),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AccountPanel(
                  account: 'account_a',
                  color: Colors.teal.shade50,
                  keyCtrl: _keyCtrlA,
                  valCtrl: _valCtrlA,
                  keys: _keysA,
                  onSet: _setA,
                  onGet: _getA,
                  onClear: _clearA,
                  getEngine: () {
                    cache.ls.setNamespace('account_a');
                    return cache.ls;
                  },
                  resetEngine: () => cache.ls.setNamespace(null),
                  onChanged: _reload,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AccountPanel(
                  account: 'account_b',
                  color: Colors.indigo.shade50,
                  keyCtrl: _keyCtrlB,
                  valCtrl: _valCtrlB,
                  keys: _keysB,
                  onSet: _setB,
                  onGet: _getB,
                  onClear: null,
                  getEngine: () {
                    cache.ls.setNamespace('account_b');
                    return cache.ls;
                  },
                  resetEngine: () => cache.ls.setNamespace(null),
                  onChanged: _reload,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({
    required this.account,
    required this.color,
    required this.keyCtrl,
    required this.valCtrl,
    required this.keys,
    required this.onSet,
    required this.onGet,
    required this.onClear,
    required this.getEngine,
    required this.resetEngine,
    required this.onChanged,
  });

  final String account;
  final Color color;
  final TextEditingController keyCtrl;
  final TextEditingController valCtrl;
  final List<String> keys;
  final VoidCallback onSet;
  final VoidCallback onGet;
  final VoidCallback? onClear;
  final Engine Function() getEngine;
  final VoidCallback resetEngine;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(account,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: keyCtrl,
            decoration: const InputDecoration(
                labelText: 'Key',
                border: OutlineInputBorder(),
                isDense: true),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: valCtrl,
            decoration: const InputDecoration(
                labelText: 'Value',
                border: OutlineInputBorder(),
                isDense: true),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FilledButton(
                  onPressed: onSet,
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  child: const Text('Set')),
              FilledButton.tonal(
                  onPressed: onGet,
                  style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  child: const Text('Get')),
              if (onClear != null)
                FilledButton.tonal(
                    onPressed: onClear,
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('Clear A')),
            ],
          ),
          const SizedBox(height: 10),
          Text('${keys.length} keys:',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          if (keys.isEmpty)
            const Text('(empty)', style: TextStyle(fontSize: 12))
          else
            for (final k in keys)
              Text('• $k = ${_readKey(k)}',
                  style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  String _readKey(String k) {
    final eng = getEngine();
    final v = eng.get<dynamic>(k);
    resetEngine();
    return '$v';
  }
}
