part of 'context.dart';

/// 内核状态访问与白盒诊断；不从公共入口导出。
extension DiomanContextInternal<R extends DiomanResponse<dynamic>>
    on DiomanContext<R> {
  /// 当前逻辑请求共享状态，仅内核与内置插件可依赖。
  DiomanContextState get state => _state;

  /// 残留的取消等待订阅数，供 I3 白盒断言。
  int get cancellationSubscriptions => _state.listeners.length;

  /// 传输是否需要克隆重放体；插件通过 markReplayable 声明。
  bool get replayable => _state.replayable;

  /// 为内核及白盒夹具创建带共享状态的上下文。
  static DiomanContext<T> create<T extends DiomanResponse<dynamic>>(
          {required int id,
          required Dioman<T> client,
          required DiomanRequest request,
          required DiomanContextState state,
          required DiomanResponseFactory<T> factory,
          required DiomanKeyService keyService,
          required DiomanClock clock,
          required DiomanLogger log}) =>
      DiomanContext<T>._internal(
          id: id,
          client: client,
          request: request,
          state: state,
          factory: factory,
          keyService: keyService,
          clock: clock,
          log: log);
}
