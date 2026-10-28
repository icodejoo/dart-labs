// 规则层：log 的三个拦截阶段、插件名与 maxBodyLength
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// 插件名 / extra 键的期望值。
const _pluginName = 'dioman:log';

/// 日志行统一前缀。
const _tag = '[dioman:log]';

/// 假服务的基址。
const _base = 'http://fake';

/// 返回 200 的路径。
const _okPath = '/ok';

/// 返回 500 的路径。
const _badPath = '/bad';

/// 超长请求体的长度，超过默认 maxBodyLength（1000）。
const _longBodyLength = 1500;

/// 默认 maxBodyLength。
const _defaultMax = 1000;

/// writer 收到的一条输出。
typedef _Line = ({String message, Object? error});

/// 假适配器：`/bad` 回 500，其余回 200。
Future<ResponseBody> _reply(RequestOptions o, int n) async =>
    ResponseBody.fromString(
      jsonEncode(o.path == _badPath ? {'fail': true} : {'v': 1}),
      o.path == _badPath ? 500 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

/// 建一个装了 [log] 的 Dio；[adapter] 缺省用 [_reply]。
Dio _dioWith(DiomanLog log, {RecordingAdapter? adapter}) =>
    fakeDio(adapter ?? RecordingAdapter(_reply))..interceptors.add(log);

/// 注册本文件的规则层用例。
void main() {
  test('[DiomanLog.name][DiomanLog.pluginName] 插件名固定为 dioman:log，同时是 extra 键',
      () async {
    expect(DiomanLog.pluginName, _pluginName);
    expect(const DiomanLog().name, DiomanLog.pluginName);

    final lines = <String>[];
    final dio = _dioWith(DiomanLog(writer: (m, {error}) => lines.add(m)));
    // 用静态常量当 extra 键，单请求覆盖应当生效。
    await dio.get<dynamic>(_okPath,
        options: Options(extra: {
          DiomanLog.pluginName: const DiomanLogOptions(enabled: false),
        }));
    expect(lines, isEmpty);
    await dio.get<dynamic>(_okPath);
    expect(lines, isNotEmpty);
  });

  group('三个拦截阶段', () {
    test('[DiomanLog.onRequest] 记录 方法+URL，按 logHeaders/logBody 附带头与 body，并放行请求',
        () async {
      final lines = <String>[];
      final adapter = RecordingAdapter(_reply);
      final dio = _dioWith(
          DiomanLog(logHeaders: true, writer: (m, {error}) => lines.add(m)),
          adapter: adapter);

      await dio.put<dynamic>('$_okPath?q=1',
          data: 'hello', options: Options(headers: {'x-trace': 'abc'}));

      final req = lines.first;
      expect(req, startsWith('$_tag → PUT $_base$_okPath?q=1'));
      expect(req, contains('Headers:'));
      expect(req, contains('x-trace: abc'));
      expect(req, endsWith('Body: hello'));
      expect(adapter.calls, 1, reason: '日志只旁观，请求照常发出');
    });

    test('[DiomanLog.onResponse] 记录 状态+方法+URL（可含头与 body），响应原样交给调用方', () async {
      final lines = <String>[];
      final dio = _dioWith(
          DiomanLog(logHeaders: true, writer: (m, {error}) => lines.add(m)));

      final res = await dio.get<dynamic>(_okPath);

      expect(res.statusCode, 200);
      expect(res.data, {'v': 1}, reason: '响应未被改动');
      final resLine = lines.firstWhere((l) => l.contains('← '));
      expect(resLine, startsWith('$_tag ← 200 GET $_base$_okPath'));
      expect(resLine, contains('Headers:'));
      expect(resLine, contains('content-type'));
      expect(resLine, endsWith('Body: {v: 1}'));
    });

    test('[DiomanLog.onError] 带状态码的错误：记录状态行与错误体后放行，异常照常抛出', () async {
      final lines = <_Line>[];
      final dio = _dioWith(DiomanLog(
          writer: (m, {error}) => lines.add((message: m, error: error))));

      await expectLater(
        dio.get<dynamic>(_badPath),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 500)),
      );

      final errLine = lines.firstWhere((l) => l.message.contains('✗'));
      expect(errLine.message, '$_tag ✗ 500 GET $_base$_badPath');
      expect(errLine.error, isNotNull,
          reason: 'error 参数带上 err.error ?? err.message');
      expect(lines.last.message, '  Error body: {fail: true}',
          reason: '错误体是单独的一条输出');
    });

    test('[DiomanLog.onError] 没有响应的传输错误：用错误类型当标签，error 参数是底层 error，没有错误体行',
        () async {
      final lines = <_Line>[];
      final cause = StateError('socket gone');
      final dio = _dioWith(
        DiomanLog(
            writer: (m, {error}) => lines.add((message: m, error: error))),
        adapter: RecordingAdapter((o, n) async => throw DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
            error: cause)),
      );

      await expectLater(
          dio.get<dynamic>(_okPath), throwsA(isA<DioException>()));

      final errLines = lines.where((l) => l.message.contains('✗')).toList();
      expect(errLines, hasLength(1));
      expect(errLines.single.message,
          '$_tag ✗ connectionError GET $_base$_okPath');
      expect(errLines.single.error, same(cause));
      expect(lines.any((l) => l.message.contains('Error body')), isFalse);
    });
  });

  group('maxBodyLength', () {
    /// 发一个 [_longBodyLength] 字符的请求体，返回第一条（请求）日志。
    Future<String> firstLog(int? pluginMax, DiomanLogOptions? override) async {
      final lines = <String>[];
      final dio = _dioWith(pluginMax == null
          ? DiomanLog(writer: (m, {error}) => lines.add(m))
          : DiomanLog(
              maxBodyLength: pluginMax, writer: (m, {error}) => lines.add(m)));
      await dio.post<dynamic>(_okPath,
          data: 'x' * _longBodyLength,
          options: override == null
              ? null
              : Options(extra: {DiomanLog.pluginName: override}));
      return lines.first;
    }

    test(
        '[DiomanLog.maxBodyLength][DiomanLog.new(maxBodyLength)] 默认 1000：超长 body 截断并附剩余字数；-1 不截断；自定义值按值截断',
        () async {
      expect(const DiomanLog().maxBodyLength, _defaultMax);

      expect(await firstLog(null, null),
          endsWith('${'x' * _defaultMax}… (+500 chars)'));

      final unlimited = await firstLog(-1, null);
      expect(unlimited, endsWith('x' * _longBodyLength));
      expect(unlimited, isNot(contains('… (+')));

      expect(await firstLog(10, null), endsWith('${'x' * 10}… (+1490 chars)'));
    });

    test(
        '[DiomanLogOptions.maxBodyLength][DiomanLogOptions.new(maxBodyLength)] 单请求覆盖截断长度，null 沿用插件值',
        () async {
      expect(await firstLog(null, const DiomanLogOptions(maxBodyLength: 5)),
          endsWith('xxxxx… (+1495 chars)'));
      expect(await firstLog(null, const DiomanLogOptions(maxBodyLength: -1)),
          endsWith('x' * _longBodyLength),
          reason: '单请求 -1 覆盖插件的 1000');
      expect(await firstLog(-1, const DiomanLogOptions(maxBodyLength: 5)),
          endsWith('xxxxx… (+1495 chars)'),
          reason: '单请求能把插件的不限制收紧');
      expect(await firstLog(20, const DiomanLogOptions()),
          endsWith('${'x' * 20}… (+1480 chars)'),
          reason: 'null 沿用插件值');
    });

    test('[DiomanLog.maxBodyLength] 截断同样作用于响应体和错误体', () async {
      final lines = <String>[];
      final dio = _dioWith(
        DiomanLog(maxBodyLength: 4, writer: (m, {error}) => lines.add(m)),
        adapter: RecordingAdapter((o, n) async => ResponseBody.fromString(
                'y' * 20, o.path == _badPath ? 500 : 200,
                headers: {
                  Headers.contentTypeHeader: [Headers.textPlainContentType],
                })),
      );
      await dio.get<dynamic>(_okPath);
      await expectLater(
          dio.get<dynamic>(_badPath), throwsA(isA<DioException>()));

      expect(lines.any((l) => l.endsWith('Body: yyyy… (+16 chars)')), isTrue);
      expect(lines.last, '  Error body: yyyy… (+16 chars)');
    });
  });
}
