import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import 'package:dio/dio.dart';
import '../support/helpers.dart';
import '../support/fake_network.dart';

/// 本主题共用的测试值。
const _diomanLiteral0 = "get";

/// 本主题共用的测试值。
const _diomanLiteral1 = "post";

/// 本主题共用的测试值。
const _diomanLiteral2 = "put";

/// 本主题共用的测试值。
const _diomanLiteral3 = "patch";

/// 本主题共用的测试值。
const _diomanLiteral4 = "delete";

/// 本主题共用的测试值。
const _diomanLiteral5 = "head";

/// 本主题共用的测试值。
const _diomanLiteral6 = "request";

/// 本主题共用的测试值。
const _diomanLiteral7 = "GET";

/// 本主题共用的测试值。
const _diomanLiteral8 = "observe";

/// 本主题共用的测试值。
const _diomanLiteral9 = "http";

/// 本主题共用的测试值。
const _diomanLiteral10 = "business";

/// 本主题共用的测试值。
const _diomanLiteral11 = "network";

/// 本主题共用的测试值。
const _diomanLiteral12 = "cancel";

/// 解码测试的请求路径。
const _path = '/user';

/// 解码测试的字段名。
const _name = 'name';

/// 解码测试的原始数据。
const _body = {_name: 'Ada'};

/// 调用方的数据模型。
class User {
  /// 保存姓名。
  User(this.name);

  /// 从响应数据创建用户。
  factory User.fromJson(Object? data) => User((data as Map)[_name] as String);

  /// 用户姓名。
  final String name;
}

/// 请求成功落定后的调用方解码验证。
void main() {
  for (final method in [
    _diomanLiteral0,
    _diomanLiteral1,
    _diomanLiteral2,
    _diomanLiteral3,
    _diomanLiteral4,
    _diomanLiteral5,
    _diomanLiteral6
  ]) {
    test(
        '[Dioman.get(decode)][Dioman.post(decode)][Dioman.put(decode)]'
        '[Dioman.patch(decode)][Dioman.delete(decode)][Dioman.head(decode)]'
        '[Dioman.request(decode)] $method decode 将成功数据转换为 User', () async {
      final verb =
          method == _diomanLiteral6 ? _diomanLiteral7 : method.toUpperCase();
      final api = testClient(
          network: FakeNetwork()
            ..routes['$verb:$_path'] = [const FakeReply(body: _body)]);
      final send = switch (method) {
        _diomanLiteral0 => api.get<User>,
        _diomanLiteral1 => api.post<User>,
        _diomanLiteral2 => api.put<User>,
        _diomanLiteral3 => api.patch<User>,
        _diomanLiteral4 => api.delete<User>,
        _diomanLiteral5 => api.head<User>,
        _ => (String path,
                {Map<String, dynamic>? query,
                Object? data,
                DiomanCall? call,
                User Function(Object?)? decode}) =>
            api.request<User>(_diomanLiteral7, path,
                query: query, data: data, call: call, decode: decode),
      };
      final user = await send(_path, decode: User.fromJson);
      expect(user.name, _body[_name]);
      expect(api.pending, 0);
    });
  }

  test('[Dioman.send][Dioman.send(decode)] 解码副本保留其他字段和原生对象，允许 null', () async {
    Result? settled;
    final api = testClient(
        network: FakeNetwork()
          ..routes['GET:$_path'] = [const FakeReply(body: _body)],
        plugins: [
          TestPlugin(_diomanLiteral8, handler: (ctx, next) async {
            settled = await next();
            return settled!;
          })
        ]);
    final r = await api.send<User>(_diomanLiteral7, _path,
        decode: User.fromJson, call: const DiomanCall(raw: true));
    expect(r.data!.name, _body[_name]);
    expect(r.ok, settled!.ok);
    expect(r.status, settled!.status);
    expect(r.code, settled!.code);
    expect(r.message, settled!.message);
    expect(r.request, same(settled!.request));
    expect(r.raw!.data, _body);
    expect(r.error, isNull);
    expect(r.callSite, settled!.callSite);
    expect(failureOf(r), isNull);
    expect(settled!.data, _body);
    final nullable =
        await api.send<Object?>(_diomanLiteral7, _path, decode: (_) => null);
    expect(nullable.data, isNull);
  });

  for (final failure in [
    _diomanLiteral9,
    _diomanLiteral10,
    _diomanLiteral11,
    _diomanLiteral12
  ]) {
    test('[Dioman.send][Dioman.request] $failure 失败不调用 decode', () async {
      var calls = 0;
      final token = CancelToken();
      if (failure == _diomanLiteral12) token.cancel();
      final api = testClient(
          network: FakeNetwork()
            ..routes['GET:$_path'] = [
              FakeReply(
                  status: failure == _diomanLiteral9 ? 503 : 200,
                  body: failure == _diomanLiteral10
                      ? {'code': 1, 'data': _body}
                      : _body,
                  error: failure == _diomanLiteral11
                      ? DioException(
                          requestOptions: RequestOptions(path: _path),
                          type: DioExceptionType.connectionError)
                      : null)
            ]);

      /// 记录是否错误地解码失败。
      User decode(Object? data) {
        calls++;
        return User.fromJson(data);
      }

      final call = DiomanCall(cancelToken: token);
      final r = await api.send<User>(_diomanLiteral7, _path,
          call: call, decode: decode);
      expect(r.ok, isFalse);
      await expectLater(api.get<User>(_path, call: call, decode: decode),
          throwsA(isA<DiomanResponse>()));
      expect(calls, 0);
    });
  }

  for (final send in [false, true]) {
    test('[Dioman.send][Dioman.get] decode 异常原对象原栈，不经过插件', () async {
      var notifications = 0;
      var pluginExits = 0;
      final api = testClient(plugins: [
        DiomanNotify(notify: (_, __) => notifications++),
        TestPlugin(_diomanLiteral8, handler: (_, next) async {
          final result = await next();
          expect(result.ok, isTrue);
          pluginExits++;
          return result;
        }),
      ]);
      final bug = StateError('decode bug');
      final stack = StackTrace.fromString('decode original stack');

      /// 固定抛出同一异常与栈。
      User decode(Object? _) => Error.throwWithStackTrace(bug, stack);
      try {
        if (send) {
          await api.send<User>(_diomanLiteral7, _path, decode: decode);
        } else {
          await api.get<User>(_path, decode: decode);
        }
        fail('应抛解码错误');
      } catch (e, s) {
        expect(e, same(bug));
        expect(s.toString(), stack.toString());
      }
      expect(pluginExits, 1);
      expect(notifications, 0);
      expect(api.pending, 0);
    });
  }

  test('[Dioman.send][Dioman.get] share 跟随者各自解码，异常不污染同组', () async {
    final gate = Completer<void>();
    final network = FakeNetwork()
      ..routes['GET:$_path'] = [FakeReply(body: _body, gate: gate.future)];
    final api = testClient(network: network, plugins: [const DiomanShare()]);
    final call = DiomanCall(options: {DiomanShare.option: true});
    final first = api.get<User>(_path, call: call, decode: User.fromJson);
    await flush();
    final second = api.send<String>(_diomanLiteral7, _path,
        call: call, decode: (data) => (data as Map)[_name] as String);
    final bug = StateError('follower decode');
    final third = api.get<User>(_path, call: call, decode: (_) => throw bug);
    final caught = expectLater(third, throwsA(same(bug)));
    await flush();
    gate.complete();
    expect((await first).name, _body[_name]);
    expect((await second).data, _body[_name]);
    await caught;
    expect(network.sends, hasLength(1));
  });
}
