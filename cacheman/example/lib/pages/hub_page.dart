import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../get_storage_cache.dart';
import '../demo_support.dart';

/// 共享 Hub 的监听过滤与延迟落盘入口。
class HubPage extends StatelessWidget {
  /// 创建共享监听页面。
  const HubPage({super.key});

  /// 构建过滤自身写入与包含自身写入的对照。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.hub.en, DemoCopy.hub.zh),
    description: tr(
      context,
      'Two cache instances share a container and namespace. Reads see writes immediately.',
      '两个实例共享容器与命名空间，写入后可以立即读取。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Compare watch delivery', '对比监听通知'),
        code:
            "final stop = a.watch<int>('message', (value) {\n  // Update your UI.\n}, includeOwnWrites: false);\nb.write('message', 1); // A receives the event\na.write('message', 2); // Own write is filtered\na.flush(); // Schedules pending persistence; returns void\nstop();",
        child: DemoGrid(
          children: [
            for (final own in [false, true])
              DemoGridItem(
                child: DemoCard(
                  title: own
                      ? tr(context, 'All writes', '包含自身写入')
                      : tr(context, 'Peer writes only', '只监听其他实例'),
                  description: tr(
                    context,
                    'A.watch(includeOwnWrites: $own). Replay resets values and subscriptions.',
                    'A.watch(includeOwnWrites: $own)，重放会复位数据与订阅。',
                  ),
                  child: HubDemo(includeOwnWrites: own),
                ),
              ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'A opts into flushDelay: 200ms and purgeOnInit. A crash can lose pending writes. B mutations queue a whole-container save immediately; flush() is not an awaited disk acknowledgement.',
          'A 启用 200ms 延迟落盘和 purgeOnInit；崩溃可能丢失窗口内写入。B 的变更仍立即排整库保存；flush() 不代表已等待磁盘完成。',
        ),
        kind: InfoNoteKind.warning,
      ),
    ],
  );
}

/// 拥有独立监听、数据与清理生命周期的 Hub 主体。
class HubDemo extends StatefulWidget {
  /// 创建监听过滤策略。
  const HubDemo({super.key, required this.includeOwnWrites});

  /// 是否监听本实例写入。
  final bool includeOwnWrites;

  /// 创建监听状态。
  @override
  State<HubDemo> createState() => _HubDemoState();
}

/// 在重放和离页时取消旧监听并提交待保存数据。
class _HubDemoState extends State<HubDemo> {
  /// 监听与延迟写入实例。
  Cacheman? _a;

  /// 同作用域的另一个实例。
  Cacheman? _b;

  /// 当前订阅的取消回调。
  VoidCallback? _stop;

  /// 最近的监听值，限制显示数量。
  final _events = <int?>[];

  /// 是否已经请求立即保存。
  bool _flushed = false;

  /// 是否发生初始化失败。
  bool _failed = false;

  /// 启动共享实例。
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 初始化完成后再挂监听，防止重放清理产生假事件。
  Future<void> _initialize() async {
    try {
      final scope = 'hub-${widget.includeOwnWrites}';
      final a = await demoCache(
        scope,
        options: CachemanOptions(
          namespace: scope,
          flushDelay: const Duration(milliseconds: 200),
          purgeOnInit: true,
        ),
      );
      final b = GetStorageCache(
        container: demoContainer,
        options: CachemanOptions(namespace: scope),
      );
      await b.ensureInitialized();
      if (!mounted) return;
      _stop = a.watch<int>(demoKey, (value) {
        if (!mounted) return;
        setState(() {
          _events.insert(0, value);
          if (_events.length > 4) _events.removeLast();
        });
      }, includeOwnWrites: widget.includeOwnWrites);
      setState(() {
        _a = a;
        _b = b;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// 从指定实例写入递增值，立即读取共享结果。
  void _write(Cacheman source) => setState(() {
    source.write(demoKey, (source.read<int>(demoKey) ?? 0) + 1);
    _flushed = false;
  });

  /// 清空当前命名空间并触发监听通知。
  void _erase() => setState(() {
    _b!.erase();
  });

  /// 请求提交待落盘数据，避免暗示已确认磁盘持久化。
  void _flush() => setState(() {
    _a!.flush();
    _flushed = true;
  });

  /// 释放订阅与待保存数据。
  @override
  void dispose() {
    _stop?.call();
    _a?.flush();
    super.dispose();
  }

  /// 构建即时读数与有限事件历史。
  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (_failed) {
      return Text(
        tr(
          context,
          DemoCopy.initializationFailed.en,
          DemoCopy.initializationFailed.zh,
        ),
      );
    }
    if (a == null) {
      return Text(
        tr(context, DemoCopy.initializing.en, DemoCopy.initializing.zh),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            context,
            'Value: ${a.read<int>(demoKey) ?? 0}',
            '当前值：${a.read<int>(demoKey) ?? 0}',
          ),
        ),
        const SizedBox(height: DemoTokens.smallGap),
        Wrap(
          spacing: DemoTokens.smallGap,
          runSpacing: DemoTokens.smallGap,
          children: [
            FilledButton.tonal(
              onPressed: () => _write(a),
              child: Text(tr(context, 'Write A', 'A 写入')),
            ),
            FilledButton.tonal(
              onPressed: () => _write(_b!),
              child: Text(tr(context, 'Write B', 'B 写入')),
            ),
            OutlinedButton(
              onPressed: _erase,
              child: Text(tr(context, 'Erase B', 'B 清空')),
            ),
            OutlinedButton(
              onPressed: _flush,
              child: Text(tr(context, 'Flush now', '立即排保存')),
            ),
          ],
        ),
        const SizedBox(height: DemoTokens.smallGap),
        Text(
          _events.isEmpty
              ? tr(context, 'No watch events yet.', '暂无监听事件。')
              : tr(context, 'A.watch events: $_events', 'A.watch 事件：$_events'),
        ),
        if (_flushed)
          Text(tr(context, 'Pending save requested.', '已请求保存待落盘数据。')),
      ],
    );
  }
}
