import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import '../demo_kit/demo_kit.dart';
import '../demo_support.dart';

/// 通过显式适配器转换的示例业务对象。
class _Profile {
  /// 创建业务值。
  const _Profile(this.name);

  /// 显示名称。
  final String name;
}

/// 类型适配、非抛出式读取与错误分类的入口。
class TypesPage extends StatelessWidget {
  /// 创建类型安全页面。
  const TypesPage({super.key});

  /// 业务对象 JSON 字段名。
  static const _nameField = 'name';

  /// 双向转换业务对象。
  static final _profileAdapter = ValueAdapter<_Profile>(
    toJson: (value) => {_nameField: value.name},
    fromJson: (value) =>
        _Profile((value as Map<String, dynamic>)[_nameField] as String),
  );

  /// 演示 eager 集合转换和带适配器的快捷访问器。
  static Future<DemoSession> _adapters() async {
    final cache = await demoCache('adapters');
    final profile = fast<_Profile>(
      cache,
      demoKey,
      adapter: _profileAdapter,
      ttl: accessorTtl,
    );
    return DemoSession([
      DemoAction('Typed list', '类型化列表', (_) {
        cache.write(demoKey, [demoValue]);
        return cache.readWith<List<String>>(
          demoKey,
          adapter: ValueAdapter.listOf<String>(),
        );
      }),
      DemoAction('Profile adapter', '业务对象适配', (_) {
        profile.set(const _Profile(demoValue));
        return profile.get()?.name;
      }),
    ]);
  }

  /// 演示类型不匹配保留数据与损坏条目删除的差异。
  static Future<DemoSession> _errors() async {
    const scope = demoErrorsField;
    final errors = <String>[];
    final cache = await demoCache(
      scope,
      options: CachemanOptions(
        namespace: scope,
        onError: (key, error) {
          errors.add(error.runtimeType.toString());
        },
      ),
    );
    return DemoSession([
      DemoAction('Type mismatch', '类型不匹配', (_) {
        errors.clear();
        cache.write(demoKey, 1);
        final value = cache.read<double>(demoKey, -1);
        return {
          'fallback': value,
          demoRetainedField: cache.keys().contains(demoKey),
          'num': cache.read<num>(demoKey),
          demoErrorsField: errors.toList(),
        };
      }),
      DemoAction('Corrupt entry', '损坏条目', (_) async {
        errors.clear();
        await cache.container.write(cache.storageKey(demoKey), '{');
        final value = cache.read<String>(demoKey);
        return {
          demoValueField: value,
          demoRetainedField: cache.keys().contains(demoKey),
          demoErrorsField: errors.toList(),
        };
      }),
      DemoAction('Serialize error', '序列化错误', (_) {
        errors.clear();
        cache.write(demoKey, Object());
        return errors.toList();
      }),
    ]);
  }

  /// 构建类型与错误卡片，不展示历史迁移章节。
  @override
  Widget build(BuildContext context) => DemoPage(
    title: tr(context, DemoCopy.types.en, DemoCopy.types.zh),
    description: tr(
      context,
      'Use ValueAdapter for business objects and typed collections. Errors are classified as CachemanError subclasses.',
      '用 ValueAdapter 转换业务对象与类型化集合；错误按 CachemanError 子类分类。',
    ),
    sections: [
      DemoSection(
        title: tr(context, 'Explicit conversion & safe defaults', '显式转换与安全默认值'),
        code:
            "cache.write('names', ['Ada']);\nfinal names = cache.readWith<List<String>>('names',\n  adapter: ValueAdapter.listOf<String>());\n// read<int>/read<double> do not coerce numbers.\n// onError: (key, error) {\n//   if (error is CachemanError) inspect(error.cause);\n// }",
        child: DemoGrid(
          children: [
            actionCard(
              context,
              en: 'Value adapters',
              zh: '值适配器',
              descriptionEn:
                  'Typed collections and a key-bound business object.',
              descriptionZh: '类型化集合与绑定键的业务对象。',
              create: _adapters,
            ),
            actionCard(
              context,
              en: 'Structured errors',
              zh: '结构化错误',
              descriptionEn: 'Mismatches retain data; corrupt reads delete it.',
              descriptionZh: '类型不匹配保留数据，损坏读取会删除条目。',
              create: _errors,
            ),
          ],
        ),
      ),
      InfoNote(
        text: tr(
          context,
          'force only retries backend write failures. Serialization and adapter failures report SerializeError without purge or retry.',
          'force 只重试后端写入失败；序列化或适配器失败上报 SerializeError，不清理、不重试。',
        ),
      ),
    ],
  );
}
