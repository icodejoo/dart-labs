import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/request_claims.dart';
import 'package:test/test.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 认证配置用例的请求路径。
const _path = '/auth-options';

/// 初始的旧访问令牌。
const _old = 'old';

/// 刷新后换上的新访问令牌。
const _fresh = 'fresh';

/// 服务端读取的认证请求头名。
const _header = 'authorization';

/// 一天，用作到期时间偏移与提前量。
const _day = Duration(days: 1);

/// 参数化场景：请求级覆盖 expiresAt。
const _expiryMode = 'expiresAt';

/// 参数化场景：请求级覆盖 now 时钟。
const _clockMode = 'now';

/// 参数化场景：请求级覆盖 refreshLeeway。
const _leewayMode = 'refreshLeeway';

/// 参数化场景：只用构造参数，不做请求级覆盖。
const _constructorMode = 'constructor';

/// 刷新后期望出现在请求头里的完整值。
const _freshHeader = 'Bearer $_fresh';

/// 注册认证配置、令牌契约与结算出口的规则测试。
void main() {
  test('[DiomanAuth.name][DiomanAuth.pluginName] 固定名称用于安装后的插件查找', () {
    final dio = Dio();
    final auth = testAuth(TestTokens(_old));
    final handle = Dioman.install(dio, auth: auth);
    addTearDown(() {
      handle.dispose();
      dio.close(force: true);
    });
    expect(auth.name, 'dioman:auth');
    expect(DiomanAuth.pluginName, auth.name);
    expect(handle.plugins.singleWhere((p) => p.name == DiomanAuth.pluginName),
        same(auth));
  });

  test(
      '[DiomanAuth.new(tokenManager)][DiomanTokenManager.accessToken] 所有请求读取同一管理器的当前令牌，空值拒绝发送',
      () async {
    final seen = <String?>[];
    final server = await TestServer.start((r) async {
      seen.add(r.headers.value(_header));
      await respondJson(r, {}, 200);
    });
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final tokens = TestTokens(null);
    final handle = Dioman.install(dio, auth: testAuth(tokens));
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    expect(tokens.accessToken, isNull);
    await expectLater(dio.get<void>(_path), throwsA(isA<DioException>()));
    tokens.set(_old);
    expect(tokens.accessToken, _old);
    await dio.get<void>(_path);
    tokens.set(_fresh);
    await dio.get<void>(_path,
        options:
            Options(extra: {DiomanAuth.pluginName: const DiomanAuthOptions()}));
    expect(seen, ['Bearer $_old', _freshHeader]);
  });

  test(
      '[DiomanTokenManager.canRefresh][DiomanTokenManager.refreshToken] 默认路由不读取刷新能力或刷新令牌，仍调用刷新回调',
      () async {
    final tokens = _UnreadRefreshTokens();
    var refreshes = 0;
    final server = await TestServer.start((r) => respondJson(
        r, {}, r.headers.value(_header) == _freshHeader ? 200 : 401));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
          tokenManager: tokens,
          onRefresh: (manager, _) async {
            expect(manager, same(tokens));
            refreshes++;
            tokens.set(_fresh);
          },
          onAccessExpired: (_, __) async {},
        ));
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await dio.get<void>(_path);
    expect(refreshes, 1);
    expect(tokens.reads, 0);
    expect(tokens.canRefresh, isFalse);
    expect(tokens.refreshToken, isNull);
  });

  test('[DiomanAuth.new(refreshLeeway)] 默认不提前刷新，到期等号触发刷新', () async {
    var now = DateTime.utc(2026);
    final at = now.add(_day);
    var refreshes = 0;
    final server = await TestServer.start((r) => respondJson(r, {}, 200));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final handle = Dioman.install(dio,
        auth: DiomanAuth(
          tokenManager: TestTokens(_old),
          expiresAt: (_) => at,
          now: () => now,
          onRefresh: (_, __) async {
            refreshes++;
          },
          onAccessExpired: (_, __) async {},
        ));
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await dio.get<void>(_path);
    expect(refreshes, 0);
    now = at;
    await dio.get<void>(_path);
    expect(refreshes, 1);
  });

  for (final mode in [_expiryMode, _clockMode, _leewayMode, _constructorMode]) {
    test(
        '[DiomanAuthOptions.expiresAt][DiomanAuthOptions.now][DiomanAuthOptions.refreshLeeway][DiomanAuth.new(refreshLeeway)] $mode 覆盖、空值继承与到期等号边界',
        () async {
      final instant = DateTime.utc(2026);
      var refreshes = 0;
      final seen = <String?>[];
      final server = await TestServer.start((r) async {
        seen.add(r.headers.value(_header));
        await respondJson(r, {}, 200);
      });
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final tokens = TestTokens(_old);
      final at = instant.add(_day);
      final override = DiomanAuthOptions(
        expiresAt: mode == _expiryMode ? (_) => instant : null,
        now: mode == _clockMode ? () => at : null,
        refreshLeeway: mode == _leewayMode ? _day : null,
      );
      const defaults = DiomanAuthOptions();
      expect(defaults.expiresAt, isNull);
      expect(defaults.now, isNull);
      expect(defaults.refreshLeeway, isNull);
      if (mode == _expiryMode) expect(override.expiresAt!(_old), instant);
      if (mode == _clockMode) expect(override.now!(), at);
      if (mode == _leewayMode) expect(override.refreshLeeway, _day);
      final auth = DiomanAuth(
        tokenManager: tokens,
        expiresAt: (token) => token == _fresh ? at.add(_day) : at,
        now: () => instant,
        refreshLeeway: mode == _constructorMode ? _day : Duration.zero,
        onRefresh: (_, __) async {
          refreshes++;
          tokens.set(_fresh);
        },
        onAccessExpired: (_, __) async {},
      );
      final handle = Dioman.install(dio, auth: auth);
      addTearDown(() async {
        handle.dispose();
        dio.close(force: true);
        await server.close();
      });
      if (mode != _constructorMode) {
        await dio.get<void>(_path,
            options: Options(extra: {auth.name: defaults}));
        expect(refreshes, 0, reason: '默认提前量为零，空覆盖继承未来到期时间');
      }
      await dio.get<void>(_path,
          options: Options(extra: {auth.name: override}));
      expect(refreshes, 1, reason: '到期时刻等于 now + leeway 时也刷新');
      expect(seen.last, _freshHeader);
      expect(seen.length, mode == _constructorMode ? 1 : 2);
    });
  }

  for (final expired in [false, true]) {
    test(
        '[DiomanAuthOptions.onAccessDenied][DiomanAuthOptions.onAccessExpired] expired=$expired 回调单请求覆盖，空值继承',
        () async {
      var inherited = 0;
      var overridden = 0;
      final server = await TestServer.start((r) => respondJson(r, {}, 401));
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final tokens = TestTokens(expired ? _old : null);
      final auth = DiomanAuth(
        tokenManager: tokens,
        onRefresh: (_, __) async {},
        onFailure: (_, __) => DiomanAuthFailureAction.expired,
        onAccessDenied: (_, __) async {
          inherited++;
        },
        onAccessExpired: (_, __) async {
          inherited++;
        },
      );

      /// 记录当前请求的覆盖回调。
      Future<void> callback(
          DiomanTokenManager manager, Response<dynamic> response) async {
        expect(manager, same(tokens));
        expect(response.statusCode, expired ? 401 : 0);
        overridden++;
      }

      final override = DiomanAuthOptions(
          onAccessDenied: expired ? null : callback,
          onAccessExpired: expired ? callback : null);
      const defaults = DiomanAuthOptions();
      expect(defaults.onAccessDenied, isNull);
      expect(defaults.onAccessExpired, isNull);
      expect(expired ? override.onAccessExpired : override.onAccessDenied,
          same(callback));
      final handle = Dioman.install(dio, auth: auth);
      addTearDown(() async {
        handle.dispose();
        dio.close(force: true);
        await server.close();
      });
      await expectLater(
          dio.get<void>(_path, options: Options(extra: {auth.name: override})),
          throwsA(isA<DioException>()));
      expect(overridden, 1);
      expect(inherited, 0);
      if (expired) tokens.set(_old);
      await expectLater(
          dio.get<void>(_path, options: Options(extra: {auth.name: defaults})),
          throwsA(isA<DioException>()));
      expect(inherited, 1);
      expect(overridden, 1);
    });
  }

  test('[DiomanAuth.onResponse] 成功清临时标记并交出认领，保留业务 extra', () async {
    final server = await TestServer.start((r) => respondJson(r, {}, 200));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    final auth = testAuth(TestTokens(_old));
    final handle = Dioman.install(dio, auth: auth);
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    final result =
        await dio.get<void>(_path, options: Options(extra: {_path: 1}));
    final options = result.requestOptions;
    expect(options.extra.keys.where((key) => key.startsWith('${auth.name}:')),
        ['${auth.name}:decision']);
    expect(options.extra[_path], 1);
    expect(claimsOf(options)!.has(auth), isFalse);
    expect(claimsOf(options)!.isFinished, isTrue);
  });

  test('[DiomanAuthFailureAction.others] 非认证错误原样传出、清临时标记且不调用恢复回调', () async {
    var callbacks = 0;
    DioException? original;
    final server = await TestServer.start((r) => respondJson(r, {}, 500));
    final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
    dio.interceptors.add(InterceptorsWrapper(onError: (error, handler) {
      original = error;
      handler.next(error);
    }));
    final auth = DiomanAuth(
        tokenManager: TestTokens(_old),
        onRefresh: (_, __) async {
          callbacks++;
        },
        onAccessExpired: (_, __) async {
          callbacks++;
        });
    final handle = Dioman.install(dio, auth: auth);
    addTearDown(() async {
      handle.dispose();
      dio.close(force: true);
      await server.close();
    });
    await expectLater(dio.get<void>(_path),
        throwsA(predicate<DioException>((error) {
      expect(error, same(original));
      expect(claimsOf(error.requestOptions)!.hasOwners, isFalse);
      expect(
          error.requestOptions.extra.keys
              .where((key) => key.startsWith('${auth.name}:')),
          ['${auth.name}:decision']);
      return error.response?.statusCode == 500;
    })));
    expect(callbacks, 0);
  });
}

/// 记录刷新契约 getter 的读取次数，证明默认认证流程无需读取它们。
class _UnreadRefreshTokens extends TestTokens {
  /// 使用一个需要刷新后才能通过服务器校验的令牌。
  _UnreadRefreshTokens() : super(_old);

  /// 刷新契约 getter 的读取次数。
  int reads = 0;

  /// 返回不可刷新的契约值，并记录读取。
  @override
  bool get canRefresh {
    reads++;
    return false;
  }

  /// 返回空刷新令牌，并记录读取。
  @override
  String? get refreshToken {
    reads++;
    return null;
  }
}
