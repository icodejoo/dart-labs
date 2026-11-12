import 'package:ffuzzy/ffuzzy.dart';
import 'package:flutter/material.dart';
import 'demo_data.dart';
import 'demo_kit/demo_kit.dart';
import 'search_page.dart';

/// 当前版本的三个常用工厂入口。
enum CorpusFactory { strings, byKey, byKeys }

/// 工厂构造、对象搜索与 Unicode 高亮工具演示。
class ConstructorsPage extends StatelessWidget {
  /// 创建构造与高亮页面。
  const ConstructorsPage({super.key});

  /// 构建可编辑工厂示例和静态 UTF-16 对照。
  @override
  Widget build(BuildContext context) => DemoPage(
        title: tr(context, 'Constructors & highlights', '构造与高亮'),
        description: tr(
            context,
            'Search strings or objects, and keep Unicode highlights intact.',
            '搜索字符串或对象，正确处理 Unicode 高亮。'),
        sections: [
          DemoSection(
            title: tr(context, 'Build a corpus', '构建语料'),
            code:
                '''final strings = FuzzyCorpus.strings(items, matchPaths: true);
final names = FuzzyCorpus.byKey(contacts, 'name');
final fields = FuzzyCorpus.byKeys(contacts, ['name', 'email', 'company']);
final hits = fields.fuzzy('acme', limit: 3);
// hits.first.matchedKey indexes the configured fields.
strings.dispose(); names.dispose(); fields.dispose();''',
            child: DemoGrid(children: [
              for (final factory in CorpusFactory.values)
                DemoGridItem(
                    child: DemoCard(
                        title: factory.name,
                        description: tr(
                            context,
                            'Edit the query; replay restores the input and corpus.',
                            '修改查询；重放恢复输入和语料。'),
                        child: FactoryDemo(factory: factory))),
            ]),
          ),
          DemoSection(
            title: tr(context, 'Unicode offsets', 'Unicode 偏移'),
            code:
                "const text = 'a😀b中文';\nfinal offsets = fuzzyCodepointToUtf16(text, [0, 1, 2, 3, 4]);\n// [0, 1, 3, 4, 5]\nfinal distance = autoMaxDistance('hello'); // 1",
            child: DemoGrid(children: [
              DemoGridItem(
                  child: DemoCard(
                title: 'fuzzyCodepointToUtf16',
                description: tr(
                    context,
                    'Emoji use two UTF-16 units. Convert complete characters.',
                    'Emoji 占两个 UTF-16 单元，转换时保留完整字符。'),
                replayable: false,
                child: const UnicodeDemo(),
              ))
            ]),
          ),
          DemoSection(
              title: tr(context, 'Alternate keys', '附加键'),
              child: InfoNote(
                  text: tr(
                      context,
                      'Highlight indices belong to the matched key. For byKeys or pinyin, apply them to that key rather than the primary display text. Pinyin is supplied by the host; ffuzzy does not transliterate automatically.',
                      '高亮下标属于命中的键。多字段或拼音命中时应对该键高亮，不应直接用于主显示文本。拼音键由宿主提供，ffuzzy 不自动转写。'))),
        ],
      );
}

/// 每张工厂卡片持有独立的对象语料和输入控制器。
class FactoryDemo extends StatefulWidget {
  /// 创建指定工厂演示。
  const FactoryDemo({super.key, required this.factory});

  /// 所使用的公开工厂。
  final CorpusFactory factory;

  /// 创建工厂演示状态。
  @override
  State<FactoryDemo> createState() => _FactoryDemoState();
}

/// 构造一次语料并在输入改变时同步更新结果。
class _FactoryDemoState extends State<FactoryDemo> {
  /// 字符串工厂的独立语料。
  late final _strings = widget.factory == CorpusFactory.strings
      ? FuzzyCorpus.strings(demoItems, matchPaths: true)
      : null;

  /// 对象工厂的独立语料。
  late final _objects = widget.factory == CorpusFactory.strings
      ? null
      : widget.factory == CorpusFactory.byKey
          ? FuzzyCorpus.byKey(demoContacts, nameField)
          : FuzzyCorpus.byKeys(demoContacts, contactFields);

  /// 稳定的输入控制器。
  late final _query = TextEditingController(
      text: widget.factory == CorpusFactory.strings
          ? 'main'
          : widget.factory == CorpusFactory.byKey
              ? 'alice'
              : 'acme');

  /// 一并释放语料和输入控制器。
  @override
  void dispose() {
    _strings?.dispose();
    _objects?.dispose();
    _query.dispose();
    super.dispose();
  }

  /// 按命中字段展示对象，避免把附加键下标用于主文本。
  @override
  Widget build(BuildContext context) {
    final hits = _objects?.fuzzy(_query.text, limit: resultLimit);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
              controller: _query,
              decoration: InputDecoration(
                  labelText: tr(context, queryEn, queryZh), isDense: true),
              onChanged: (_) => setState(() {})),
          const SizedBox(height: DemoTokens.smallGap),
          if (_strings != null)
            SearchResults(
                result: _strings.fuzzy(_query.text,
                    limit: resultLimit, highlight: true))
          else if (hits!.isEmpty)
            Text(tr(context, emptyEn, emptyZh))
          else
            for (final hit in hits)
              Text(
                  '${hit.raw[nameField]} · ${tr(context, 'Field', '字段')}: ${widget.factory == CorpusFactory.byKey ? nameField : contactFields[hit.matchedKey]}'),
        ]);
  }
}

/// 静态展示 emoji 的码点、UTF-16 偏移和实际高亮。
class UnicodeDemo extends StatelessWidget {
  /// 创建无需重放的工具演示。
  const UnicodeDemo({super.key});

  /// Unicode 演示的完整文本。
  static const text = 'a😀b中文';

  /// 每个完整字符的码点序号。
  static const indices = [0, 1, 2, 3, 4];

  /// 展示转换结果和自动编辑距离阈值。
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text(text),
        Text('${tr(context, 'Codepoints', '码点')}: $indices'),
        Text('UTF-16: ${fuzzyCodepointToUtf16(text, indices)}'),
        const SearchResults(result: [
          FuzzyHit(text, 0, 0, FuzzyKeyKind.original, 0, 0, [1, 3])
        ]),
        Text('autoMaxDistance("hello"): ${autoMaxDistance('hello')}'),
      ]);
}
