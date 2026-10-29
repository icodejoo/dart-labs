import 'dart:async';
import 'package:dio/dio.dart';
import '../client.dart';
import '../context.dart';
import '../options.dart';
import '../plugin.dart';
import '../request.dart';
import '../response.dart';
import '../stages.dart';

/// source 默认安全方法白名单。
const sourceSafeMethods = {'GET', 'HEAD'};

/// mock 探测期间绕过共享和缓存；只在当前 next 调用期间置位。
final sourceProbe = StateKey<bool>('mock probe');

/// 内联路由处理器；返回原始数据（HTTP 200）或 Dio Response，由工厂归一化。
typedef DiomanMockRoute = FutureOr<Object?> Function(DiomanRequest request);

/// 请求级 mock 配置；null 字段沿用插件配置。
class DiomanMockOptions {
  /// 例如 `DiomanMockOptions(mockUrl: 'https://mock.example')`。
  const DiomanMockOptions(
      {this.enabled, this.routes, this.mockUrl, this.fallbackWhen});

  /// 本次开关。
  final bool? enabled;

  /// METHOD:path 到处理器的映射。
  final Map<String, DiomanMockRoute>? routes;

  /// 探测服务地址。
  final String? mockUrl;

  /// 探测结果是否回落；抛错按程序错误处理。
  final bool Function(DiomanResponse<dynamic>)? fallbackWhen;
}

/// source 最外层 mock；内联命中直接经工厂返回，否则探测后按条件回落。
class DiomanMock<R extends DiomanResponse<dynamic>> extends DiomanPlugin<R> {
  /// [routes] 优先于 [mockUrl]，例如 `DiomanMock(routes: {'GET:/pets': (_) => []})`。
  const DiomanMock(
      {this.enabled = true,
      this.routes = const {},
      this.mockUrl,
      this.fallbackWhen});

  /// 安装期开关，默认装上即生效。
  @override
  final bool enabled;

  /// 内联路由。
  final Map<String, DiomanMockRoute> routes;

  /// 转发服务地址。
  final String? mockUrl;

  /// 回落判定，默认 HTTP 404 或网络失败。
  final bool Function(DiomanResponse<dynamic>)? fallbackWhen;

  /// 稳定插件名。
  static const pluginName = 'dioman:mock';

  /// 请求级 bool 或配置键。
  static final option = DiomanOptionKey<DiomanMockOptions>(pluginName);

  /// 稳定名称。
  @override
  String get name => pluginName;

  /// 结果来源阶段。
  @override
  DiomanStage get stage => DiomanStage.source;

  /// 为客户端复制路由表。
  @override
  DiomanPluginInstance<R> setup(Dioman<R> client) => _Mock<R>(DiomanMockOptions(
      routes: Map.of(routes), mockUrl: mockUrl, fallbackWhen: fallbackWhen));
}

/// 客户端独立配置。
class _Mock<R extends DiomanResponse<dynamic>> extends DiomanPluginInstance<R> {
  /// 保存预合并配置。
  _Mock(this.base);

  /// 插件配置。
  final DiomanMockOptions base;

  /// 探测状态只包围一次 next，回落恢复共享与缓存。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext<R> ctx, DiomanNext<R> next) async {
    final o = resolveOption<DiomanMockOptions>(
        ctx.request.call.options[DiomanMock.option],
        base: base,
        merge: (a, b) => DiomanMockOptions(
            enabled: b.enabled,
            routes: {...a.routes!, ...?b.routes},
            mockUrl: b.mockUrl ?? a.mockUrl,
            fallbackWhen: b.fallbackWhen ?? a.fallbackWhen));
    if (o == null || o.enabled == false) return next();
    final cancelled = ctx.cancelled();
    if (cancelled != null) return cancelled;
    final route = o.routes!['${ctx.request.method}:${ctx.request.uri.path}'];
    if (route != null) {
      final data = await ctx.wait(Future.sync(() => route(ctx.request)));
      return ctx.cancelled() ??
          ctx.factory.normalize(ctx.request,
              raw: data is Response<dynamic>
                  ? data
                  : Response<dynamic>(
                      requestOptions: ctx.request.toRequestOptions(),
                      statusCode: 200,
                      data: data));
    }
    final url = o.mockUrl;
    if (url == null || url.isEmpty) {
      ctx.log('[mock] 缺少 mockUrl，跳过探测');
      return next();
    }
    ctx.markReplayable();
    late DiomanResponse<dynamic> probe;
    ctx.set(sourceProbe, true);
    try {
      final path = ctx.request.uri.path;
      final original = Uri.parse(ctx.request.path);
      final query = original.hasQuery ? '?${original.query}' : '';
      probe = await next(RequestPatch(
          path: '${url.replaceFirst(RegExp(r'/+$'), '')}$path$query'));
    } finally {
      ctx.set(sourceProbe, false);
    }
    final cancel = ctx.cancelled();
    if (cancel != null) return cancel;
    final fallback = o.fallbackWhen?.call(probe) ??
        (probe.httpStatus == 404 || probe.kind == DiomanKind.network);
    return fallback ? next() : probe;
  }
}
