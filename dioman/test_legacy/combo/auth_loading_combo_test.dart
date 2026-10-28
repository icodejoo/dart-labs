// ignore_for_file: avoid_relative_lib_imports
// 组合层：auth_loading
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('pairwise: loading + auth', () {
// Now automatable with a real server: the replay reaches this
// TestServer, so the FULL successful refresh+replay path can be
// exercised (this was previously downgraded to a "refresh fails" test
// because the replay used to go out over the real internet).
    test(
        '[DiomanAuth.new(onAccessExpired) × DiomanLoading.new(onChanged)] a 401 that DiomanAuth successfully refreshes+replays only settles '
        'the loading counter ONCE, at the point the replayed response '
        'finally lands — no premature 0-edge from the initial 401', () async {
      final tm = TestTokens(tkT0);
      var attempts = 0;
      final server = await TestServer.start((req) async {
        attempts++;
        if (attempts == 1) return respondJson(req, {tkError: 1}, 401);
        return respondJson(req, {tkV: tkOk}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      installStateful(
        dio,
        loading: DiomanLoading(onChanged: states.add),
        auth: DiomanAuth(
          tokenManager: tm,
          onRefresh: (_, __) async => tm.set(tkT1),
          onAccessExpired: (_, __) async {},
        ),
      );

      final r = await dio.get<Map<String, dynamic>>(tkData2);
      expect(r.data, {tkV: tkOk});
      expect(attempts, 2);
      expect(states, [true, false],
          reason: "auth's whole refresh-then-replay dance happens inside "
              "ONE onError pass (it resolves the error directly via "
              'handler.resolve) — loading only ever sees a single settle '
              'for this request, no flicker');
    });
  });
}
