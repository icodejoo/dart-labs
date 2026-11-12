import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 批量操作与三种键绑定访问器的入口。
class BatchPage extends StatelessWidget {
  /// 创建批量页面。
  const BatchPage({super.key});

  /// 创建同步批量读写会话。
  static Future<DemoSession> _batch() async {
    final cache = await demoCache('batch-operations');
    return DemoSession([
      DemoAction('Write all', '批量写入', (_) {
        cache.writeAll(demoKeys, [10, 20]);
        return cache.readAll(demoKeys);
      }),
      DemoAction('Read all', '批量读取', (_) => cache.readAll(demoKeys)),
      DemoAction('Remove all', '批量删除', (_) {
        cache.removeAll(demoKeys);
        return cache.keys();
      }),
    ]);
  }

  /// 创建带默认 TTL 的 fast、lazy 与 batchFast 访问器。
  static Future<DemoSession> _accessors() async {
    final cache = await demoCache('accessors');
    final direct = fast<String>(cache, demoKey, ttl: accessorTtl);
    final deferred = lazy<String>(cache, demoKey, ttl: accessorTtl);
    final pair = batchFast<String>(cache, demoKeys, ttl: accessorTtl);
    return DemoSession([
      DemoAction('fast.set', 'fast 写入', (input) {
        direct.set(input);
        return direct.get();
      }),
      DemoAction('lazy.get', 'lazy 读取', (_) => deferred().get()),
      DemoAction('batchFast', '批量访问器', (input) {
        for (final entry in pair.values) {
          entry.set(input);
        }
        return cache.readAll(demoKeys);
      }),
    ]);
  }

  /// 构建批量与快捷访问器卡片。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.batch.en, DemoCopy.batch.zh),
    description: tr(
      context,
      'Batch calls are sequential. Accessors bind a key, adapter and default millisecond TTL.',
      '批量调用按顺序执行；访问器绑定键、适配器与默认毫秒 TTL。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Fewer repeated keys', '少写重复的键'),
        code:
            "cache.writeAll(['first', 'second'], [10, 20]);\nfinal values = cache.readAll(['first', 'second']);\nfinal token = fast<String>(cache, 'token', ttl: 60000);\ntoken.set('abc');\nfinal deferred = lazy<String>(cache, 'token');\nfinal pair = batchFast<String>(cache, ['first', 'second']);",
        child: DemoGrid(
          children: [
            actionCard(
              context,
              en: 'Batch operations',
              zh: '批量操作',
              descriptionEn: 'Read results preserve the requested key order.',
              descriptionZh: '读取结果保持请求键的顺序。',
              create: _batch,
            ),
            actionCard(
              context,
              en: 'Bound accessors',
              zh: '绑定访问器',
              descriptionEn: 'Shared value, with a 60-second default TTL.',
              descriptionZh: '共用输入值，默认 60 秒 TTL。',
              create: _accessors,
              editable: true,
            ),
          ],
        ),
      ),
    ],
  );
}
