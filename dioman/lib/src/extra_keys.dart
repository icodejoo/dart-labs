import 'package:dio/dio.dart';

import 'dioman_plugin.dart';
import 'mock_adapter.dart';

/// `RequestOptions.extra` 里一个键的类别。
enum DiomanExtraKeyKind {
  /// 公开配置键：调用方可写，值是 `DiomanXxxOptions`（键即插件名）。
  config,

  /// 跨插件协议键：多个插件之间的约定，调用方不应写入。
  protocol,

  /// 内部状态键：插件自己在请求上记账，调用方不应读写。
  state,
}

/// 注册表里的一条记录：一个 `extra` 键的归属与含义。
///
/// 只描述接口契约，不暴露读写逻辑。内置键见 [DiomanExtraKeys.builtIn]；
/// 自定义插件可用 [DiomanExtraKeys.register] 登记自己的键。
///
/// ```dart
/// const myKey = DiomanExtraKey(
///   key: 'my:plugin:startedAt',
///   owner: 'my:plugin',
///   kind: DiomanExtraKeyKind.state,
///   valueType: 'int',
///   description: '请求开始的毫秒时间戳',
/// );
/// ```
class DiomanExtraKey {
  /// 创建一条登记记录。
  ///
  /// - [key]：`extra` 中的键字符串。
  /// - [owner]：所属插件的 [DiomanPlugin.name]（传输层组件用类名）。
  /// - [kind]：键的类别。
  /// - [valueType]：值的类型说明（给人看的字符串，如 `int`、`DiomanCacheOptions`）。
  /// - [description]：一句话用途说明。
  const DiomanExtraKey({
    required this.key,
    required this.owner,
    required this.kind,
    required this.valueType,
    required this.description,
  });

  /// 公开配置键的简写：键即插件名 [name]，类别为 [DiomanExtraKeyKind.config]。
  const DiomanExtraKey.config(String name, this.valueType, this.description)
      : key = name,
        owner = name,
        kind = DiomanExtraKeyKind.config;

  /// 内部状态键的简写：类别为 [DiomanExtraKeyKind.state]。
  const DiomanExtraKey.state(
      this.key, this.owner, this.valueType, this.description)
      : kind = DiomanExtraKeyKind.state;

  /// `extra` 中的键字符串。
  final String key;

  /// 所属插件的 [DiomanPlugin.name]；不是插件的传输层组件用其类名，见
  /// [DiomanExtraKeys.mockAdapterOwner]。
  final String owner;

  /// 键的类别。
  final DiomanExtraKeyKind kind;

  /// 值的类型说明。
  final String valueType;

  /// 一句话用途说明。
  final String description;

  @override
  String toString() => 'DiomanExtraKey($key, $owner, ${kind.name})';
}

/// 一个被多个同名插件实例共享的状态键，见 [DiomanExtraKeys.findSharedState]。
class DiomanSharedStateKey {
  /// 创建诊断结果；一般由 [DiomanExtraKeys.findSharedState] 返回。
  const DiomanSharedStateKey(this.key, this.count);

  /// 被共享的状态键。
  final DiomanExtraKey key;

  /// 共享该键的插件实例数（至少为 2）。
  final int count;

  @override
  String toString() => '${key.key} x$count';
}

/// `extra` 键注册表：集中登记每个键的所属插件、类别与值类型，并诊断重复
/// 实例共享同名状态键的问题。
///
/// 内置键是 `const` 清单，运行时行为与既有键名完全不变；源码里的键常量与本表的
/// 一致性由 `test/integration/extra_keys_integration_test.dart` 守护（新增键忘记登记会失败）。
///
/// ```dart
/// // 查询
/// final k = DiomanExtraKeys.lookup('dioman:cache:key');
/// print('${k?.owner} ${k?.valueType}');
///
/// // 诊断：同一个 Dio 上手动装了两个 DiomanCache
/// final dup = DiomanExtraKeys.findSharedState(dio.interceptors);
/// ```
abstract final class DiomanExtraKeys {
  /// [DiomanMockAdapter] 登记键时用的 owner：它是传输层 adapter 而非插件，没有
  /// [DiomanPlugin.name]，所以用类名。
  static const mockAdapterOwner = 'DiomanMockAdapter';

  /// 内置插件（及 [DiomanMockAdapter]）的全部 `extra` 键（不含自定义登记）。
  static const List<DiomanExtraKey> builtIn = [
    // ── 公开配置键：extra[插件名] = DiomanXxxOptions ──
    DiomanExtraKey.config('dioman:auth', 'DiomanAuthOptions', '单请求认证覆盖'),
    DiomanExtraKey.config('dioman:breaker', 'DiomanBreakerOptions', '单请求熔断覆盖'),
    DiomanExtraKey.config('dioman:cache', 'DiomanCacheOptions', '单请求缓存覆盖'),
    DiomanExtraKey.config('dioman:filter', 'DiomanFilterOptions', '单请求参数过滤覆盖'),
    DiomanExtraKey.config('dioman:qid', 'DiomanKeyOptions', '单请求键生成覆盖'),
    DiomanExtraKey.config('dioman:loading', 'DiomanLoadingOptions', '单请求加载态覆盖'),
    DiomanExtraKey.config('dioman:log', 'DiomanLogOptions', '单请求日志覆盖'),
    // 传输层 adapter 不是插件，owner 登记为类名；值也可以是 false（跳过 mock）。
    DiomanExtraKey(
      key: DiomanMockAdapter.extraKey,
      owner: mockAdapterOwner,
      kind: DiomanExtraKeyKind.config,
      valueType: 'DiomanMockOptions',
      description: '单请求 Mock 覆盖（传输层 adapter）',
    ),
    DiomanExtraKey.config(
        'dioman:normalize', 'DiomanNormalizeOptions', '单请求规范化覆盖'),
    DiomanExtraKey.config(
        'dioman:offline', 'DiomanOfflineOptions', '单请求离线排队覆盖'),
    DiomanExtraKey.config('dioman:repath', 'DiomanRepathOptions', '单请求路径替换覆盖'),
    DiomanExtraKey.config('dioman:retry', 'DiomanRetryOptions', '单请求重试覆盖'),
    DiomanExtraKey.config('dioman:share', 'DiomanShareOptions', '单请求去重覆盖'),
    DiomanExtraKey.config('dioman:timeout', 'DiomanTimeoutOptions', '单请求超时覆盖'),

    // ── 跨插件协议键 ──
    DiomanExtraKey(
      key: 'dioman:key',
      owner: 'dioman:qid',
      kind: DiomanExtraKeyKind.protocol,
      valueType: 'String',
      description: 'key 写入的请求键，cache/share 读取',
    ),
    DiomanExtraKey(
      key: 'dioman:claims',
      owner: 'dioman:share',
      kind: DiomanExtraKeyKind.protocol,
      valueType: 'RequestClaims',
      description: '认领登记簿：auth/retry 认领，share/cancel 据此推迟结算',
    ),
    DiomanExtraKey(
      key: 'dioman:share:joined',
      owner: 'dioman:share',
      kind: DiomanExtraKeyKind.protocol,
      valueType: 'bool',
      description: '标记跟随者/落败者，auth/retry 见到后不再自行恢复',
    ),

    // ── 内部状态键 ──
    DiomanExtraKey.state(
        'dioman:notify:sent', 'dioman:notify', 'bool', '同一逻辑请求已发送通知'),
    DiomanExtraKey.state(
        'dioman:auth:decision', 'dioman:auth', 'bool', '本次请求是否受保护的缓存判定'),
    DiomanExtraKey.state(
        'dioman:auth:protected', 'dioman:auth', 'bool', '请求已按受保护处理'),
    DiomanExtraKey.state(
        'dioman:auth:refreshed', 'dioman:auth', 'bool', '本次请求已刷新过令牌，防止重复刷新'),
    DiomanExtraKey.state(
        'dioman:auth:denied', 'dioman:auth', 'bool', '请求被认证拒绝（走错误链）'),
    DiomanExtraKey.state(
        'dioman:auth:tokenUsed', 'dioman:auth', 'String?', '注入请求的原始令牌'),
    DiomanExtraKey.state(
        'dioman:breaker:key', 'dioman:breaker', 'Record', '熔断放行凭据（桶、窗口、探测标记）'),
    DiomanExtraKey.state(
        'dioman:cache:key', 'dioman:cache', 'String', '本次请求的缓存键'),
    DiomanExtraKey.state(
        'dioman:cache:ttl', 'dioman:cache', 'int', '本次请求解析出的 TTL（毫秒）'),
    DiomanExtraKey.state(
        'dioman:cache:generation', 'dioman:cache', 'int', '请求发起时的清理代次'),
    DiomanExtraKey.state('dioman:cache:policy', 'dioman:cache',
        'DiomanCachePolicy', '本次请求的缓存策略'),
    DiomanExtraKey.state(
        'dioman:cancel:token', 'dioman:cancel', 'CancelToken', 'cancel 注入的令牌'),
    DiomanExtraKey.state(
        'dioman:loading:bracketed', 'dioman:loading', 'bool', '请求已打开加载括号'),
    DiomanExtraKey.state('dioman:loading:delayClose', 'dioman:loading',
        'Duration', '本次请求的延迟关闭时长'),
    DiomanExtraKey.state(
        'dioman:retry:callbackFailed', 'dioman:retry', 'bool', '重试回调抛过异常'),
    DiomanExtraKey.state(
        'dioman:share:entry', 'dioman:share', 'Object', '请求所属的在途条目'),
    DiomanExtraKey.state(
        'dioman:share:seq', 'dioman:share', 'int', '请求在条目中的序号'),
    DiomanExtraKey.state('dioman:share:policy', 'dioman:share',
        'DiomanSharePolicy', '本次请求的去重策略'),
    DiomanExtraKey.state(
        'dioman:share:retriesLeft', 'dioman:share', 'int', 'retry 策略剩余次数'),
    DiomanExtraKey.state(
        'dioman:share:interval', 'dioman:share', 'Duration', 'retry 策略重试间隔'),
  ];

  /// 自定义插件登记的键，按登记顺序。
  static final List<DiomanExtraKey> _custom = [];

  /// 内置键 + 自定义登记键，按登记顺序（只读视图）。
  static List<DiomanExtraKey> get all =>
      List.unmodifiable([...builtIn, ..._custom]);

  /// 按键字符串查询登记记录，未登记返回 null。
  static DiomanExtraKey? lookup(String key) {
    for (final k in all) {
      if (k.key == key) return k;
    }
    return null;
  }

  /// 返回指定类别 [kind] 的全部登记记录。
  static List<DiomanExtraKey> ofKind(DiomanExtraKeyKind kind) => [
        for (final k in all)
          if (k.kind == kind) k
      ];

  /// 返回归属插件 [owner]（[DiomanPlugin.name]）的全部登记记录。
  static List<DiomanExtraKey> ofOwner(String owner) => [
        for (final k in all)
          if (k.owner == owner) k
      ];

  /// 为自定义插件登记一个键。
  ///
  /// 键已存在（含内置键）时抛 [StateError]，用来在开发期发现键名冲突。
  /// 参数：[key] 要登记的记录。无返回值。
  static void register(DiomanExtraKey key) {
    final existing = lookup(key.key);
    if (existing != null) {
      throw StateError(
        "extra key '${key.key}' is already registered by '${existing.owner}'; "
        "cannot register it again for '${key.owner}'.",
      );
    }
    _custom.add(key);
  }

  /// 移除自定义登记的键；内置键不可移除。
  ///
  /// 参数：[key] 键字符串。返回：确实移除了自定义键时为 true。
  static bool unregister(String key) {
    final before = _custom.length;
    _custom.removeWhere((k) => k.key == key);
    return _custom.length != before;
  }

  /// 诊断：找出被多个同名插件实例共享的状态键。
  ///
  /// 同名实例读写同一批 `extra` 状态键，会互相覆盖对方在请求上的记账（典型
  /// 场景：绕过 [Dioman.install] 手动往 `dio.interceptors` 里加了两次同一个
  /// 插件）。只检查有登记状态键的插件；没有状态键的重复实例（如两个 log）不算。
  ///
  /// 参数：[interceptors] 待检查的拦截器，如 `dio.interceptors`。
  /// 返回：冲突列表，无冲突为空。
  ///
  /// ```dart
  /// final dup = DiomanExtraKeys.findSharedState(dio.interceptors);
  /// for (final d in dup) print('${d.key.key} 被 ${d.count} 个实例共享');
  /// ```
  static List<DiomanSharedStateKey> findSharedState(
      Iterable<Interceptor> interceptors) {
    final counts = <String, int>{};
    for (final i in interceptors) {
      if (i is DiomanPlugin) counts[i.name] = (counts[i.name] ?? 0) + 1;
    }
    return [
      for (final k in ofKind(DiomanExtraKeyKind.state))
        if ((counts[k.owner] ?? 0) > 1)
          DiomanSharedStateKey(k, counts[k.owner]!),
    ];
  }

  /// 开发期断言：存在共享状态键的重复实例时抛 [AssertionError]。
  ///
  /// 只在启用 assert 时检查（debug/测试），release 下是空操作。
  /// 参数：[interceptors] 待检查的拦截器。无返回值。
  static void assertNoSharedState(Iterable<Interceptor> interceptors) {
    assert(() {
      final dup = findSharedState(interceptors);
      if (dup.isNotEmpty) {
        throw AssertionError(
          'duplicate plugin instances share extra state keys: '
          '${dup.join(', ')}. Install each plugin only once.',
        );
      }
      return true;
    }());
  }

  /// 把内置键渲染成 Markdown 表格，用于同步 docs/design/architecture.md。
  ///
  /// 返回：带表头的 Markdown 表格（不含自定义登记键）。
  static String toMarkdown() {
    const labels = {
      DiomanExtraKeyKind.config: '公开配置',
      DiomanExtraKeyKind.protocol: '跨插件协议',
      DiomanExtraKeyKind.state: '内部状态',
    };
    final b = StringBuffer()
      ..writeln('| 键 | 所属插件 | 类别 | 值类型 | 说明 |')
      ..writeln('|---|---|---|---|---|');
    for (final k in builtIn) {
      b.writeln('| `${k.key}` | `${k.owner}` | ${labels[k.kind]} | '
          '`${k.valueType}` | ${k.description} |');
    }
    return b.toString();
  }
}
