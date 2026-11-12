import 'package:dioman/src/diagnostics.dart';
import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../support/source_test_helpers.dart';
import '../support/fake_network.dart';
import '../support/helpers.dart';


/// 验证对应主题的行为与边界。
void main() {
  test(
      '[DiomanOffline.new(isOnline)][DiomanOffline.new(onConnectivityChanged)][DiomanOfflineApi.pending]'
      '[DiomanOffline.shouldQueue] 在线直接放行且不调用排队判定回调', () async {
    final stream = StreamController<bool>.broadcast(sync: true);
    addTearDown(stream.close);
    final net = FakeNetwork();
    var checks = 0;
    final api = testClient(network: net, plugins: [
      DiomanOffline<Result>(
          isOnline: () => true,
          onConnectivityChanged: stream.stream,
          shouldQueue: (_) {
            checks++;
            throw StateError(b4LiteralEmpty);
          })
    ]);
    expect((await api.send<Object?>(b4Get, b4Path)).ok, isTrue);
    expect(checks, 0);
    expect(net.sends.length, 1);
    expect(api.plugin<DiomanOfflineApi>()!.pending, 0);
    expect(api.cancellationSubscriptions, 0);
    api.dispose();
  });
}
