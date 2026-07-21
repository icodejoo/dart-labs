import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../main.dart';

class BatchPage extends StatefulWidget {
  const BatchPage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  final _k1 = TextEditingController(text: 'batch_a');
  final _v1 = TextEditingController(text: 'alpha');
  final _k2 = TextEditingController(text: 'batch_b');
  final _v2 = TextEditingController(text: 'beta');
  final _k3 = TextEditingController(text: 'batch_c');
  final _v3 = TextEditingController(text: 'gamma');

  late final FastAccessor<String> _fa =
      fast<String>(cache, 'fa_key');
  final _faValCtrl = TextEditingController(text: 'fast_value');
  String? _faDisplay;

  String _batchResult = '';

  void _refresh() {
    setState(() {});
    widget.onChanged();
  }

  List<String> get _batchKeys =>
      [_k1.text.trim(), _k2.text.trim(), _k3.text.trim()];
  List<String> get _batchValues =>
      [_v1.text.trim(), _v2.text.trim(), _v3.text.trim()];

  void _setAll() {
    cache.writeAll(_batchKeys, _batchValues);
    setState(() => _batchResult = 'writeAll done');
    _refresh();
  }

  void _getAll() {
    final results = cache.readAll(_batchKeys);
    setState(() =>
        _batchResult = results.asMap().entries.map((e) => '${_batchKeys[e.key]}: ${e.value}').join('\n'));
  }

  void _removeAll() {
    cache.removeAll(_batchKeys);
    setState(() => _batchResult = 'removeAll done');
    _refresh();
  }

  void _faGet() {
    final v = _fa.get();
    setState(() => _faDisplay = v ?? '(not set)');
  }

  void _faSet() {
    final v = _faValCtrl.text.trim();
    if (v.isEmpty) return;
    _fa.set(v);
    setState(() => _faDisplay = v);
    widget.onChanged();
  }

  void _faRemove() {
    _fa.remove();
    setState(() => _faDisplay = '(removed)');
    widget.onChanged();
  }

  @override
  void dispose() {
    _k1.dispose(); _v1.dispose();
    _k2.dispose(); _v2.dispose();
    _k3.dispose(); _v3.dispose();
    _faValCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Batch operations (ls)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          _PairRow(kCtrl: _k1, vCtrl: _v1, label: '1'),
          const SizedBox(height: 8),
          _PairRow(kCtrl: _k2, vCtrl: _v2, label: '2'),
          const SizedBox(height: 8),
          _PairRow(kCtrl: _k3, vCtrl: _v3, label: '3'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _setAll, child: const Text('writeAll')),
              FilledButton.tonal(onPressed: _getAll, child: const Text('readAll')),
              FilledButton.tonal(
                  onPressed: _removeAll, child: const Text('removeAll')),
            ],
          ),
          if (_batchResult.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_batchResult,
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 12),
          Text('FastAccessor  (key: "fa_key", ls)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _faValCtrl,
            decoration: const InputDecoration(
                labelText: 'Value to set', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: _faSet, child: const Text('set')),
              FilledButton.tonal(onPressed: _faGet, child: const Text('get')),
              FilledButton.tonal(onPressed: _faRemove, child: const Text('remove')),
            ],
          ),
          if (_faDisplay != null) ...[
            const SizedBox(height: 12),
            Text('Current value: $_faDisplay',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow(
      {required this.kCtrl, required this.vCtrl, required this.label});
  final TextEditingController kCtrl;
  final TextEditingController vCtrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: kCtrl,
            decoration: InputDecoration(
                labelText: 'Key $label', border: const OutlineInputBorder()),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: vCtrl,
            decoration: InputDecoration(
                labelText: 'Value $label',
                border: const OutlineInputBorder()),
          ),
        ),
      ],
    );
  }
}
