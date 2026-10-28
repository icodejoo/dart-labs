// 规则层：log 的各个开关（插件级默认值 + 单请求覆盖）
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../../test/support/fixtures.dart';

/// 返回 200 的路径。
const _okPath = '/ok';

/// 返回 500 的路径。
const _badPath = '/bad';

/// 请求日志行的特征片段。
const _reqMark = '→ POST';

/// 响应日志行的特征片段。
const _resMark = '← 200';

/// 错误日志行的特征片段。
const _errMark = '✗ 500';

/// 自定义请求头名，用来确认头部日志。
const _reqHeader = 'x-trace';

/// 自定义响应头名，用来确认头部日志。
const _resHeader = 'x-reply';

/// 记录一次测试里 writer 收到的全部输出。
class _Captured {
  /// 日志文本，按调用顺序。
  final lines = <String>[];

  /// writer 的 error 参数，按调用顺序。
  final errors = <Object?>[];

  /// 是否出现过含 [mark] 的日志行。
  bool has(String mark) => lines.any((l) => l.contains(mark));
}

/// 假适配器：`/bad` 回 500，其余回 200；两种都带自定义响应头。
Future<ResponseBody> _reply(RequestOptions o, int n) async =>
    ResponseBody.fromString(
      jsonEncode(o.path == _badPath ? {'fail': true} : {'v': 1}),
      o.path == _badPath ? 500 : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        _resHeader: ['1'],
      },
    );

/// 建一个装了 [make] 造出的 DiomanLog 的 Dio，日志写进 [out]。
Dio _dioWith(_Captured out, DiomanLog Function(LogWriter writer) make) {
  final dio = fakeDio(RecordingAdapter(_reply));
  dio.interceptors.add(make((m, {error}) {
    out.lines.add(m);
    out.errors.add(error);
  }));
  return dio;
}

/// 带单请求日志覆盖的 Options，可附加请求头。
Options _override(DiomanLogOptions o, {Map<String, dynamic>? headers}) =>
    Options(extra: {DiomanLog.pluginName: o}, headers: headers);

/// 依次发一次成功请求和一次失败请求（失败必须抛 DioException）。
Future<void> _traffic(Dio dio, {Options? options, Object? data}) async {
  await dio.post<dynamic>(_okPath, data: data, options: options);
  await expectLater(dio.post<dynamic>(_badPath, data: data, options: options),
      throwsA(isA<DioException>()));
}

/// 注册本文件的规则层用例。
void main() {
  group('DiomanLog 总开关 enabled', () {
    test(
        '[DiomanLog.enabled][DiomanLog.new(enabled)] 默认开启；false 时三类日志都不输出，请求结果不受影响',
        () async {
      final on = _Captured();
      await _traffic(_dioWith(on, (w) => DiomanLog(writer: w)));
      expect(const DiomanLog().enabled, isTrue);
      expect([on.has(_reqMark), on.has(_resMark), on.has(_errMark)],
          everyElement(isTrue));

      final off = _Captured();
      final dio = _dioWith(off, (w) => DiomanLog(enabled: false, writer: w));
      final ok = await dio.post<dynamic>(_okPath);
      expect(ok.data, {'v': 1}, reason: '关掉日志不能改变响应');
      await expectLater(
          dio.post<dynamic>(_badPath),
          throwsA(isA<DioException>()
              .having((e) => e.response?.statusCode, 'status', 500)));
      expect(off.lines, isEmpty);
    });

    test(
        '[DiomanLogOptions.enabled][DiomanLogOptions.new(enabled)] 单请求 false 只静音本次；true 可在插件关闭时点亮本次；null 沿用插件',
        () async {
      final out = _Captured();
      final dio = _dioWith(out, (w) => DiomanLog(writer: w));
      await dio.post<dynamic>(_okPath,
          options: _override(const DiomanLogOptions(enabled: false)));
      expect(out.lines, isEmpty, reason: '本次被静音');
      await dio.post<dynamic>(_okPath,
          options: _override(const DiomanLogOptions(enabled: null)));
      expect(out.has(_reqMark), isTrue, reason: 'null 沿用插件的 enabled=true');

      final closed = _Captured();
      final off = _dioWith(closed, (w) => DiomanLog(enabled: false, writer: w));
      await off.post<dynamic>(_okPath);
      expect(closed.lines, isEmpty);
      await off.post<dynamic>(_okPath,
          options: _override(const DiomanLogOptions(enabled: true)));
      expect(closed.has(_reqMark) && closed.has(_resMark), isTrue,
          reason: 'true 覆盖插件的 enabled=false');
    });
  });

  group('DiomanLog 分类开关 logRequest/logResponse/logError', () {
    test(
        '[DiomanLog.logRequest][DiomanLog.new(logRequest)] 默认记录请求；false 时只丢请求行，响应与错误行仍在',
        () async {
      final out = _Captured();
      await _traffic(
          _dioWith(out, (w) => DiomanLog(logRequest: false, writer: w)));
      expect(const DiomanLog().logRequest, isTrue);
      expect(out.has('→'), isFalse);
      expect(out.has(_resMark) && out.has(_errMark), isTrue);
    });

    test(
        '[DiomanLogOptions.logRequest][DiomanLogOptions.new(logRequest)] 单请求能双向覆盖插件的 logRequest',
        () async {
      final quiet = _Captured();
      await _dioWith(quiet, (w) => DiomanLog(writer: w)).post<dynamic>(_okPath,
          options: _override(const DiomanLogOptions(logRequest: false)));
      expect(quiet.has('→'), isFalse);
      expect(quiet.has(_resMark), isTrue, reason: '只影响请求行');

      final loud = _Captured();
      await _dioWith(loud, (w) => DiomanLog(logRequest: false, writer: w))
          .post<dynamic>(_okPath,
              options: _override(const DiomanLogOptions(logRequest: true)));
      expect(loud.has(_reqMark), isTrue);
    });

    test(
        '[DiomanLog.logResponse][DiomanLog.new(logResponse)] 默认记录成功响应；false 时只丢响应行，请求与错误行仍在',
        () async {
      final out = _Captured();
      await _traffic(
          _dioWith(out, (w) => DiomanLog(logResponse: false, writer: w)));
      expect(const DiomanLog().logResponse, isTrue);
      expect(out.has('←'), isFalse);
      expect(out.has(_reqMark) && out.has(_errMark), isTrue);
    });

    test(
        '[DiomanLogOptions.logResponse][DiomanLogOptions.new(logResponse)] 单请求能双向覆盖插件的 logResponse',
        () async {
      final quiet = _Captured();
      await _dioWith(quiet, (w) => DiomanLog(writer: w)).post<dynamic>(_okPath,
          options: _override(const DiomanLogOptions(logResponse: false)));
      expect(quiet.has('←'), isFalse);
      expect(quiet.has(_reqMark), isTrue);

      final loud = _Captured();
      await _dioWith(loud, (w) => DiomanLog(logResponse: false, writer: w))
          .post<dynamic>(_okPath,
              options: _override(const DiomanLogOptions(logResponse: true)));
      expect(loud.has(_resMark), isTrue);
    });

    test(
        '[DiomanLog.logError][DiomanLog.new(logError)] 默认记录错误行；false 时错误行和错误体都不输出，异常照常抛出',
        () async {
      final out = _Captured();
      await _traffic(
          _dioWith(out, (w) => DiomanLog(logError: false, writer: w)));
      expect(const DiomanLog().logError, isTrue);
      expect(out.has('✗'), isFalse);
      expect(out.has('Error body:'), isFalse);
      expect(out.has(_reqMark) && out.has(_resMark), isTrue);
    });

    test(
        '[DiomanLogOptions.logError][DiomanLogOptions.new(logError)] 单请求能双向覆盖插件的 logError',
        () async {
      final quiet = _Captured();
      await expectLater(
          _dioWith(quiet, (w) => DiomanLog(writer: w)).post<dynamic>(_badPath,
              options: _override(const DiomanLogOptions(logError: false))),
          throwsA(isA<DioException>()));
      expect(quiet.has('✗'), isFalse);

      final loud = _Captured();
      await expectLater(
          _dioWith(loud, (w) => DiomanLog(logError: false, writer: w))
              .post<dynamic>(_badPath,
                  options: _override(const DiomanLogOptions(logError: true))),
          throwsA(isA<DioException>()));
      expect(loud.has(_errMark), isTrue);
    });
  });

  group('DiomanLog 内容开关 logHeaders/logBody', () {
    /// 带自定义请求头发一次成功请求，返回所有日志。
    Future<_Captured> run(DiomanLog Function(LogWriter w) make,
        {DiomanLogOptions? override, Object? data}) async {
      final out = _Captured();
      await _dioWith(out, make).post<dynamic>(_okPath,
          data: data,
          options: override == null
              ? Options(headers: {_reqHeader: '1'})
              : _override(override, headers: {_reqHeader: '1'}));
      return out;
    }

    test(
        '[DiomanLog.logHeaders][DiomanLog.new(logHeaders)] 默认不输出头；true 时请求与响应日志都带头',
        () async {
      expect(const DiomanLog().logHeaders, isFalse);
      final off = await run((w) => DiomanLog(writer: w));
      expect(off.has('Headers:'), isFalse);

      final on = await run((w) => DiomanLog(logHeaders: true, writer: w));
      expect(on.lines.where((l) => l.contains('Headers:')), hasLength(2));
      expect(on.lines.first, contains(_reqHeader), reason: '请求头在请求日志里');
      expect(on.lines.last, contains(_resHeader), reason: '响应头在响应日志里');
    });

    test(
        '[DiomanLogOptions.logHeaders][DiomanLogOptions.new(logHeaders)] 单请求能双向覆盖插件的 logHeaders',
        () async {
      final on = await run((w) => DiomanLog(writer: w),
          override: const DiomanLogOptions(logHeaders: true));
      expect(on.has(_reqHeader) && on.has(_resHeader), isTrue);

      final off = await run((w) => DiomanLog(logHeaders: true, writer: w),
          override: const DiomanLogOptions(logHeaders: false));
      expect(off.has('Headers:'), isFalse);
    });

    test(
        '[DiomanLog.logBody][DiomanLog.new(logBody)] 默认输出请求/响应/错误体；false 时都不输出',
        () async {
      expect(const DiomanLog().logBody, isTrue);
      final out = _Captured();
      await _traffic(_dioWith(out, (w) => DiomanLog(writer: w)),
          data: 'payload');
      expect(out.lines.first, contains('Body: payload'));
      expect(out.lines.any((l) => l.contains('Body: {v: 1}')), isTrue);
      expect(out.has('Error body: {fail: true}'), isTrue);

      final off = _Captured();
      await _traffic(_dioWith(off, (w) => DiomanLog(logBody: false, writer: w)),
          data: 'payload');
      expect(off.has('Body:'), isFalse);
      expect(off.has('Error body:'), isFalse);
      expect(
          off.has(_reqMark) && off.has(_resMark) && off.has(_errMark), isTrue,
          reason: '只关 body，不影响日志行本身');
    });

    test(
        '[DiomanLogOptions.logBody][DiomanLogOptions.new(logBody)] 单请求能双向覆盖插件的 logBody',
        () async {
      final off = await run((w) => DiomanLog(writer: w),
          override: const DiomanLogOptions(logBody: false), data: 'payload');
      expect(off.has('Body:'), isFalse);

      final on = await run((w) => DiomanLog(logBody: false, writer: w),
          override: const DiomanLogOptions(logBody: true), data: 'payload');
      expect(on.has('Body: payload'), isTrue);
    });
  });

  test(
      '[DiomanLog.logBody] 请求体为 Uint8List 之类非 null 数据时按 toString 输出，null 体不输出 Body 行',
      () async {
    final out = _Captured();
    final dio = _dioWith(out, (w) => DiomanLog(writer: w));
    await dio.post<dynamic>(_okPath, data: Uint8List.fromList([1, 2]));
    expect(out.lines.first, contains('Body: [1, 2]'));
    out.lines.clear();
    await dio.post<dynamic>(_okPath);
    expect(out.lines.first.contains('Body:'), isFalse);
  });
}
