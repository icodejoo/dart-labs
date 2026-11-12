import 'dart:async';
import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';

/// 示例独占容器，避免清理用户应用的默认缓存。
const demoContainer = 'cacheman_demo_kit';

/// 全部示例共用的逻辑键。
const demoKey = 'message';

/// 示例输入与编码的稳定数据值。
const demoValue = 'Ada';

/// 列表与批量操作的逻辑键。
const demoKeys = ['first', 'second'];

/// 快捷访问器的毫秒 TTL。
const accessorTtl = 60000;

/// 页头和导航共用的项目名称。
const demoProject = 'cacheman';

/// 包的公开文档入口。
const demoPubUrl = 'https://pub.dev/packages/cacheman';

/// 结果映射中的值字段。
const demoValueField = 'value';

/// 结果映射中的键字段。
const demoKeysField = 'keys';

/// 结果映射中的错误字段。
const demoErrorsField = 'errors';

/// 结果映射中的条目保留字段。
const demoRetainedField = 'retained';

/// 跨页面复用的双语文案，避免相同标签重复维护。
abstract final class DemoCopy {
  /// 基础读写的双语文案。
  static const basic = (en: 'Basic operations', zh: '基础读写');

  /// 过期与续期的双语文案。
  static const ttl = (en: 'TTL & expiry', zh: '过期与续期');

  /// 批量与快捷访问的双语文案。
  static const batch = (en: 'Batch & accessors', zh: '批量与快捷访问');

  /// 命名空间的双语文案。
  static const namespace = (en: 'Namespaces', zh: '命名空间');

  /// 扩展类型与快照的双语文案。
  static const advanced = (en: 'Jsonx & debug', zh: '扩展类型与快照');

  /// 分层存储的双语文案。
  static const async = (en: 'Layered storage', zh: '分层存储');

  /// 共享监听的双语文案。
  static const hub = (en: 'Shared Hub', zh: '共享监听');

  /// 类型与错误的双语文案。
  static const types = (en: 'Types & errors', zh: '类型与错误');

  /// 正在初始化…的双语文案。
  static const initializing = (en: 'Initializing…', zh: '正在初始化…');

  /// 初始化失败，请重放重试。的双语文案。
  static const initializationFailed = (
    en: 'Initialization failed. Replay to retry.',
    zh: '初始化失败，请重放重试。',
  );

  /// 读取的双语文案。
  static const read = (en: 'Read', zh: '读取');

  /// 清空的双语文案。
  static const erase = (en: 'Erase', zh: '清空');
}

/// 创建并初始化专用作用域；重放只清理该卡片的数据。
Future<Cacheman> demoCache(String scope, {CachemanOptions? options}) async {
  final cache = Cacheman(
    container: demoContainer,
    options: options ?? CachemanOptions(namespace: scope),
  );
  await cache.ensureInitialized();
  cache.erase();
  return cache;
}

/// 一个动作的双语标题与可等待操作。
class DemoAction {
  /// 创建操作，输入值由所在卡片提供。
  const DemoAction(this.en, this.zh, this.run);

  /// 英文按钮标题。
  final String en;

  /// 中文按钮标题。
  final String zh;

  /// 返回本次操作的技术数据。
  final FutureOr<Object?> Function(String input) run;
}

/// 一次卡片挂载持有的缓存、操作与清理回调。
class DemoSession {
  /// 创建互不共享可变状态的操作会话。
  DemoSession(this.actions, {this.dispose});

  /// 卡片提供的操作。
  final List<DemoAction> actions;

  /// 取消监听并提交待落盘数据的回调。
  final VoidCallback? dispose;
}

/// 提供初始化、结果、错误反馈与异步操作隔离的演示主体。
class ActionDemo extends StatefulWidget {
  /// 创建会话；重挂载会重新执行初始化。
  const ActionDemo({super.key, required this.create, this.editable = false});

  /// 每次挂载创建一份新会话。
  final Future<DemoSession> Function() create;

  /// 是否提供值输入框。
  final bool editable;

  /// 创建局部操作状态。
  @override
  State<ActionDemo> createState() => _ActionDemoState();
}

/// 管理单张卡片的加载、操作与结果。
class _ActionDemoState extends State<ActionDemo> {
  /// 输入框控制器。
  final _input = TextEditingController(text: demoValue);

  /// 初始化完成的会话。
  DemoSession? _session;

  /// 当前可见技术数据。
  Object? _result;

  /// 是否已有结果，区分尚未操作和读取返回 null。
  bool _hasResult = false;

  /// 操作是否仍在等待。
  bool _busy = false;

  /// 是否发生初始化或执行失败。
  bool _failed = false;

  /// 启动局部会话。
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// 初始化结束后更新界面；过期会话立即清理。
  Future<void> _initialize() async {
    try {
      final session = await widget.create();
      if (!mounted) {
        session.dispose?.call();
        return;
      }
      setState(() => _session = session);
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _result = error.runtimeType;
        });
      }
    }
  }

  /// 执行同步或异步操作，并阻止等待期间重复点击。
  Future<void> _run(DemoAction action) async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final result = await action.run(_input.text);
      if (mounted) {
        setState(() {
          _result = result;
          _hasResult = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _result = error.runtimeType;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 清理输入、监听与待落盘数据。
  @override
  void dispose() {
    _session?.dispose?.call();
    _input.dispose();
    super.dispose();
  }

  /// 构建紧凑的操作区，所有运行反馈跟随当前语言。
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (widget.editable) ...[
        TextField(
          controller: _input,
          decoration: InputDecoration(
            labelText: tr(context, 'Value', '值'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: DemoTokens.smallGap),
      ],
      if (_session == null && !_failed)
        Text(tr(context, DemoCopy.initializing.en, DemoCopy.initializing.zh)),
      Wrap(
        spacing: DemoTokens.smallGap,
        runSpacing: DemoTokens.smallGap,
        children: [
          for (final action in _session?.actions ?? <DemoAction>[])
            FilledButton.tonal(
              onPressed: _busy ? null : () => _run(action),
              child: Text(tr(context, action.en, action.zh)),
            ),
        ],
      ),
      const SizedBox(height: DemoTokens.smallGap),
      if (_busy) Text(tr(context, 'Loading…', '正在加载…')),
      Text(
        _failed
            ? tr(context, 'Operation failed', '操作失败')
            : tr(context, 'Result', '结果'),
        style: Theme.of(context).textTheme.labelMedium,
      ),
      Text(
        _hasResult || _failed
            ? '$_result'
            : tr(context, 'Choose an action above.', '点击上方按钮开始。'),
        softWrap: true,
      ),
    ],
  );
}

/// 将动作会话包装为可重放、独立复位的网格卡片。
DemoGridItem actionCard(
  BuildContext context, {
  required String en,
  required String zh,
  required String descriptionEn,
  required String descriptionZh,
  required Future<DemoSession> Function() create,
  bool editable = false,
}) => DemoGridItem(
  child: DemoCard(
    title: tr(context, en, zh),
    description: tr(context, descriptionEn, descriptionZh),
    child: ActionDemo(create: create, editable: editable),
  ),
);
