import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../main.dart';

class AdvancedPage extends StatefulWidget {
  const AdvancedPage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  String _jsonxResult = '';
  String _debugSnapshot = '';

  void _storeDateTime() {
    final now = DateTime.now();
    final encoded = Jsonx.encode(now);
    cache.ls.set('jsonx_datetime', encoded);
    final decoded = Jsonx.decode<DateTime>(encoded);
    setState(() =>
        _jsonxResult = 'DateTime\n  in:  $now\n  enc: $encoded\n  out: $decoded');
  }

  void _storeDuration() {
    const dur = Duration(hours: 2, minutes: 30);
    final encoded = Jsonx.encode(dur);
    cache.ls.set('jsonx_duration', encoded);
    final decoded = Jsonx.decode<Duration>(encoded);
    setState(() =>
        _jsonxResult = 'Duration\n  in:  $dur\n  enc: $encoded\n  out: $decoded');
  }

  void _storeSet() {
    const s = {1, 2, 3, 99};
    final encoded = Jsonx.encode(s);
    cache.ls.set('jsonx_set', encoded);
    final decoded = Jsonx.decode<Set<dynamic>>(encoded);
    setState(() =>
        _jsonxResult = 'Set\n  in:  $s\n  enc: $encoded\n  out: $decoded');
  }

  void _storeBigInt() {
    final b = BigInt.parse('99999999999999999999999999999');
    final encoded = Jsonx.encode(b);
    cache.ls.set('jsonx_bigint', encoded);
    final decoded = Jsonx.decode<BigInt>(encoded);
    setState(() =>
        _jsonxResult = 'BigInt\n  in:  $b\n  enc: $encoded\n  out: $decoded');
  }

  void _storeUri() {
    final uri = Uri.parse('https://pub.dev/packages/cacheman?tab=readme');
    final encoded = Jsonx.encode(uri);
    cache.ls.set('jsonx_uri', encoded);
    final decoded = Jsonx.decode<Uri>(encoded);
    setState(() =>
        _jsonxResult = 'Uri\n  in:  $uri\n  enc: $encoded\n  out: $decoded');
  }

  void _takeSnapshot() {
    final snap = debug(cache.ls);
    if (snap.isEmpty) {
      setState(() => _debugSnapshot = '(ls is empty — set some keys first)');
      return;
    }
    final buf = StringBuffer();
    for (final entry in snap.entries) {
      buf.writeln('${entry.key}: ${entry.value}');
    }
    setState(() => _debugSnapshot = buf.toString().trim());
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Jsonx — extended type roundtrip',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
              'Encode/decode types that plain jsonEncode cannot handle.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                  onPressed: _storeDateTime, child: const Text('DateTime')),
              FilledButton(
                  onPressed: _storeDuration, child: const Text('Duration')),
              FilledButton(onPressed: _storeSet, child: const Text('Set')),
              FilledButton(
                  onPressed: _storeBigInt, child: const Text('BigInt')),
              FilledButton(onPressed: _storeUri, child: const Text('Uri')),
            ],
          ),
          if (_jsonxResult.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                _jsonxResult,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ],
          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 12),
          Text('debug() — ls snapshot',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Reads all entries in ls with metadata.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: _takeSnapshot, child: const Text('Take snapshot')),
          if (_debugSnapshot.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _debugSnapshot,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
