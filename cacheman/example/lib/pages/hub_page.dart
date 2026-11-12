import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';

/// Demonstrates peer notifications, immediate reads and delayed persistence.
/// 演示实例间通知、即时读取和延迟落盘。
class HubPage extends StatefulWidget {
  /// Creates the shared-container demo. / 创建共享容器演示。
  const HubPage({super.key});

  @override
  State<HubPage> createState() => _HubPageState();
}

/// Owns subscriptions and flushes pending data on disposal.
/// 持有订阅，并在释放时排保存待落盘数据。
class _HubPageState extends State<HubPage> {
  /// Stable demo scope and key. / 稳定的演示作用域和键。
  static const _scope = 'hub-demo';
  static const _key = 'count';

  /// Both instances use the default container and a dedicated namespace.
  /// 两个实例使用默认容器及演示专用命名空间。
  final _a = Cacheman(
    options: const CachemanOptions(
      namespace: _scope,
      flushDelay: Duration(milliseconds: 200),
      purgeOnInit: true,
    ),
  );
  final _b = Cacheman(options: const CachemanOptions(namespace: _scope));

  /// Subscription cleanup and initialization status. / 订阅清理与初始化状态。
  VoidCallback? _stop;
  bool _ready = false;

  /// Visible notification history. / 可见通知历史。
  final _events = <String>[];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// Initializes once before synchronous interactions. / 同步交互前初始化一次。
  Future<void> _initialize() async {
    await _a.ensureInitialized();
    await _b.ensureInitialized();
    if (!mounted) return;
    _stop = _a.watch<int>(_key, (value) {
      setState(() {
        _events.insert(0, 'A.watch: $value');
        if (_events.length > 8) _events.removeLast();
      });
    }, includeOwnWrites: false);
    setState(() => _ready = true);
  }

  /// Writes an immediately readable counter through the selected instance.
  /// 通过选定实例写入立即可读的计数。
  void _increment(Cacheman source) {
    source.write(_key, (source.read<int>(_key) ?? 0) + 1);
    setState(() {});
  }

  @override
  void dispose() {
    _stop?.call();
    if (_ready) _a.flush();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('Shared Hub / 共享容器', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text(
        'A uses flushDelay: 200ms and purgeOnInit. A.watch ignores A writes; '
        'B writes and scoped erase notify it. A write is readable immediately. '
        'A crash can lose writes within the 200ms window. B writes/deletes '
        'still queue a whole-container save immediately.',
      ),
      const SizedBox(height: 12),
      if (!_ready)
        const LinearProgressIndicator()
      else ...[
        Text(
          'Value: ${_a.read<int>(_key)}; A keys: ${_a.keys()}; B keys: ${_b.keys()}',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () => _increment(_a),
              child: const Text('Write A'),
            ),
            FilledButton(
              onPressed: () => _increment(_b),
              child: const Text('Write B'),
            ),
            OutlinedButton(
              onPressed: () {
                _b.erase();
                setState(() {});
              },
              child: const Text('Erase B'),
            ),
            OutlinedButton(onPressed: _a.flush, child: const Text('Flush now')),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          _events.isEmpty ? 'No watch events yet / 暂无监听事件' : _events.join('\n'),
        ),
      ],
    ],
  );
}
