import 'package:dio/dio.dart';

/// 用于区分非空字段的默认值，BaseOptions 不保留参数是否显式传入的信息。
final _defaults = BaseOptions();

/// 递归复制配置容器；不透明对象保留身份。
dynamic cloneDiomanConfig(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k, cloneDiomanConfig(v)));
  }
  if (value is List) return value.map(cloneDiomanConfig).toList();
  return value;
}

/// 克隆配置及其三个可变容器，返回与源隔离的配置。
BaseOptions cloneDiomanOptions(BaseOptions source) => source.copyWith(
    headers: Map<String, dynamic>.from(cloneDiomanConfig(source.headers)),
    queryParameters:
        Map<String, dynamic>.from(cloneDiomanConfig(source.queryParameters)),
    extra: Map<String, dynamic>.from(cloneDiomanConfig(source.extra)));

/// 写入非空、非默认的配置；容器按顶层键合并并深拷贝。
/// BaseOptions 无法区分显式默认值与省略，因此空地址和 json 保留宿主值。
void mergeDiomanOptions(BaseOptions target, BaseOptions source) {
  final c = cloneDiomanOptions(source);
  final host = cloneDiomanOptions(target);
  if (c.baseUrl.isNotEmpty) target.baseUrl = c.baseUrl;
  if (c.connectTimeout != null) target.connectTimeout = c.connectTimeout;
  if (c.receiveTimeout != null) target.receiveTimeout = c.receiveTimeout;
  if (c.sendTimeout != null) target.sendTimeout = c.sendTimeout;
  target.headers = {...host.headers, ...c.headers};
  target.queryParameters = {...host.queryParameters, ...c.queryParameters};
  target.extra = {...host.extra, ...c.extra};
  if (c.responseType != ResponseType.json) target.responseType = c.responseType;
  if (c.method != _defaults.method) target.method = c.method;
  if (c.preserveHeaderCase != _defaults.preserveHeaderCase) {
    target.preserveHeaderCase = c.preserveHeaderCase;
  }
  if (c.validateStatus != _defaults.validateStatus) {
    target.validateStatus = c.validateStatus;
  }
  if (c.receiveDataWhenStatusError != _defaults.receiveDataWhenStatusError) {
    target.receiveDataWhenStatusError = c.receiveDataWhenStatusError;
  }
  if (c.followRedirects != _defaults.followRedirects) {
    target.followRedirects = c.followRedirects;
  }
  if (c.maxRedirects != _defaults.maxRedirects) {
    target.maxRedirects = c.maxRedirects;
  }
  if (c.persistentConnection != _defaults.persistentConnection) {
    target.persistentConnection = c.persistentConnection;
  }
  if (c.requestEncoder != null) target.requestEncoder = c.requestEncoder;
  if (c.responseDecoder != null) target.responseDecoder = c.responseDecoder;
  if (c.listFormat != _defaults.listFormat) target.listFormat = c.listFormat;
}
