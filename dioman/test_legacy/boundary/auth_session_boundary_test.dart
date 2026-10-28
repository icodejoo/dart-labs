// 边界层：auth / 刷新窗口与会话过期通知
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/support/fixtures.dart';

/// 并发请求数。
const _n = 5;

/// 受保护的测试路径。
const _path = '/p';

/// 默认的授权头字段名。
const _authHeader = 'Authorization';

/// 构造 Bearer 头的值。
String _bearer(String token) => 'Bearer $token';

/// 并发发起 [count] 个请求，断言全部以 [DioException] 失败。
Future<void> _allFail(Dio dio, [int count = _n]) => Future.wait(List.generate(
    count,
    (_) => expectLater(dio.get<dynamic>(_path), throwsA(isA<DioException>()))));

/// 按携带的 token 返回响应：只有 [good] 得 200，其余 401。
RecordingAdapter _adapterAccepting(String good) =>
    RecordingAdapter((o, n) async =>
        jsonBody({}, o.headers[_authHeader] == _bearer(good) ? 200 : 401));

/// 注册本文件的边界层用例。
void main() {
  group('onRefresh 同步抛错不卡死刷新窗口', () {
    test(
        '[DiomanAuth.new(onRefresh)] 非 async 的 onRefresh 第一次同步抛错：该请求失败，之后再触发刷新会再次调用并恢复',
        () async {
      final tm = TestTokens('t0');
      final dio = fakeDio(_adapterAccepting('t1'));
      var refreshCalls = 0;
      Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: tm,
            // 故意不是 async：第一次在返回 Future 之前就同步抛错。
            onRefresh: (_, __) {
              refreshCalls++;
              if (refreshCalls == 1) throw StateError('sync boom');
              tm.set('t1');
              return Future<void>.value();
            },
            onAccessExpired: (_, __) async {},
          ));

      await expectLater(dio.get<dynamic>(_path), throwsA(isA<DioException>()));
      expect(refreshCalls, 1);

      tm.set('t0'); // 刷新失败后会话已被清掉，使用者重新登录
      final r = await dio.get<dynamic>(_path);
      expect(r.statusCode, 200);
      expect(refreshCalls, 2, reason: '窗口已重新打开，onRefresh 再次被调用');
      expect(tm.accessToken, 't1');
    });

    test('[DiomanAuth.new(onRefresh)] 同步抛错期间并发的多个请求都失败，onRefresh 只调用一次，之后能恢复',
        () async {
      final tm = TestTokens('t0');
      final dio = fakeDio(_adapterAccepting('t1'));
      var refreshCalls = 0;
      Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) {
              refreshCalls++;
              if (refreshCalls == 1) throw StateError('sync boom');
              tm.set('t1');
              return Future<void>.value();
            },
            onAccessExpired: (_, __) async {},
          ));

      await _allFail(dio);
      expect(refreshCalls, 1, reason: '并发请求共用同一个刷新窗口');

      tm.set('t0');
      final r = await dio.get<dynamic>(_path);
      expect(r.statusCode, 200);
      expect(refreshCalls, 2);
    });
  });

  group('onAccessExpired 会话标识', () {
    test(
        '[DiomanAuth.new(onAccessExpired)] 并发 N 个请求同时 401 且刷新失败，onAccessExpired 只调用一次',
        () async {
      final tm = TestTokens('old');
      final dio = fakeDio(_adapterAccepting('never'));
      var expired = 0;
      Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async {
              await settleAsync(10);
              throw StateError('refresh failed');
            },
            onAccessExpired: (_, __) async => expired++,
          ));

      await _allFail(dio);
      expect(expired, 1);
      expect(tm.accessToken, isNull);
    });

    test(
        '[DiomanAuth.new(onAccessExpired)] 过期后使用者重新登录，旧会话迟到的 401 不会清掉新 token，也不会再通知',
        () async {
      final tm = TestTokens('old');
      final lateGate = Completer<void>();
      final adapter = RecordingAdapter((o, n) async {
        if (o.path == '/late') await lateGate.future;
        return jsonBody({}, 401);
      });
      final dio = fakeDio(adapter);
      var expired = 0;
      Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async {},
            // 任何 401 都直接判会话过期，专门走"过期动作"这条路径。
            onFailure: (_, r) => r.statusCode == 401
                ? DiomanAuthFailureAction.expired
                : DiomanAuthFailureAction.others,
            onAccessExpired: (_, __) async => expired++,
          ));

      // /late 带着旧 token 出发后被挂起。
      final late = dio.get<dynamic>('/late');
      final lateDone = expectLater(late, throwsA(isA<DioException>()));
      await settleAsync();
      // 同一会话的另一个请求先 401：清 token 并通知一次。
      await expectLater(dio.get<dynamic>(_path), throwsA(isA<DioException>()));
      expect(expired, 1);
      expect(tm.accessToken, isNull);

      tm.set('new'); // 使用者直接重新登录，没走刷新
      lateGate.complete();
      await lateDone;

      expect(tm.accessToken, 'new', reason: '旧会话的 401 不能清掉新会话');
      expect(expired, 1, reason: '同一旧会话不重复通知');
    });

    test('[DiomanAuth.new(onAccessExpired)] 刷新进行中使用者重新登录，随后刷新失败：不清新 token，不通知',
        () async {
      final tm = TestTokens('old');
      final refreshGate = Completer<void>();
      final dio = fakeDio(_adapterAccepting('never'));
      var expired = 0;
      Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async {
              await refreshGate.future;
              throw StateError('refresh failed');
            },
            onAccessExpired: (_, __) async => expired++,
          ));

      final pending = Future.wait(List.generate(
          3,
          (_) => expectLater(
              dio.get<dynamic>(_path), throwsA(isA<DioException>()))));
      await settleAsync();
      tm.set('new');
      refreshGate.complete();
      await pending;

      expect(tm.accessToken, 'new');
      expect(expired, 0);
    });

    test('[DiomanAuth.new(onAccessExpired)] 新会话之后再过期会再次通知一次（含重新登录拿到同名 token）',
        () async {
      final tm = TestTokens('old');
      final dio = fakeDio(_adapterAccepting('never'));
      var expired = 0;
      Dioman.install(dio,
          auth: DiomanAuth(
            tokenManager: tm,
            onRefresh: (_, __) async {
              await settleAsync(10);
              throw StateError('refresh failed');
            },
            onAccessExpired: (_, __) async => expired++,
          ));

      await _allFail(dio);
      expect(expired, 1);

      tm.set('new');
      await _allFail(dio);
      expect(expired, 2, reason: '新会话过期再通知一次，且整波只通知一次');

      tm.set('new'); // 重新登录又拿到同一个字符串
      await _allFail(dio);
      expect(expired, 3);
    });
  });
}
