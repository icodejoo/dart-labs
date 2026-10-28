import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';

/// 路径替换的请求级覆盖；null 字段继承插件配置。
class DiomanRepathOptions {
  /// [pattern] 的第一个非空捕获组是键名；[removeKey] 控制消费字段删除。
  const DiomanRepathOptions({this.enabled, this.pattern, this.removeKey});

  /// false 跳过本次处理。
  final bool? enabled;

  /// 占位符正则。
  final RegExp? pattern;

  /// 是否移除被消费的字段。
  final bool? removeKey;
}

/// 只替换 URL 路径中的变量，query 优先于 Map 请求体。
class DiomanRepath<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// 创建插件，例如 `DiomanRepath(removeKey: false)`；值按路径段编码。
  const DiomanRepath(
      {this.pattern, this.removeKey = true, this.enabled = true});

  /// 自定义捕获正则，省略时匹配三种内置语法。
  final RegExp? pattern;

  /// 替换后删除来源键。
  final bool removeKey;

  /// 安装期开关。
  @override
  final bool enabled;

  /// 稳定名称。
  static const pluginName = 'dioman:repath';

  /// 请求选项键，接受 bool 或 DiomanRepathOptions。
  static final option = DiomanOptionKey<DiomanRepathOptions>(pluginName);

  /// 默认占位符模式。
  static final defaultPattern = RegExp(r'\{([^}]+)\}|\[([^\]]+)]|:([^/?#\s]+)');

  /// 返回稳定名称。
  @override
  String get name => pluginName;

  /// 请求整形阶段。
  @override
  DiomanStage get stage => DiomanStage.prepare;

  /// 预合并默认配置。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) =>
      _Repath<R>(DiomanRepathOptions(
          pattern: pattern ?? defaultPattern, removeKey: removeKey));
}

/// 每客户端的已解析配置。
class _Repath<R extends DiomanResponse<dynamic>>
    extends DiomanPluginInstance<R> {
  /// 保存基础配置。
  _Repath(this.base);

  /// 预合并配置。
  final DiomanRepathOptions base;

  /// 生成路径与来源字段的补丁，不修改原请求。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) {
    final o = resolveOption<DiomanRepathOptions>(
        ctx.request.call.options[DiomanRepath.option],
        base: base,
        merge: (a, b) => DiomanRepathOptions(
            enabled: b.enabled,
            pattern: b.pattern ?? a.pattern,
            removeKey: b.removeKey ?? a.removeKey));
    if (o == null || o.enabled == false) return next();
    final original = ctx.request.path;
    final origin = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/?#]*')
            .firstMatch(original)
            ?.end ??
        0;
    final rest = original.substring(origin);
    final suffixAt = rest.indexOf(RegExp(r'[?#]'));
    final path = suffixAt < 0 ? rest : rest.substring(0, suffixAt);
    final suffix = rest.substring(path.length);
    final query = ctx.request.query;
    final data = ctx.request.data;
    final usedQuery = <String>{};
    final usedData = <String>{};
    final replaced = path.replaceAllMapped(o.pattern!, (m) {
      String? key;
      for (var i = 1; i <= m.groupCount; i++) {
        final group = m.group(i);
        if (group != null && group.isNotEmpty) {
          key = group;
          break;
        }
      }
      if (key == null) return m[0]!;
      if (query.containsKey(key)) {
        usedQuery.add(key);
        return Uri.encodeComponent('${query[key]}');
      }
      if (data is Map && data.containsKey(key)) {
        usedData.add(key);
        return Uri.encodeComponent('${data[key]}');
      }
      return m[0]!;
    });
    if (replaced == path) return next();
    final newPath = original.substring(0, origin) + replaced + suffix;
    if (!o.removeKey!) return next(RequestPatch(path: newPath));
    if (usedData.isEmpty) {
      return next(RequestPatch(path: newPath, removeQuery: usedQuery));
    }
    final body = Map.of(data as Map)
      ..removeWhere((k, _) => usedData.contains(k));
    return next(
        RequestPatch(path: newPath, removeQuery: usedQuery, data: body));
  }
}
