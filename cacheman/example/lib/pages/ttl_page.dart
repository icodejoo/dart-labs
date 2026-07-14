import 'dart:async';
import 'package:flutter/material.dart';
import '../main.dart';

class TtlPage extends StatefulWidget {
  const TtlPage({super.key, required this.onChanged});
  final VoidCallback onChanged;

  @override
  State<TtlPage> createState() => _TtlPageState();
}

class _TtlPageState extends State<TtlPage> {
  final _keyCtrl = TextEditingController(text: 'my_ttl_key');
  final _valCtrl = TextEditingController(text: 'hello world');
  double _ttlSeconds = 10;
  double _expireInSeconds = 15;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _keyCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {});
    widget.onChanged();
  }

  void _setWithTtl() {
    final k = _keyCtrl.text.trim();
    final v = _valCtrl.text.trim();
    if (k.isEmpty) return;
    cache.ls.set(k, v, ttl: (_ttlSeconds * 1000).round());
    _refresh();
  }

  void _setWithExpireAt() {
    final k = _keyCtrl.text.trim();
    final v = _valCtrl.text.trim();
    if (k.isEmpty) return;
    final expireAt =
        DateTime.now().add(Duration(seconds: _expireInSeconds.round()));
    cache.ls.set(k, v, expireAt: expireAt);
    _refresh();
  }

  void _get() {
    final k = _keyCtrl.text.trim();
    if (k.isEmpty) return;
    final v = cache.ls.get<dynamic>(k);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(v == null ? '"$k" not found / expired' : '$v')),
    );
  }

  void _purge() {
    cache.ls.purge();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final keys = cache.ls.keys();
    final now = DateTime.now().millisecondsSinceEpoch;

    return SingleChildScrollView(
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
          const SizedBox(height: 16),
          Text(
            'TTL: ${_ttlSeconds.round()}s',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            value: _ttlSeconds,
            min: 1,
            max: 30,
            divisions: 29,
            label: '${_ttlSeconds.round()}s',
            onChanged: (v) => setState(() => _ttlSeconds = v),
          ),
          const SizedBox(height: 4),
          Text(
            'expireAt: +${_expireInSeconds.round()}s from now',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            value: _expireInSeconds,
            min: 1,
            max: 30,
            divisions: 29,
            label: '+${_expireInSeconds.round()}s',
            onChanged: (v) => setState(() => _expireInSeconds = v),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                  onPressed: _setWithTtl, child: const Text('Set with TTL')),
              FilledButton(
                  onPressed: _setWithExpireAt,
                  child: const Text('Set with expireAt')),
              FilledButton.tonal(onPressed: _get, child: const Text('Get')),
              FilledButton.tonal(
                  onPressed: _purge, child: const Text('Purge expired')),
            ],
          ),
          const SizedBox(height: 20),
          Text('ls entries (live countdown)',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (keys.isEmpty)
            const Text('(empty)')
          else
            for (final k in keys) ...[
              _EntryRow(
                keyName: k,
                now: now,
                onDelete: () {
                  cache.ls.remove(k);
                  _refresh();
                },
              ),
              const Divider(height: 1),
            ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(
      {required this.keyName, required this.now, required this.onDelete});
  final String keyName;
  final int now;
  final VoidCallback onDelete;

  String _status() {
    final v = cache.ls.get<dynamic>(keyName);
    if (v == null) return 'expired or absent';
    return '$v';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(keyName),
      subtitle: Text(_status()),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: onDelete,
      ),
    );
  }
}
