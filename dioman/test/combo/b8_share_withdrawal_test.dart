import 'dart:async';
import 'package:dioman/dioman.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import '../support/b3_helpers.dart';
import '../support/fake_clock.dart';
import '../support/helpers.dart';

const _leader = 'leader';
const _follower = 'follower';
const _lastCompleted = 'last-completed';
const _path = '/withdraw';
const _get = 'GET';
const _tick = Duration(seconds: 1);

void main() {
  for (final policy in [
    DiomanSharePolicy.start,
    DiomanSharePolicy.end,
    DiomanSharePolicy.race
  ]) {
    for (final role in [_leader, _follower, 'latest', _lastCompleted]) {
      for (final timeout in [false, true]) {
        test('[DiomanShare.policy] B8 撤回 $policy $role timeout=$timeout',
            () async {
          final clock = FakeClock();
          final gates = List.generate(3, (_) => Completer<void>());
          final tokens = List.generate(3, (_) => CancelToken());
          var sent = 0;
          final api = testClient(clock: clock, plugins: [
            DiomanShare<Result>(policy: policy),
            TestPlugin('gates', stage: DiomanStage.source,
                handler: (ctx, next) async {
              final id = sent++;
              await ctx.wait(gates[id].future);
              return ctx.cancelled() ??
                  ctx.fail(
                      DiomanFailure(kind: DiomanKind.http, status: 500 + id));
            })
          ]);
          final withdrawn = role == _leader
              ? 0
              : role == _follower
                  ? 1
                  : 2;
          final requests = <Future<Result>>[];
          for (var i = 0; i < 3; i++) {
            requests.add(api.send<dynamic>(_get, _path,
                call: DiomanCall(
                    cancelToken: tokens[i],
                    connectTimeout:
                        timeout && i == withdrawn ? _tick : Duration.zero,
                    receiveTimeout:
                        timeout && i == withdrawn ? _tick : Duration.zero,
                    options: {DiomanShare.option: true})));
            await b3Turn();
          }
          if (role == _lastCompleted && policy != DiomanSharePolicy.start) {
            gates[0].complete();
            gates[1].complete();
            await b3Turn();
          }
          if (timeout) {
            clock.elapse(_tick * 2);
          } else {
            tokens[withdrawn].cancel();
          }
          await b3Turn();
          expect((await requests[withdrawn]).kind,
              timeout ? DiomanKind.timeout : DiomanKind.cancel);
          for (final gate in gates) {
            if (!gate.isCompleted) gate.complete();
          }
          final results = await Future.wait(requests);
          for (var i = 0; i < results.length; i++) {
            if (i == withdrawn) continue;
            expect(results[i].kind, DiomanKind.http, reason: 'I8 他人撤回不污染结果');
            if (policy != DiomanSharePolicy.start) {
              expect(results[i].status, isNot(500 + withdrawn));
            }
          }
          expect(api.pending, 0);
          expect(clock.pendingTimers, 0);
          api.dispose();
        });
      }
    }
  }
}
