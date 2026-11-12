import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 当前同步 CRUD 与枚举的入口。
class BasicPage extends StatelessWidget {
  /// 创建基础页面。
  const BasicPage({super.key});

  /// 初始化隔离数据并提供编辑、读取和删除。
  static Future<DemoSession> _crud() async {
    final cache = await demoCache('basic-crud');
    return DemoSession([
      DemoAction('Write', '写入', (input) {
        cache.write(demoKey, input);
        return cache.read<String>(demoKey);
      }),
      DemoAction(
        DemoCopy.read.en,
        DemoCopy.read.zh,
        (_) => cache.read<String>(demoKey),
      ),
      DemoAction('Remove', '删除', (_) {
        cache.remove(demoKey);
        return cache.keys();
      }),
      DemoAction('Erase scope', '清空本卡片', (_) {
        cache.erase();
        return cache.keys();
      }),
    ]);
  }

  /// 展示一次 keys 快照与按键顺序读取。
  static Future<DemoSession> _enumerate() async {
    final cache = await demoCache('enumeration');
    return DemoSession([
      DemoAction('Write pair', '写入两项', (_) {
        cache.writeAll(demoKeys, [1, 2]);
        return {demoKeysField: cache.keys(), 'length': cache.length};
      }),
      DemoAction('Read snapshot', '读取快照', (_) {
        final keys = cache.keys();
        return cache.readAll(keys);
      }),
    ]);
  }

  /// 构建首屏可操作的双卡片页面。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.basic.en, DemoCopy.basic.zh),
    description: tr(
      context,
      'Initialize once, then read and write synchronously. Each card owns its namespace.',
      '初始化一次后同步读写。每张卡片使用独立命名空间。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Try persistent storage', '试试持久化存储'),
        code:
            "final cache = Cacheman(options: CachemanOptions(namespace: 'demo'));\nawait cache.ensureInitialized();\ncache.write('message', 'Ada');\nfinal value = cache.read<String>('message');\nfinal keys = cache.keys(); // snapshot, no deprecated key(index)\ncache.readAll(keys);",
        child: DemoGrid(
          children: [
            actionCard(
              context,
              en: 'Keys & length',
              zh: '键与数量',
              descriptionEn: 'Enumerate with keys(), then readAll().',
              descriptionZh: '用 keys() 快照枚举，再批量读取。',
              create: _enumerate,
            ),
            actionCard(
              context,
              en: 'Read & write',
              zh: '读写与删除',
              descriptionEn: 'Edit the value stored under message.',
              descriptionZh: '编辑 message 键的值。',
              create: _crud,
              editable: true,
            ),
          ],
        ),
      ),
    ],
  );
}
