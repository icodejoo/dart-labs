import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';

/// 返回 true 时剔除顶层字段；异常按 bug 原样落定。
typedef DiomanFilterPredicate = bool Function(String key, dynamic value);

/// 过滤的请求级覆盖，忽略集合与插件配置取并集。
class DiomanFilterOptions {
  /// [predicate] 替换谓词，空字段继承；例如 `DiomanFilterOptions(ignoreKeys: ['id'])`。
  const DiomanFilterOptions(
      {this.enabled, this.predicate, this.ignoreKeys, this.ignoreValues});

  /// false 跳过过滤。
  final bool? enabled;

  /// 返回 true 时删除。
  final DiomanFilterPredicate? predicate;

  /// 直接保留的键。
  final List<String>? ignoreKeys;

  /// 直接保留的值，沿用 Dart 相等语义。
  final List<Object?>? ignoreValues;
}

/// 装上即过滤 query 与 Map 请求体的顶层空字段。
class DiomanFilter<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// 创建过滤器，例如 `DiomanFilter(ignoreKeys: ['nullable'])`；特殊载荷原样放行。
  const DiomanFilter(
      {this.predicate = defaultPredicate,
      this.ignoreKeys = const [],
      this.ignoreValues = const [],
      this.enabled = true});

  /// 字段删除规则。
  final DiomanFilterPredicate predicate;

  /// 保留键。
  final List<String> ignoreKeys;

  /// 保留值。
  final List<Object?> ignoreValues;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 稳定名称。
  static const pluginName = 'dioman:filter';

  /// 请求级 bool 或 DiomanFilterOptions 键。
  static final option = DiomanOptionKey<DiomanFilterOptions>(pluginName);

  /// 默认删除 null、NaN、空白字符串，保留零和 false。
  static bool defaultPredicate(String key, dynamic value) =>
      value == null ||
      (value is num && value.isNaN) ||
      (value is String && value.trim().isEmpty);

  /// 返回稳定名称。
  @override
  String get name => pluginName;

  /// 请求整形阶段。
  @override
  DiomanStage get stage => DiomanStage.prepare;

  /// 复制豁免集合，避免外部修改基础配置。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) =>
      _Filter<R>(DiomanFilterOptions(
          predicate: predicate,
          ignoreKeys: List.of(ignoreKeys),
          ignoreValues: List.of(ignoreValues)));
}

/// 每客户端的过滤配置。
class _Filter<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> {
  /// 保存基础配置。
  _Filter(this.base);

  /// 预合并配置。
  final DiomanFilterOptions base;

  /// 判定一次并仅在删除字段时派生请求。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) {
    final o = resolveOption<DiomanFilterOptions>(
        ctx.request.call.options[DiomanFilter.option],
        base: base,
        merge: (a, b) => DiomanFilterOptions(
            enabled: b.enabled,
            predicate: b.predicate ?? a.predicate,
            ignoreKeys: [...a.ignoreKeys!, ...?b.ignoreKeys],
            ignoreValues: [...a.ignoreValues!, ...?b.ignoreValues]));
    if (o == null || o.enabled == false) return next();

    /// 豁免项优先于用户谓词。
    bool drop(dynamic k, dynamic v) =>
        !o.ignoreKeys!.contains('$k') &&
        !o.ignoreValues!.contains(v) &&
        o.predicate!('$k', v);
    final queryKeys = ctx.request.query.entries
        .where((e) => drop(e.key, e.value))
        .map((e) => e.key)
        .toSet();
    final data = ctx.request.data;
    if (data is Map) {
      final body = Map.of(data)..removeWhere(drop);
      if (body.length != data.length) {
        return next(RequestPatch(removeQuery: queryKeys, data: body));
      }
    }
    if (queryKeys.isEmpty) return next();
    return next(RequestPatch(removeQuery: queryKeys));
  }
}
