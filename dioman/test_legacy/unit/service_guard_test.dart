// ignore_for_file: avoid_relative_lib_imports
// 单元：验收执行器的服务守卫——注入的 429/503 放行，真实限流/熔断整轮停止
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/common.dart';

/// testkit 注入失败时的响应体。
const _injectedBody = '{"code":503,"data":{"reason":"injected","meta":{}}}';

/// 真实 CPU 熔断时的响应体（没有注入标记）。
const _genuineBody = '{"code":503,"message":"cpu overloaded"}';

/// 固定返回 [status] 与 [body] 的假传输层。
class _FixedAdapter implements HttpClientAdapter {
  /// 构造返回固定响应的传输层。
  _FixedAdapter(this.status, this.body);

  /// 返回的状态码。
  final int status;

  /// 返回的响应体。
  final String body;

  /// 原样返回固定响应。
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(body, status);

  /// 无资源可释放。
  @override
  void close({bool force = false}) {}
}

/// 经守卫取一次 [status]/[body] 的响应，返回读出的响应体文本。
Future<String> _fetch(int status, String body) async {
  final guard = ServiceGuardAdapter(_FixedAdapter(status, body));
  final response =
      await guard.fetch(RequestOptions(path: '/t/echo'), null, null);
  return utf8.decode(
      await response.stream.fold<List<int>>([], (all, c) => all..addAll(c)));
}

/// 注册本文件的单元用例。
void main() {
  tearDown(() => serviceBlocked = false);

  test('[isInjectedResponse] 识别 testkit 的注入标记，真实熔断与普通响应不算', () {
    expect(isInjectedResponse(utf8.encode(_injectedBody)), isTrue);
    expect(
        isInjectedResponse(
            utf8.encode('{"data":{"reason": "injected failure"}}')),
        isTrue);
    expect(isInjectedResponse(utf8.encode(_genuineBody)), isFalse);
    expect(
        isInjectedResponse(utf8.encode('{"reason":"not injected"}')), isFalse);
    expect(isInjectedResponse([0xff, 0xfe]), isFalse, reason: '非法 UTF-8 不抛错');
  });

  test('[checkServiceStatus] 已解析数据带注入标记（含 business 风格的 HTTP 200 业务码）时放行，真实的仍停止',
      () {
    final injected = jsonDecode(_injectedBody);
    expect(isInjectedData(injected), isTrue);
    expect(isInjectedData(jsonDecode(_genuineBody)), isFalse);
    expect(isInjectedData('text'), isFalse);
    checkServiceStatus(429, data: injected);
    checkServiceStatus(503, data: injected);
    expect(serviceBlocked, isFalse);
    expect(() => checkServiceStatus(503, data: jsonDecode(_genuineBody)),
        throwsStateError);
    expect(serviceBlocked, isTrue);
    serviceBlocked = false;
    expect(() => checkServiceStatus(429), throwsStateError);
  });

  test('[ServiceGuardAdapter.fetch] 注入的 429/503 放行且响应体原样保留，不标记停止', () async {
    expect(await _fetch(503, _injectedBody), _injectedBody);
    expect(await _fetch(429, _injectedBody), _injectedBody);
    expect(serviceBlocked, isFalse);
  });

  test(
      '[ServiceGuardAdapter.fetch][checkServiceStatus] 真实 429/503 以取消错误中断并标记整轮停止',
      () async {
    await expectLater(
        _fetch(503, _genuineBody),
        throwsA(isA<DioException>()
            .having((e) => e.type, 'type', DioExceptionType.cancel)));
    expect(serviceBlocked, isTrue);
  });

  test('[ServiceGuardAdapter.fetch] 其他状态码不读响应体，直接透传', () async {
    expect(await _fetch(500, _genuineBody), _genuineBody);
    expect(serviceBlocked, isFalse);
  });
}
