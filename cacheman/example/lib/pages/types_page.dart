import 'package:cacheman/cacheman.dart';
import 'package:flutter/material.dart';

/// Business value without automatic JSON serialization. / 不自动序列化的业务值。
class _Profile {
  const _Profile(this.name);

  /// Display name. / 显示名称。
  final String name;
}

/// Adapter/default/error demonstration. / 适配器、默认值、错误演示。
class TypesPage extends StatefulWidget {
  /// Example / 示例：`const TypesPage()`.
  const TypesPage({super.key});
  @override
  State<TypesPage> createState() => _TypesPageState();
}

/// Owns the demo cache and visible classified error log. / 持有演示缓存及分类错误日志。
class _TypesPageState extends State<TypesPage> {
  /// Stable logical keys. / 稳定的逻辑键。
  static const _namesKey = 'names',
      _profileKey = 'profile',
      _numberKey = 'number';

  /// JSON field and shared demonstration value. / JSON 字段及共用演示值。
  static const _nameField = 'name', _demoName = 'Ada';

  /// Explicit JSON conversion for a business value. / 业务值的显式 JSON 转换。
  static final _profiles = ValueAdapter<_Profile>(
    toJson: (p) => {_nameField: p.name},
    fromJson: (j) =>
        _Profile((j as Map<String, dynamic>)[_nameField] as String),
  );

  /// Visible results and error causes. / 可见结果与原异常。
  final _lines = <String>[];

  /// Cache with structured reporting, separate from other demo pages.
  /// 带结构化上报的缓存，与其他演示页隔离。
  late final _cache = Cacheman(
    container: 'cacheman_types_demo',
    options: CachemanOptions(
      onError: (key, error) {
        if (error is CachemanError) {
          _lines.add('${error.runtimeType}($key): ${error.cause}');
        }
      },
    ),
  );

  /// Initialization gate for the run button. / 演示按钮的初始化闸门。
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  /// Initializes once before enabling writes. / 启用写入前初始化一次。
  Future<void> _initialize() async {
    await _cache.ensureInitialized();
    if (mounted) setState(() => _ready = true);
  }

  /// Demonstrates retained mismatches, typed adapters and accessor ttl.
  /// 演示不匹配保留条目、类型适配和访问器 ttl。
  void _run() {
    _lines.clear();
    _cache.write(_namesKey, [_demoName]);
    final fallback = _cache.read<List<String>>(_namesKey, const []);
    _lines.add(
      'Without adapter / 无适配器: $fallback; retained / 保留: ${_cache.keys().contains(_namesKey)}',
    );
    final names = _cache.readWith<List<String>>(
      _namesKey,
      adapter: ValueAdapter.listOf<String>(),
    );
    _lines.add('With adapter / 有适配器: $names');
    final profile = fast<_Profile>(
      _cache,
      _profileKey,
      adapter: _profiles,
      ttl: 60000,
    );
    profile.set(const _Profile(_demoName));
    _lines.add('Profile + default ttl / 业务类 + 默认 ttl: ${profile.get()!.name}');
    _cache.write(_numberKey, 1);
    _lines.add(
      'int → double default / 默认值: ${_cache.read<double>(_numberKey, -1)}; num: ${_cache.read<num>(_numberKey)}',
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('ValueAdapter & CachemanError / 类型安全与错误分类'),
      const SizedBox(height: 12),
      FilledButton(
        onPressed: _ready ? _run : null,
        child: const Text('Run / 运行'),
      ),
      const SizedBox(height: 12),
      SelectableText(_lines.join('\n')),
    ],
  );
}
