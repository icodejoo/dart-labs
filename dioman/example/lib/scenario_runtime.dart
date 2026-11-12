import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:flutter/material.dart';
import 'demo_kit/demo_kit.dart';

/// 不会发往公网的本地传输来源。
const demoOrigin = 'https://demo.invalid';

/// 演示使用的统一请求方法。
const demoMethod = 'GET';

/// 演示使用的统一请求路径。
const demoPath = '/items';

/// 可随界面语言切换的文案或日志。
class DemoText {
  /// 保存英文和中文版本。
  const DemoText(this.en, this.zh);

  /// 英文文案。
  final String en;

  /// 中文文案。
  final String zh;

  /// 按作用域语言选择文本。
  String resolve(BuildContext context) => tr(context, en, zh);
}

/// 每轮演示独立持有客户端、等待任务及双语日志。
class DemoSession {
  /// 创建本轮资源容器。
  DemoSession(this.emit);

  /// 输出双语日志的回调。
  final void Function(DemoText) emit;

  /// 本轮创建的客户端。
  final List<Dioman> _clients = [];

  /// 能在离页时立即结束的等待任务。
  final Map<Timer, Completer<void>> _waits = {};

  /// 复用同一资源释放结果。
  Future<void>? _closing;

  /// 同步封闭日志与新等待，先于异步资源释放。
  bool _closed = false;

  /// 是否已离页或被重放取代。
  bool get closed => _closed;

  /// 输出日志；销毁后忽略迟到的回调。
  void log(String en, String zh, [Object? detail]) {
    if (closed) return;
    final suffix = detail == null ? '' : '\n$detail';
    emit(DemoText('$en$suffix', '$zh$suffix'));
  }

  /// 安装真实 Dioman 管线和内存传输，不触发外部网络。
  Dioman client({
    List<DiomanPlugin> plugins = const [],
    FutureOr<ResponseBody> Function(RequestOptions)? respond,
    Duration? deadline,
    DiomanLogger? debug,
  }) {
    final dio = Dio(BaseOptions(baseUrl: demoOrigin));
    dio.httpClientAdapter = _DemoTransport(this, respond);
    final api =
        Dioman(dio: dio, plugins: plugins, deadline: deadline, debug: debug);
    _clients.add(api);
    return api;
  }

  /// 等待可取消的演示延迟，离页时释放对应计时器。
  Future<void> wait(Duration duration) {
    if (closed) return Future<void>.value();
    final done = Completer<void>();
    late final Timer timer;
    timer = Timer(duration, () {
      _waits.remove(timer);
      done.complete();
    });
    _waits[timer] = done;
    return done.future;
  }

  /// 取消在途调用并等待插件释放，最后关闭宿主持有的 Dio。
  Future<void> close() {
    _closed = true;
    return _closing ??= _dispose();
  }

  /// 依次清理本轮客户端和演示计时器。
  Future<void> _dispose() async {
    for (final entry in _waits.entries) {
      entry.key.cancel();
      entry.value.complete();
    }
    _waits.clear();
    for (final api in _clients.reversed) {
      try {
        await api.dispose();
      } finally {
        api.dio.close(force: true);
      }
    }
  }
}

/// 使用 JSON 响应模拟服务器，不绕过缓存或共享所在的 source 阶段。
ResponseBody demoJson(Object? data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );

/// 接入 Dio 的内存后端，保留完整请求及取消语义。
class _DemoTransport implements HttpClientAdapter {
  /// 保存本轮资源与可选路由处理器。
  _DemoTransport(this.session, this.respond);

  /// 所属演示轮次。
  final DemoSession session;

  /// 当前演示自定义响应。
  final FutureOr<ResponseBody> Function(RequestOptions)? respond;

  /// 生成内存响应；取消后返回 Dio 取消错误。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = await (respond?.call(options) ?? demoJson({'value': 42}));
    if (session.closed || (options.cancelToken?.isCancelled ?? false)) {
      throw DioException(
          requestOptions: options, type: DioExceptionType.cancel);
    }
    return body;
  }

  /// 内存传输没有额外连接资源。
  @override
  void close({bool force = false}) {}
}

/// 透明观察 outer 阶段进出，不替代内核结果模型。
class DemoTrace extends DiomanPlugin {
  /// 保存本轮日志容器。
  const DemoTrace(this.session);

  /// 本轮资源容器。
  final DemoSession session;

  /// 自定义插件的稳定标识。
  @override
  String get name => 'demo:trace';

  /// 观察整个逻辑请求。
  @override
  DiomanStage get stage => DiomanStage.outer;

  /// 每客户端创建独立观察实例。
  @override
  DiomanPluginInstance setup(Dioman client) => _TraceInstance(session);
}

/// 记录调用的开始和最终 HTTP 状态。
class _TraceInstance extends DiomanPluginInstance {
  /// 保存日志容器。
  _TraceInstance(this.session);

  /// 本轮日志容器。
  final DemoSession session;

  /// 在 next 两侧观察请求与结果。
  @override
  Future<DiomanResponse<dynamic>> handle(
      DiomanContext ctx, DiomanNext next) async {
    session.log('Request entered outer stage', '请求进入 outer 阶段',
        '${ctx.request.method} ${ctx.request.path}');
    final result = await next();
    session.log('Final HTTP status', '最终 HTTP 状态', result.status);
    return result;
  }
}
