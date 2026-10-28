// ignore_for_file: avoid_relative_lib_imports
// 规则层：timeout
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group('timeout 两级查找（simplify）', () {
    test(
        '[DiomanTimeout.timeouts][DiomanTimeout.new(probe)] 单请求覆盖只替换对应档位，其余档位回落到插件配置',
        () async {
      final adapter = RecordingAdapter((o, n) async => jsonBody({tkV: 1}, 200));
      final dio = fakeDio(adapter);
      var quality = NetworkQuality.poor;
      Dioman.install(dio,
          timeout: DiomanTimeout(
            probe: () => quality,
            timeouts: {
              NetworkQuality.poor:
                  const DiomanTimeouts(connect: Duration(seconds: 30)),
              NetworkQuality.good:
                  const DiomanTimeouts(connect: Duration(seconds: 15)),
            },
          ));
      final override = Options(extra: {
        DiomanTimeout.pluginName: const DiomanTimeoutOptions(timeouts: {
          NetworkQuality.good: DiomanTimeouts(connect: Duration(seconds: 1)),
        }),
      });

      await dio.get<dynamic>(tkX, options: override);
      expect(adapter.seen.last.connectTimeout, const Duration(seconds: 30));
      quality = NetworkQuality.good;
      await dio.get<dynamic>(tkX, options: override);
      expect(adapter.seen.last.connectTimeout, const Duration(seconds: 1));
      quality = NetworkQuality.none;
      await dio.get<dynamic>(tkX, options: override);
      expect(
          adapter.seen.last.connectTimeout, isNot(const Duration(seconds: 1)));
    });
  });

  group(tkDiomanTimeout, () {
    test(
        '[DiomanTimeouts.receive][DiomanTimeout.timeouts] applies the matched tier: short receive times out, generous is ok',
        () async {
      final server = await TestServer.start((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      var quality = NetworkQuality.poor;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanTimeout(
        probe: () => quality,
        timeouts: const {
          NetworkQuality.poor:
              DiomanTimeouts(receive: Duration(milliseconds: 100)),
          NetworkQuality.excellent:
              DiomanTimeouts(receive: Duration(seconds: 2)),
        },
      ));

      // poor → 100ms receive against a 300ms server → receiveTimeout.
      await expectLater(
        dio.get<dynamic>(tkX),
        throwsA(isA<DioException>()
            .having((e) => e.type, tkType, DioExceptionType.receiveTimeout)),
      );

      // excellent → 2s receive → succeeds.
      quality = NetworkQuality.excellent;
      final r = await dio.get<dynamic>(tkX);
      expect(r.statusCode, 200);
    });
    test(
        '[DiomanTimeout.onRequest][DiomanTimeout.timeouts] only non-null fields are written; others keep BaseOptions',
        () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      final captured = <String, Duration?>{};
      final dio = Dio(BaseOptions(
        baseUrl: server.baseUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 5),
      ));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.poor,
        timeouts: const {
          // Only connect is set for this tier.
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured[tkConnect] = o.connectTimeout;
        captured[tkReceive] = o.receiveTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>(tkX);
      expect(captured[tkConnect], const Duration(seconds: 7),
          reason: 'connect was overridden by the tier');
      expect(captured[tkReceive], const Duration(seconds: 5),
          reason:
              'receive was null in the tier → left at the BaseOptions value');
    });
    test(
        '[DiomanTimeout.enabled][DiomanTimeout.timeouts] per-request enabled:false keeps the carried timeouts',
        () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      Duration? captured;
      final dio = Dio(BaseOptions(
        baseUrl: server.baseUrl,
        connectTimeout: const Duration(seconds: 4),
      ));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.poor,
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured = o.connectTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>(tkX,
          options: Options(extra: {
            DiomanTimeout.pluginName:
                const DiomanTimeoutOptions(enabled: false),
          }));
      expect(captured, const Duration(seconds: 4),
          reason: 'opted out → the tier override never applied');
    });
  });

  group('DiomanTimeout', () {
    test(
        '[DiomanTimeout.timeouts][DiomanTimeoutOptions.timeouts] '
        'per-request timeouts merge, overriding a single tier', () async {
      final server = await TestServer.start((req) async {
        await respondJson(req, {tkOk: true}, 200);
      });
      addTearDown(server.close);

      Duration? captured;
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      dio.interceptors.add(DiomanTimeout(
        probe: () => NetworkQuality.poor,
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        },
      ));
      dio.interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        captured = o.connectTimeout;
        h.next(o);
      }));

      await dio.get<dynamic>(tkX,
          options: Options(extra: {
            DiomanTimeout.pluginName: const DiomanTimeoutOptions(timeouts: {
              NetworkQuality.poor:
                  DiomanTimeouts(connect: Duration(seconds: 9)),
            }),
          }));
      expect(captured, const Duration(seconds: 9),
          reason: 'the per-request poor tier replaced the plugin default');
    });
  });
}
