import 'dart:async';
import 'package:ffuzzy/ffuzzy.dart';
import 'package:flutter/material.dart';
import 'demo_data.dart';
import 'demo_kit/demo_kit.dart';

/// 演示初始语料，重放时重新创建。
const lifecycleItems = ['alpha', 'beta', 'gamma'];

/// 插入或刷新演示使用的新语料。
const addedItems = ['delta', 'epsilon'];

/// 宿主计算的拼音键。
const pinyinKey = 'zhongwen';

/// 拼音键对应的原始条目。
const keyedItem = '中文搜索引擎';

/// 当前版本的可变语料操作。
enum CorpusAction {
  add,
  addAll,
  addKey,
  update,
  removeAt,
  removeWhere,
  refresh,
  clear,
  dispose,
  asyncBuild,
  asyncAddAll,
  asyncDispose
}

/// 语料生命周期与异步方法演示。
class LifecyclePage extends StatelessWidget {
  /// 创建生命周期页面。
  const LifecyclePage({super.key});

  /// 构建每个操作的独立卡片。
  @override
  Widget build(BuildContext context) => DemoPage(
        title: tr(context, 'Corpus lifecycle', '语料生命周期'),
        description: tr(
            context,
            'Apply an operation, inspect the result, then replay to reset.',
            '执行操作、查看结果，再用重放恢复初始语料。'),
        sections: [
          DemoSection(
            title: tr(context, 'Mutations & async lifecycle', '变更与异步生命周期'),
            code:
                '''final corpus = FuzzyCorpus.strings(['alpha', 'beta', 'gamma']);
corpus.add('delta');
corpus.addAll(['delta', 'epsilon']);
corpus.addKey('中文搜索引擎', [FuzzyKey.kind('zhongwen', FuzzyKeyKind.pinyin)]);
corpus.update(0, 'delta');
corpus.removeAt(0);
corpus.removeWhere((item) => item.startsWith('a'));
corpus.refresh(['delta', 'epsilon']);
corpus.clear();
corpus.dispose();

final built = await FuzzyCorpus.asyncBuild(['alpha', 'beta', 'gamma'], stringOf: (s) => s);
await built.asyncAddAll(['delta', 'epsilon']);
await built.asyncDispose();''',
            child: DemoGrid(children: [
              for (final action in CorpusAction.values)
                DemoGridItem(
                    child: DemoCard(
                  title: action.name,
                  description: tr(
                      context,
                      'An isolated corpus; replay restores its initial state.',
                      '使用独立语料，重放恢复初始状态。'),
                  child: CorpusDemo(action: action),
                )),
            ]),
          ),
          DemoSection(
              title: tr(context, 'Safe ownership', '安全管理资源'),
              child: InfoNote(
                  text: tr(
                      context,
                      'Await an active search before mutating the corpus. asyncDispose waits for in-flight work. Updates and removals rebuild the index in O(n); this page makes no performance promises.',
                      '变更语料前应等待在途搜索完成。asyncDispose 会等待异步任务结束。更新和删除需要 O(n) 重建索引，本页不提供性能承诺。'))),
        ],
      );
}

/// 具有独立语料与资源回收逻辑的操作主体。
class CorpusDemo extends StatefulWidget {
  /// 创建操作演示；benchmark 为构建压测显式使用较大语料。
  const CorpusDemo({super.key, required this.action, this.benchmark = false});

  /// 要调用的 API。
  final CorpusAction action;

  /// 是否保留开发期的三千条构建计时。
  final bool benchmark;

  /// 创建生命周期演示状态。
  @override
  State<CorpusDemo> createState() => _CorpusDemoState();
}

/// 管理一次操作与重放前的资源寿命。
class _CorpusDemoState extends State<CorpusDemo> {
  /// 演示持有的语料；异步构建前为空。
  late FuzzyCorpus<String>? _corpus = widget.action == CorpusAction.asyncBuild
      ? null
      : FuzzyCorpus.strings(lifecycleItems);

  /// 操作是否在途。
  bool _busy = false;

  /// 是否执行完成。
  bool _done = false;

  /// 是否执行失败。
  bool _failed = false;

  /// 释放后的语料不再读取长度。
  bool _released = false;

  /// 用于说明键匹配或删除数量的观察值。
  int? _observed;

  /// 仅本次构建的实际耗时，不预填历史数据。
  int? _elapsed;

  /// 等待在途异步工作后回收语料，允许构建晚于卸载完成。
  @override
  void dispose() {
    if (!_released && _corpus != null) unawaited(_corpus!.asyncDispose());
    super.dispose();
  }

  /// 调用当前公开 API，并为晚到的构建结果立即释放资源。
  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    final watch = Stopwatch()..start();
    try {
      final corpus = _corpus;
      switch (widget.action) {
        case CorpusAction.add:
          corpus!.add(addedItems.first);
        case CorpusAction.addAll:
          corpus!.addAll(addedItems);
        case CorpusAction.addKey:
          corpus!.addKey(
              keyedItem, [FuzzyKey.kind(pinyinKey, FuzzyKeyKind.pinyin)]);
          _observed = corpus.fuzzy(pinyinKey).first.matchedKindCode;
        case CorpusAction.update:
          corpus!.update(0, addedItems.first);
        case CorpusAction.removeAt:
          corpus!.removeAt(0);
        case CorpusAction.removeWhere:
          _observed = corpus!.removeWhere((item) => item.startsWith('a'));
        case CorpusAction.refresh:
          corpus!.refresh(addedItems);
        case CorpusAction.clear:
          corpus!.clear();
        case CorpusAction.dispose:
          corpus!.dispose();
          _released = true;
        case CorpusAction.asyncBuild:
          final built = await FuzzyCorpus.asyncBuild(
              widget.benchmark
                  ? List.generate(benchmarkSize, (index) => 'item_$index')
                  : lifecycleItems,
              stringOf: (item) => item);
          if (!mounted) {
            await built.asyncDispose();
            return;
          }
          _corpus = built;
        case CorpusAction.asyncAddAll:
          await corpus!.asyncAddAll(addedItems);
        case CorpusAction.asyncDispose:
          await corpus!.asyncDispose();
          _released = true;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
        _elapsed = watch.elapsedMicroseconds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _failed = true;
      });
    } finally {
      watch.stop();
    }
  }

  /// 显示操作按钮与当前语料快照。
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton(
              onPressed: _busy || _done ? null : _apply,
              child: Text(_busy
                  ? tr(context, 'Working…', '执行中…')
                  : _done
                      ? tr(context, 'Completed', '已完成')
                      : tr(context, 'Run', '执行'))),
          const SizedBox(height: DemoTokens.smallGap),
          if (_failed)
            Text(tr(
                context, 'Operation failed. Replay to retry.', '操作失败，可重放重试。')),
          if (_busy)
            Text(tr(context, 'Waiting for the engine…', '等待引擎完成…'))
          else if (_released)
            Text(tr(context, 'Disposed; further use throws StateError.',
                '已释放，继续访问会抛出 StateError。'))
          else ...[
            Text('${tr(context, 'Length', '条目数')}: ${_corpus?.length ?? 0}'),
            if (!widget.benchmark && _corpus != null)
              Text(_corpus!.fuzzyRaws('').join(' · ')),
          ],
          if (_observed != null)
            Text(
                '${widget.action == CorpusAction.addKey ? tr(context, 'Matched kind code', '命中键类型编号') : tr(context, 'Removed', '删除数')}: $_observed'),
          if (widget.benchmark && _elapsed != null)
            Text(
                '${tr(context, 'Build time', '构建耗时')}: ${(_elapsed! / 1000).toStringAsFixed(2)} ms'),
        ],
      );
}

/// 保留原示例中的三千条异步构建计时，归入压测导航。
class BuildBenchmarkPage extends StatelessWidget {
  /// 创建压测页面，默认不执行计时。
  const BuildBenchmarkPage({super.key});

  /// 构建按需运行的基准与平台解释。
  @override
  Widget build(BuildContext context) => DemoPage(
        title: tr(context, 'Async build benchmark', '异步构建基准'),
        description: tr(
            context,
            'Measure this device with $benchmarkSize generated items.',
            '使用 $benchmarkSize 条生成数据测量当前设备。'),
        sections: [
          DemoSection(
            title: tr(context, 'On-demand measurement', '按需测量'),
            code: r'''final watch = Stopwatch()..start();
final corpus = await FuzzyCorpus.asyncBuild(
  List.generate(3000, (i) => 'item_$i'), stringOf: (s) => s);
watch.stop();
await corpus.asyncDispose();''',
            child: DemoGrid(children: [
              DemoGridItem(
                  child: DemoCard(
                title: 'asyncBuild · $benchmarkSize',
                description: tr(
                    context,
                    'One fresh corpus per replay; includes generated input.',
                    '每次重放使用新语料；耗时包含数据生成。'),
                child: const CorpusDemo(
                    action: CorpusAction.asyncBuild, benchmark: true),
              ))
            ]),
          ),
          DemoSection(
              title: tr(context, 'Interpretation', '如何解读'),
              child: InfoNote(
                  text: tr(
                      context,
                      'A single local sample, not a cross-platform comparison. Web runs WASM on the main thread; native asyncBuild uses an isolate. The package test/bench_native_test.dart retains the native corpus-vs-Dart benchmark.',
                      '这是单次本机样本，不能用于跨平台对比。Web 在主线程执行 WASM，原生 asyncBuild 使用 isolate。包内 test/bench_native_test.dart 保留原生语料与 Dart 的基准对照。'))),
        ],
      );
}
