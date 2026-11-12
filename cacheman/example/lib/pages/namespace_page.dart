import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 命名空间隔离与切换的入口。
class NamespacePage extends StatelessWidget {
  /// 创建命名空间页面。
  const NamespacePage({super.key});

  /// 在同一容器中建立两个稳定的命名空间实例。
  static Future<DemoSession> _isolation() async {
    final a = await demoCache('accounts:a');
    final b = await demoCache('accounts:b');
    return DemoSession([
      DemoAction('Write both', '写入两侧', (_) {
        a.write(demoKey, 'Alice');
        b.write(demoKey, 'Bob');
        return {'A': a.read<String>(demoKey), 'B': b.read<String>(demoKey)};
      }),
      DemoAction('Erase A', '清空 A', (_) {
        a.erase();
        return {'A': a.keys(), 'B': b.read<String>(demoKey)};
      }),
      DemoAction(
        'Storage keys',
        '查看底层键',
        (_) => [a.storageKey(demoKey), b.storageKey(demoKey)],
      ),
    ]);
  }

  /// 演示显式切域，避免在构建或 getter 中修改共享实例。
  static Future<DemoSession> _switch() async {
    const first = 'switch:a';
    const second = 'switch:a:b';
    final cache = await demoCache(first);
    cache.setNamespace(second);
    cache.erase();
    cache.setNamespace(first);
    return DemoSession([
      DemoAction('Switch & write', '切换并写入', (_) {
        cache.setNamespace(second);
        cache.write(demoKey, demoValue);
        return cache.storageKey(demoKey);
      }),
      DemoAction('Back to A', '切回 A', (_) {
        cache.setNamespace(first);
        return cache.keys();
      }),
    ]);
  }

  /// 构建隔离和转义演示。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.namespace.en, DemoCopy.namespace.zh),
    description: tr(
      context,
      'Scopes share a backend, with escaped prefixes and scoped erase.',
      '同一后端通过转义前缀隔离，erase 只清理当前作用域。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Independent scopes', '独立作用域'),
        code:
            "final a = Cacheman(options: CachemanOptions(namespace: 'accounts:a'));\nfinal b = Cacheman(options: CachemanOptions(namespace: 'accounts:b'));\nawait a.ensureInitialized();\nawait b.ensureInitialized();\na.erase(); // b remains intact\na.setNamespace('accounts:a:b');\na.storageKey('message');",
        child: DemoGrid(
          children: [
            actionCard(
              context,
              en: 'Account isolation',
              zh: '账户隔离',
              descriptionEn: 'The same logical key stores different values.',
              descriptionZh: '相同逻辑键可以保存不同账户的数据。',
              create: _isolation,
            ),
            actionCard(
              context,
              en: 'Switch & escape',
              zh: '切换与转义',
              descriptionEn:
                  'Colons in namespaces are escaped, preventing collisions.',
              descriptionZh: '命名空间中的冒号会转义，防止前缀碰撞。',
              create: _switch,
            ),
          ],
        ),
      ),
    ],
  );
}
