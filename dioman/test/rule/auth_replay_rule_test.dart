import '../support/response_contract.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/auth_test_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';

const _path = '/b8';
const _put = 'PUT';
const _route = '$_put:$_path';

/// 验证对应主题的行为与边界。
void main() {
  for (final useStream in [false, true]) {
    test(
        '[DiomanContext.canReplay] B8 auth ready 的实际体决定重放 useStream=$useStream',
        () async {
      final body = Stream<Uint8List>.value(Uint8List.fromList([1, 2]));
      final net = FakeNetwork()
        ..routes[_route] = [const FakeReply(status: 401), const FakeReply()];
      var refreshes = 0;
      final api = testClient(statusOf: businessStatus, network: net, plugins: [
        b3Auth(TestTokens(),
            ready: (_, __) => RequestPatch(data: useStream ? body : {'a': 1}),
            refresh: (tm, _) {
              refreshes++;
              tm.setTokens(accessToken: b3Fresh);
            })
      ]);
      final r =
          await api.send<dynamic>(_put, _path, data: useStream ? null : body);
      expect(r.status, useStream ? 401 : 200);
      expect(net.sends.length, useStream ? 1 : 2);
      expect(refreshes, useStream ? 0 : 1);
      api.dispose();
    });
  }
}
