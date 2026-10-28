import 'package:dio/dio.dart';
import 'clock.dart';
import 'config.dart';
import 'context.dart';
import 'key.dart';
import 'options.dart';
import 'pipeline.dart';
import 'plugin.dart';
import 'request.dart';
import 'response.dart';
import 'stages.dart';
import 'transport.dart';

/// 关闭 debug 时复用的空日志器。
void _noLog(String _) {}

/// 以 Dio 为引擎的洋葱管线客户端；旧入口与本库完全独立。
class Dioman<R extends DiomanResponse<dynamic>> {
  /// 创建客户端，例如 `Dioman(dio: Dio(), debug: true)`。
  /// [response] 控制归一化，[reject] 只转换动词方法的可预期失败。
  Dioman(
      {required this.dio,
      List<DiomanPlugin<R>> plugins = const [],
      DiomanResponseFactory<R>? response,
      this.key = const DiomanKeyOptions(),
      this.reject,
      Object? debug,
      this.clock = const DiomanClock.system()})
      : response = response ?? DiomanResponseFactory<R>(),
        _debug = debug != null && debug != false,
        _logger =
            debug is DiomanLogger ? debug : (debug == true ? print : _noLog) {
    if (debug != null && debug is! bool && debug is! DiomanLogger) {
      throw ArgumentError.value(debug, 'debug');
    }
    validateDiomanPlugins(plugins);
    try {
      for (final plugin in plugins) {
        _registrations.add(DiomanRegistration(
            plugin, plugin.enabled ? plugin.setup(this) : null));
      }
      _compile();
    } catch (_) {
      for (final registration in _registrations.reversed) {
        try {
          registration.instance?.dispose();
        } catch (_) {/* 保留安装时首次异常。 */}
      }
      rethrow;
    }
  }

  /// 底层 Dio；用户拦截器在每次传输时运行。
  final Dio dio;

  /// 客户端的归一化服务。
  final DiomanResponseFactory<R> response;

  /// 客户端构键配置。
  final DiomanKeyOptions key;

  /// 可预期失败的最终异常转换器。
  final Object Function(R)? reject;

  /// 可注入时间服务。
  final DiomanClock clock;

  /// 是否记录调用点。
  final bool _debug;

  /// 用户日志器或默认输出。
  final DiomanLogger _logger;

  /// 注册顺序，供生命周期和 extend 使用。
  final _registrations = <DiomanRegistration<R>>[];

  /// 已排序的执行层快照。
  List<DiomanRegistration<R>> _layers = [];

  /// 编译后的链，在途请求捕获当前值。
  late DiomanRunner<R> _run;

  /// 活跃逻辑请求。
  final _pending = <DiomanContextState>{};

  /// 仍可取消的请求状态，包含逻辑调用已结束的共享传输。
  final _cancellable = <DiomanContextState>{};

  /// 请求序号。
  int _sequence = 0;

  /// 生命周期状态。
  bool _disposed = false;

  /// 当前活跃逻辑请求数。
  int get pending => _pending.length;

  /// 活跃的内核取消等待订阅总数，供不变量检查。
  int get cancellationSubscriptions =>
      _pending.fold(0, (n, s) => n + s.listeners.length);

  /// 隔离日志回调异常，避免 debug 改变请求结果。
  void _log(String message) {
    try {
      _logger(message);
    } catch (_) {/* 日志通知不影响请求。 */}
  }

  /// 记录插件通知故障；[message] 交给用户日志器或默认输出，日志器异常会隔离。
  /// 例如插件捕获回调错误后调用 `client.logError('通知失败')`，不受 debug 开关抑制。
  void logError(String message) {
    if (_debug) {
      _log(message);
    } else {
      try {
        print(message);
      } catch (_) {/* 输出通知不影响请求。 */}
    }
  }

  /// 拒绝销毁后的操作。
  void _checkAlive() {
    if (_disposed) throw StateError('客户端已销毁');
  }

  /// 在配置变动时编译链，不在请求期间排序。
  void _compile() {
    _layers = sortDiomanPipeline(_registrations);
    _run = compileDiomanPipeline(_layers, (ctx) => diomanTransport(dio, ctx));
  }

  /// 添加插件；先校验再 setup，安装失败不修改当前链。
  void use(DiomanPlugin<R> plugin) {
    _checkAlive();
    validateDiomanPlugins([..._registrations.map((r) => r.plugin), plugin]);
    final instance = plugin.enabled ? plugin.setup(this) : null;
    _registrations.add(DiomanRegistration(plugin, instance));
    _compile();
  }

  /// 按 [name] 移除并释放插件；不存在返回 false，在途保留原链。
  bool eject(String name) {
    final index = _registrations.indexWhere((r) => r.plugin.name == name);
    if (index < 0) return false;
    final removed = _registrations.removeAt(index);
    _compile();
    removed.instance?.dispose();
    return true;
  }

  /// 返回实现 [A] 的第一个实例，例如 `api.plugin<CacheApi>()`。
  A? plugin<A>() {
    for (final r in _registrations) {
      if (r.instance is A) return r.instance as A;
    }
    return null;
  }

  /// 返回解析后的固定阶段和名称顺序，返回列表不可修改。
  List<(DiomanStage, String)> inspect() => List.unmodifiable(_layers.map((r) {
        final fixed = diomanBuiltinStages.entries
            .where((e) => e.value.contains(r.plugin.name));
        return (
          fixed.isEmpty ? r.plugin.stage : fixed.single.key,
          r.plugin.name
        );
      }));

  /// 中止尚未取消的请求状态（含保留的共享传输），返回本次中止数。
  int cancelAll([Object? reason]) {
    var count = 0;
    for (final state in _cancellable.toList()) {
      if (!state.token.isCancelled) {
        count++;
        state.cancel(reason);
      }
    }
    return count;
  }

  /// 克隆 BaseOptions 并重新 setup 插件，状态不共享；[plugins] 替换继承列表。
  /// [options] 在 setup 后合并非空、非默认字段，显式覆盖优先；容器按键合并。
  /// BaseOptions 不记录省略信息，不能用默认值重置已有非默认值。
  /// 例如 `api.extend(options: BaseOptions(baseUrl: 'https://child.example'))`。
  Dioman<R> extend({BaseOptions? options, List<DiomanPlugin<R>>? plugins}) {
    _checkAlive();
    final child = Dioman<R>(
        dio: Dio(cloneDiomanOptions(dio.options)),
        plugins: plugins ?? _registrations.map((r) => r.plugin).toList(),
        response: response,
        key: key,
        reject: reject,
        debug: _debug ? _logger : false,
        clock: clock);
    if (options != null) mergeDiomanOptions(child.dio.options, options);
    return child;
  }

  /// 先取消请求，再逆序释放全部实例；清理完毕后原栈抛出首个异常。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelAll();
    final errors = <(Object, StackTrace)>[];
    for (final r in _registrations.reversed) {
      try {
        r.instance?.dispose();
      } catch (e, s) {
        errors.add((e, s));
      }
    }
    if (errors.isNotEmpty) {
      Error.throwWithStackTrace(errors.first.$1, errors.first.$2);
    }
  }

  /// 执行请求并返回结果；可预期失败不抛，internal 原异常原栈抛出。
  /// 例如 `await api.send<Object?>('GET', '/pets')`。
  Future<DiomanResponse<T>> send<T>(String method, String path,
      {Map<String, dynamic>? query, Object? data, DiomanCall? call}) async {
    final result =
        await _dispatch(method, path, query: query, data: data, call: call);
    if (result is DiomanResponse<T>) return result;
    return result.copy<T>();
  }

  /// 执行任意 [method] 并返回数据；可预期失败经 reject 后抛出。
  Future<T> request<T>(String method, String path,
      {Map<String, dynamic>? query, Object? data, DiomanCall? call}) async {
    final result =
        await _dispatch(method, path, query: query, data: data, call: call);
    if (!result.ok) throw (reject?.call(result as R) ?? result);
    return result.data as T;
  }

  /// 发送 GET 并返回数据；参数与 request 相同，例如 `api.get<Object?>('/pets')`。
  Future<T> get<T>(String path,
          {Map<String, dynamic>? query, Object? data, DiomanCall? call}) =>
      request<T>('GET', path, query: query, data: data, call: call);

  /// 发送 POST 并返回数据；参数与 request 相同，例如 `api.post<Object?>('/pets')`。
  Future<T> post<T>(String path,
          {Map<String, dynamic>? query, Object? data, DiomanCall? call}) =>
      request<T>('POST', path, query: query, data: data, call: call);

  /// 发送 PUT 并返回数据；参数与 request 相同，例如 `api.put<Object?>('/pets')`。
  Future<T> put<T>(String path,
          {Map<String, dynamic>? query, Object? data, DiomanCall? call}) =>
      request<T>('PUT', path, query: query, data: data, call: call);

  /// 发送 PATCH 并返回数据；参数与 request 相同，例如 `api.patch<Object?>('/pets')`。
  Future<T> patch<T>(String path,
          {Map<String, dynamic>? query, Object? data, DiomanCall? call}) =>
      request<T>('PATCH', path, query: query, data: data, call: call);

  /// 发送 DELETE 并返回数据；参数与 request 相同，例如 `api.delete<Object?>('/pets')`。
  Future<T> delete<T>(String path,
          {Map<String, dynamic>? query, Object? data, DiomanCall? call}) =>
      request<T>('DELETE', path, query: query, data: data, call: call);

  /// 发送 HEAD 并返回数据；参数与 request 相同，例如 `api.head<Object?>('/pets')`。
  Future<T> head<T>(String path,
          {Map<String, dynamic>? query, Object? data, DiomanCall? call}) =>
      request<T>('HEAD', path, query: query, data: data, call: call);

  /// 入口仅 compose 一次；登记后所有可能抛错的构造都在 finally 保护内。
  Future<DiomanResponse<dynamic>> _dispatch(String method, String path,
      {Map<String, dynamic>? query, Object? data, DiomanCall? call}) async {
    _checkAlive();
    final run = _run;
    final site = _debug ? StackTrace.current : null;
    late final DiomanContextState state;
    state = DiomanContextState(CancelToken(),
        onDispose: () => _cancellable.remove(state));
    _cancellable.add(state);
    DiomanCancelLink? userLink;
    _pending.add(state);
    try {
      final c = call ?? const DiomanCall();
      if (c.cancelToken != null) {
        userLink = DiomanCancelLink(c.cancelToken!, state.cancel);
      }
      final options = Options(
              method: method,
              headers: c.headers,
              sendTimeout: c.sendTimeout,
              receiveTimeout: c.receiveTimeout)
          .compose(dio.options, path, queryParameters: query, data: data);
      if (c.connectTimeout != null) options.connectTimeout = c.connectTimeout;
      final ctx = DiomanContext<R>(
          id: ++_sequence,
          client: this,
          request: DiomanRequest(options, call: c),
          state: state,
          factory: response,
          keyService: DiomanKeyService(key),
          clock: clock,
          log: _log);
      var result = await run(ctx);
      if (result.kind != DiomanKind.internal) {
        result = ctx.cancelled() ?? result;
      }
      if (!result.ok && site != null && result.kind != DiomanKind.internal) {
        result = response.withCallSite(result, site);
      }
      if (result.kind == DiomanKind.internal) {
        Error.throwWithStackTrace(
            result.error ?? StateError('internal result without error'),
            result.errorStack ?? StackTrace.current);
      }
      return result;
    } finally {
      userLink?.dispose();
      state.dispose();
      _pending.remove(state);
    }
  }
}
