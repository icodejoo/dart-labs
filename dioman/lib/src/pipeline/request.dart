import 'dart:collection';
import 'package:dio/dio.dart';
import 'options.dart';

/// 区分未提供和显式 null 的补丁哨兵。
const _absent = Object();

/// 有效 Dio 配置的不可变请求视图；入口合并一次后构造。
class DiomanRequest {
  /// 从 [options] 拷贝有效配置；[call] 保存调用选项，例如 `DiomanRequest(ro)`。
  DiomanRequest(RequestOptions options, {DiomanCall call = const DiomanCall()})
      : _options = options.copyWith(),
        data = options.data,
        headers = Map.unmodifiable(options.headers),
        query = Map.unmodifiable(options.queryParameters),
        extra = Map.unmodifiable(options.extra),
        call = DiomanCall(
            key: call.key,
            envelope: call.envelope,
            silent: call.silent,
            options: Map.unmodifiable(call.options));

  /// 完整有效配置的私有副本，永不交给 Dio 修改。
  final RequestOptions _options;

  /// 请求体引用；不透明载荷由传输按需克隆，插件通过补丁替换。
  final Object? data;

  /// 不可修改的请求头。
  final Map<String, dynamic> headers;

  /// 不可修改的查询参数。
  final Map<String, dynamic> query;

  /// 不可修改的用户扩展字段。
  final Map<String, dynamic> extra;

  /// 调用配置。
  final DiomanCall call;

  /// 有效路径。
  String get path => _options.path;

  /// 有效方法。
  String get method => _options.method;

  /// 有效基础地址。
  String get baseUrl => _options.baseUrl;

  /// 有效 URI。
  Uri get uri => toRequestOptions().uri;

  /// 连接超时。
  Duration? get connectTimeout => _options.connectTimeout;

  /// 发送超时。
  Duration? get sendTimeout => _options.sendTimeout;

  /// 接收超时。
  Duration? get receiveTimeout => _options.receiveTimeout;

  /// 当前传输令牌；未指定时内核使用逻辑请求令牌。
  CancelToken? get cancelToken => _options.cancelToken;

  /// 通知静默标记。
  bool get silent => call.silent;

  /// 返回可独立修改的有效 Dio 配置，例如 `dio.fetch(r.toRequestOptions())`。
  RequestOptions toRequestOptions() => _options.copyWith(
      headers: Map.from(headers),
      queryParameters: Map.from(query),
      extra: Map.from(extra))
    ..data = data;

  /// 合并 [patch] 并返回独立视图；不修改基准请求。
  DiomanRequest patch(RequestPatch patch) {
    final o = toRequestOptions();
    final h = LinkedHashMap<String, dynamic>.from(o.headers);
    for (final key in patch.removeHeaders) {
      h.removeWhere((k, _) => k.toLowerCase() == key.toLowerCase());
    }
    for (final e in patch.headers.entries) {
      h.removeWhere((k, _) => k.toLowerCase() == e.key.toLowerCase());
      h[e.key] = e.value;
    }
    o.headers = h;
    o.queryParameters.removeWhere((k, _) => patch.removeQuery.contains(k));
    o.queryParameters.addAll(patch.query);
    o.extra.addAll(patch.extra);
    if (!identical(patch.data, _absent)) o.data = patch.data;
    if (patch.path != null) o.path = patch.path!;
    if (patch.method != null) o.method = patch.method!;
    if (!identical(patch.connectTimeout, _absent)) {
      o.connectTimeout = patch.connectTimeout as Duration?;
    }
    if (!identical(patch.sendTimeout, _absent)) {
      o.sendTimeout = patch.sendTimeout as Duration?;
    }
    if (!identical(patch.receiveTimeout, _absent)) {
      o.receiveTimeout = patch.receiveTimeout as Duration?;
    }
    if (!identical(patch.cancelToken, _absent)) {
      o.cancelToken = patch.cancelToken as CancelToken?;
    }
    return DiomanRequest(o, call: call);
  }
}

/// 内层请求的改动；集合按键合并，删除必须显式提供删除集合。
class RequestPatch {
  /// 创建补丁，例如 `RequestPatch(data: null, removeHeaders: {'Authorization'})`。
  const RequestPatch(
      {this.headers = const {},
      this.query = const {},
      this.extra = const {},
      this.removeHeaders = const {},
      this.removeQuery = const {},
      this.data = _absent,
      this.path,
      this.method,
      this.connectTimeout = _absent,
      this.sendTimeout = _absent,
      this.receiveTimeout = _absent,
      this.cancelToken = _absent});

  /// 合并的请求头。
  final Map<String, dynamic> headers;

  /// 合并的查询参数。
  final Map<String, dynamic> query;

  /// 合并的用户扩展。
  final Map<String, dynamic> extra;

  /// 不区分大小写的待删除请求头。
  final Set<String> removeHeaders;

  /// 待删除查询键。
  final Set<String> removeQuery;

  /// 整体替换的请求体，允许 null。
  final Object? data;

  /// 替换路径。
  final String? path;

  /// 替换方法。
  final String? method;

  /// 替换连接超时，允许 null。
  final Object? connectTimeout;

  /// 替换发送超时，允许 null。
  final Object? sendTimeout;

  /// 替换接收超时，允许 null。
  final Object? receiveTimeout;

  /// 替换传输取消令牌，允许 null。
  final Object? cancelToken;
}
