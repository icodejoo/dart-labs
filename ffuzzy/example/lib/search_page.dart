import 'dart:async';
import 'package:ffuzzy/ffuzzy.dart';
import 'package:flutter/material.dart';
import 'demo_data.dart';
import 'demo_kit/demo_kit.dart';
import 'search_specs.dart';

/// 合并同步、原始对象与异步搜索的交互目录。
class SearchPage extends StatelessWidget {
  /// 创建搜索页面。
  const SearchPage({super.key});

  /// 构建真实搜索卡片与跨整行的代码。
  @override
  Widget build(BuildContext context) => DemoPage(
        title: tr(context, 'Find your match', '找到你想要的结果'),
        description: tr(context, 'Edit any query and compare matching modes.',
            '编辑任意查询，对比不同匹配方式。'),
        sections: [
          DemoSection(
            title: tr(context, 'Live search', '实时搜索'),
            code:
                "final corpus = FuzzyCorpus.strings(items, matchPaths: true);\nconst resultLimit = 3;\n\n${searchSpecs.map((spec) => spec.code).join('\n\n')}\n\nawait corpus.asyncDispose();",
            child: DemoGrid(children: [
              for (final spec in searchSpecs)
                DemoGridItem(
                    child: DemoCard(
                  title: spec.name,
                  description: tr(context, spec.en, spec.zh),
                  child: SearchDemo(spec: spec),
                )),
            ]),
          ),
          DemoSection(
            title: tr(context, 'Execution & limits', '执行方式与限制'),
            child: InfoNote(
                text: tr(
                    context,
                    'Native async searches use worker isolates. Web async yields a microtask and runs WASM on the main thread. Approximate queries allow at most 64 codepoints; maxDistance is 0–10 (automatic when omitted). Raws skips highlight indices.',
                    '原生异步搜索使用后台 isolate；Web 异步让出微任务后仍在主线程执行 WASM。近似查询最多 64 个码点，maxDistance 为 0–10，省略时自动选择。Raws 不计算高亮下标。')),
          ),
        ],
      );
}

/// 控制每张卡片使用的结果与执行方式。
enum SearchVariant { hits, raws, asyncHits, asyncRaws }

/// 拥有独立语料和输入状态的搜索主体，重放会恢复初始查询。
class SearchDemo extends StatefulWidget {
  /// 创建某个搜索方法的演示。
  const SearchDemo({super.key, required this.spec});

  /// 当前公开方法配置。
  final SearchSpec spec;

  /// 创建本卡片的查询状态。
  @override
  State<SearchDemo> createState() => _SearchDemoState();
}

/// 缓存搜索结果并丢弃已卸载或过期的异步响应。
class _SearchDemoState extends State<SearchDemo> {
  /// 本卡片的驻留语料。
  final _corpus = FuzzyCorpus.strings(demoItems, matchPaths: true);

  /// 查询输入控制器，只在挂载时创建一次。
  late final _query = TextEditingController(text: widget.spec.query);

  /// 当前变体。
  SearchVariant _variant = SearchVariant.hits;

  /// 最近一次结果。
  late Object _result = widget.spec.hits(_corpus, _query.text);

  /// 是否正在等待异步结果。
  bool _busy = false;

  /// 最近一次调用是否失败。
  bool _failed = false;

  /// 异步请求代次，用于忽略过时响应。
  int _request = 0;

  /// 释放输入控制器并等待在途查询结束后释放语料。
  @override
  void dispose() {
    _query.dispose();
    unawaited(_corpus.asyncDispose());
    super.dispose();
  }

  /// 执行所选 API，所有异步入口都有完成、错误和卸载处理。
  Future<void> _run() async {
    final request = ++_request;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = switch (_variant) {
        SearchVariant.hits => widget.spec.hits(_corpus, _query.text),
        SearchVariant.raws => widget.spec.raws!(_corpus, _query.text),
        SearchVariant.asyncHits =>
          await widget.spec.asyncHits(_corpus, _query.text),
        SearchVariant.asyncRaws =>
          await widget.spec.asyncRaws!(_corpus, _query.text),
      };
      if (!mounted || request != _request) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() {
        _failed = true;
        _busy = false;
      });
    }
  }

  /// 构建查询、变体切换和紧凑结果。
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _query,
            decoration: InputDecoration(
                labelText: tr(context, queryEn, queryZh), isDense: true),
            onChanged: (_) => _run(),
          ),
          const SizedBox(height: DemoTokens.smallGap),
          DropdownButtonFormField<SearchVariant>(
            initialValue: _variant,
            isExpanded: true,
            decoration: InputDecoration(
                labelText: tr(context, 'API variant', 'API 变体'), isDense: true),
            items: [
              for (final variant in SearchVariant.values)
                if (switch (variant) {
                  SearchVariant.raws => widget.spec.raws != null,
                  SearchVariant.asyncRaws => widget.spec.asyncRaws != null,
                  _ => true,
                })
                  DropdownMenuItem(
                      value: variant,
                      child: Text(switch (variant) {
                        SearchVariant.hits => tr(context, 'Hits', '命中详情'),
                        SearchVariant.raws =>
                          tr(context, 'Raw objects', '原始对象'),
                        SearchVariant.asyncHits =>
                          tr(context, 'Async hits', '异步命中'),
                        SearchVariant.asyncRaws =>
                          tr(context, 'Async raw objects', '异步原始对象'),
                      })),
            ],
            onChanged: (value) {
              if (value != null) {
                _variant = value;
                _run();
              }
            },
          ),
          const SizedBox(height: DemoTokens.smallGap),
          if (_busy)
            Text(tr(context, 'Searching…', '搜索中…'))
          else if (_failed)
            Text(tr(context, 'Search failed. Check query limits and replay.',
                '搜索失败，请检查查询限制后重放。'))
          else
            SearchResults(result: _result),
        ],
      );
}

/// 将当前公开 API 的三类结果渲染为双语列表。
class SearchResults extends StatelessWidget {
  /// 创建结果展示。
  const SearchResults({super.key, required this.result});

  /// 命中列表、原始对象列表或双路结果。
  final Object result;

  /// 构建结果；高亮下标先转换到 UTF-16 再应用到字符。
  @override
  Widget build(BuildContext context) {
    if (result case FuzzyDualResult<String> dual) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('fuzzy'),
        SearchResults(result: dual.fuzzy),
        const SizedBox(height: DemoTokens.tinyGap),
        const Text('approx'),
        SearchResults(result: dual.approx),
      ]);
    }
    final hits = result is List<FuzzyHit<String>>
        ? result as List<FuzzyHit<String>>
        : null;
    final texts =
        hits?.map((hit) => hit.raw).toList() ?? result as List<String>;
    if (texts.isEmpty) return Text(tr(context, emptyEn, emptyZh));
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var index = 0; index < texts.length; index++) ...[
        Text.rich(TextSpan(
            children: _highlight(texts[index],
                hits == null ? const [] : hits[index].indices, scheme))),
        if (hits != null)
          Text('${tr(context, 'Score', '分数')}: ${hits[index].score}',
              style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }
}

/// 按完整 Unicode 字符生成高亮，避免 emoji 代理对被截断。
List<InlineSpan> _highlight(
    String text, List<int> indices, ColorScheme scheme) {
  final offsets = fuzzyCodepointToUtf16(text, indices).toSet();
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    spans.add(TextSpan(
        text: character,
        style: offsets.contains(offset)
            ? TextStyle(
                color: scheme.onPrimaryContainer,
                backgroundColor: scheme.primaryContainer,
                fontWeight: FontWeight.bold)
            : null));
    offset += character.length;
  }
  return spans;
}
