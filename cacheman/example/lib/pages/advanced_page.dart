import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 扩展 JSON 类型与缓存快照的入口。
class AdvancedPage extends StatelessWidget {
  /// 创建扩展类型页面。
  const AdvancedPage({super.key});

  /// 使用实际缓存自动序列化类型，避免将编码字符串再次写入。
  static Future<DemoSession> _types() async {
    const scope = 'jsonx';
    final cache = await demoCache(
      scope,
      options: CachemanOptions(
        namespace: scope,
        serialize: (entity) => Jsonx.encode(entity.toJson()),
        deserialize: (raw) =>
            CacheEntity.fromJson(Jsonx.decode<Map<String, dynamic>>(raw)),
      ),
    );
    final samples = <String, Object>{
      'DateTime': DateTime.utc(2026, 1, 1),
      'Duration': const Duration(hours: 2, minutes: 30),
      'Set': {1, 2, 3},
      'BigInt': BigInt.parse('99999999999999999999999999999'),
      'Uri': Uri.parse(demoPubUrl),
    };
    return DemoSession([
      for (final entry in samples.entries)
        DemoAction(entry.key, entry.key, (_) {
          cache.write(demoKey, entry.value);
          final value = cache.read<dynamic>(demoKey);
          return {
            'type': value.runtimeType,
            demoValueField: value,
            'Jsonx.encode': Jsonx.encode(entry.value),
          };
        }),
    ]);
  }

  /// 提供只读快照与对应命名空间数据。
  static Future<DemoSession> _snapshot() async {
    final cache = await demoCache('snapshot');
    return DemoSession([
      DemoAction('Seed values', '写入样本', (_) {
        cache.writeAll(demoKeys, [demoValue, 42]);
        return cache.keys();
      }),
      DemoAction('Take snapshot', '获取快照', (_) => debug(cache)),
    ]);
  }

  /// 构建类型往返和调试卡片。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.advanced.en, DemoCopy.advanced.zh),
    description: tr(
      context,
      'Configure Jsonx serialization, then store extended Dart values directly.',
      '配置 Jsonx 序列化后，直接存储支持的扩展 Dart 值。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Inspect values', '检查数据'),
        code:
            "final cache = Cacheman(options: CachemanOptions(\n  serialize: (e) => Jsonx.encode(e.toJson()),\n  deserialize: (s) => CacheEntity.fromJson(\n    Jsonx.decode<Map<String, dynamic>>(s)),\n));\nawait cache.ensureInitialized();\nfinal date = DateTime.utc(2026, 1, 1);\ncache.write('date', date);\nfinal restored = cache.read<DateTime>('date');\nfinal encoded = Jsonx.encode(date);\nfinal decoded = Jsonx.decode<DateTime>(encoded);\nfinal snapshot = debug(cache);",
        child: DemoGrid(
          children: [
            actionCard(
              context,
              en: 'Extended types',
              zh: '扩展类型',
              descriptionEn: 'DateTime, Duration, Set, BigInt and Uri.',
              descriptionZh: '日期、时长、集合、大整数和 URI。',
              create: _types,
            ),
            actionCard(
              context,
              en: 'Debug snapshot',
              zh: '调试快照',
              descriptionEn: 'Decoded values with namespace-prefixed keys.',
              descriptionZh: '查看解码值与带命名空间的键。',
              create: _snapshot,
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'debug() performs normal reads: it can delete expired entries or renew sliding TTL. It is not an expiry-metadata inspector.',
          'debug() 会执行普通读取：可能删除过期项或触发滑动续期；它不展示过期元数据。',
        ),
      ),
    ],
  );
}
