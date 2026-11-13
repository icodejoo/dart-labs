import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';
import '../demo_backends.dart';

/// 同步、异步与自定义存储的入口。
class AsyncPage extends StatelessWidget {
  /// 创建分层存储页面。
  const AsyncPage({super.key});

  /// 创建应用自接持久化的小值缓存。
  static Future<DemoSession> _sync() async {
    final cache = await demoCache('summary');
    return DemoSession([
      DemoAction('Store summary', '保存摘要', (_) {
        cache.write(demoKey, 1000);
        return cache.read<int>(demoKey);
      }),
    ]);
  }

  /// 创建显式 await 的大值 Map 后端。
  static Future<DemoSession> _async() async {
    final cache = MemoryAsync();
    await cache.ensureInitialized();
    return DemoSession([
      DemoAction('Store 1,000 rows', '保存 1,000 行', (_) async {
        await cache.write(demoKey, List.generate(1000, (index) => index));
        final value = await cache.read<List<dynamic>>(demoKey);
        return {'rows': value?.length, demoKeysField: await cache.length()};
      }),
      DemoAction(DemoCopy.erase.en, DemoCopy.erase.zh, (_) async {
        await cache.erase();
        return await cache.length();
      }),
    ]);
  }

  /// 创建同步更新的自定义原语后端。
  static Future<DemoSession> _custom() async {
    final cache = MemorySync();
    await cache.ensureInitialized();
    return DemoSession([
      DemoAction('Write custom', '自定义写入', (input) {
        cache.write(demoKey, input);
        return cache.read<String>(demoKey);
      }),
      DemoAction(DemoCopy.erase.en, DemoCopy.erase.zh, (_) {
        cache.erase();
        return cache.length;
      }),
    ]);
  }

  /// 构建三个相同逻辑键、独立后端的示例。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.async.en, DemoCopy.async.zh),
    description: tr(
      context,
      'One API shape, separate backends. AsyncCacheman awaits reads and writes; Cacheman stays synchronous.',
      '一致的 API 形式，不同的后端；AsyncCacheman 等待读写，Cacheman 保持同步。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Choose a storage boundary', '选择存储边界'),
        code:
            "final summary = GetStorageCache();\nawait summary.ensureInitialized();\nsummary.write('rows', 1000);\n// App-defined subclass; no built-in asynchronous backend.\nfinal report = MemoryAsync();\nawait report.ensureInitialized();\nawait report.write('rows', [1, 2, 3]);\nfinal rows = await report.read<List<dynamic>>('rows');",
        child: DemoGrid(
          children: [
            actionCard(
              context,
              en: 'Persistent summary',
              zh: '持久化摘要',
              descriptionEn: 'App-owned get_storage backend for small values.',
              descriptionZh: '应用自接 get_storage 后端保存小值。',
              create: _sync,
            ),
            actionCard(
              context,
              en: 'Async report',
              zh: '异步报表',
              descriptionEn:
                  'Example-only Map; not a disk-performance benchmark.',
              descriptionZh: '仅演示的 Map 后端，不代表磁盘性能。',
              create: _async,
            ),
            actionCard(
              context,
              en: 'Custom sync backend',
              zh: '自定义同步后端',
              descriptionEn: 'Cacheman.custom with immediate memory updates.',
              descriptionZh: 'Cacheman.custom 在返回前更新内存。',
              create: _custom,
              editable: true,
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'The two Map backends are example code. Replace their primitives with your own storage; the package adds no asynchronous backend.',
          '两个 Map 后端均为示例代码；应用应自行提供存储原语，本包不内置异步后端。',
        ),
      ),
    ],
  );
}
