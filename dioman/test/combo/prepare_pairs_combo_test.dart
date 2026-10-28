import 'dart:async';
import 'package:dioman/pipeline.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/pipeline/b3_helpers.dart';
import '../support/pipeline/b5_powerset.dart';
import '../support/pipeline/fake_clock.dart';
import '../support/pipeline/fake_network.dart';
import '../support/pipeline/helpers.dart';

/// 只做请求整形的四项；envs 只在 setup 合并配置。
const prepareNames = [repathName, filterName, timeoutName, envsName];
const pairPath = '/pairs/{id}';
const shapedPath = '/pairs/7';
const pairId = 'id';
const pairEmpty = 'empty';
const pairKeep = 'keep';
const pairEnv = 'x-pair-env';
const pairUrl = 'https://pairs.test';
const pairTimeout = Duration(seconds: 7);

/// 四个整形项与其它插件共 42 对，全部检查真实 adapter 收到的配置。
void main() {
  final names = [...interactionNames, ...prepareNames];
  for (var i = 0; i < names.length; i++) {
    for (var j = i + 1; j < names.length; j++) {
      final pair = [names[i], names[j]];
      if (!pair.any(prepareNames.contains)) continue;
      test('[DiomanPlugin pairs] ${pair.join('+')} 补丁穿透发送', () async {
        final clock = FakeClock();
        final stream = StreamController<bool>.broadcast(sync: true);
        final net = FakeNetwork();
        final events = <bool>[];
        final factories = <String, DiomanPlugin<Result> Function()>{
          loadingName: () => DiomanLoading(onChanged: events.add),
          notifyName: () => DiomanNotify(notify: (_, __) {}),
          retryName: () =>
              DiomanRetry(max: 2, delay: (_, __, ___) => Duration.zero),
          breakerName: () => DiomanBreaker(),
          authName: () => b3Auth(TestTokens()),
          mockName: () => DiomanMock(mockUrl: mockUrl),
          shareName: () => DiomanShare(),
          cacheName: () => DiomanCache(),
          offlineName: () => DiomanOffline(
              isOnline: () => true, onConnectivityChanged: stream.stream),
          repathName: () => DiomanRepath(),
          filterName: () => DiomanFilter(),
          timeoutName: () =>
              DiomanTimeout(probe: () => NetworkQuality.good, timeouts: {
                NetworkQuality.good: DiomanTimeouts(
                    connect: pairTimeout,
                    send: pairTimeout,
                    receive: pairTimeout)
              }),
          envsName: () => DiomanEnvs([
                EnvRule(
                    rule: () => true,
                    config:
                        BaseOptions(baseUrl: pairUrl, headers: {pairEnv: 1}))
              ]),
        };
        final path = pair.contains(repathName) ? shapedPath : pairPath;
        final probePath = '$mockUrl${Uri(path: path).path}';
        net.routes['$flowGet:$probePath'] = [FakeReply(status: 404)];
        final api = testClient(
            network: net,
            clock: clock,
            plugins: [for (final name in pair.reversed) factories[name]!()]);
        try {
          final response = await api.send<dynamic>(flowGet, pairPath,
              query: {pairId: 7, pairEmpty: null},
              data: {pairEmpty: null, pairKeep: 1},
              call: DiomanCall(options: {
                DiomanShare.option: true,
                DiomanCache.option: true,
              }));
          expect(response.ok, isTrue);
          expect(net.sends.length, pair.contains(mockName) ? 2 : 1);
          for (final send in net.sends) {
            final probe = send.options.path.startsWith(mockUrl);
            expect(send.options.path, probe ? probePath : path);
            expect(send.options.queryParameters, {
              if (!pair.contains(repathName)) pairId: 7,
              if (!pair.contains(filterName)) pairEmpty: null,
            });
            expect(send.body, {
              if (!pair.contains(filterName)) pairEmpty: null,
              pairKeep: 1,
            });
            // start 共享传输按 B4 契约清除 Dio 超时，订阅者保留自己的超时。
            final timeout = pair.contains(shareName)
                ? Duration.zero
                : pair.contains(timeoutName)
                    ? pairTimeout
                    : null;
            expect(send.options.connectTimeout, timeout);
            expect(send.options.sendTimeout, timeout);
            expect(send.options.receiveTimeout, timeout);
            if (pair.contains(envsName)) {
              expect(send.options.headers[pairEnv], 1);
              expect(send.options.uri.host,
                  probe ? Uri.parse(mockUrl).host : Uri.parse(pairUrl).host);
            }
          }
          expect(api.pending, 0);
          expect(clock.pendingTimers, 0);
        } finally {
          api.dispose();
          await stream.close();
        }
      });
    }
  }
}
