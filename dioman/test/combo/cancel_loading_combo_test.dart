// ignore_for_file: avoid_relative_lib_imports
// 组合层：cancel_loading
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';
import '../accept/lib/literals.dart';
import '../support/fixtures.dart';
import '../support/test_server.dart';

/// 注册本文件的组合层用例。
void main() {
  group('pairwise: cancel + loading', () {
// Same root cause as the "share + cancel" deadlock test above — see the
// FIXED note there. DiomanCancel now sets `token.requestOptions` so a
// cancellation error carries the real RequestOptions (with all of this
// request's `extra` state, including DiomanLoading's `_kBracketed` flag)
// instead of a blank one.
    test(
        '[DiomanCancel.onRequest × DiomanLoading.new(onChanged)] FIXED: cancelling a request correctly settles the loading counter '
        'back to 0 — DiomanLoading._decrement can now find its own '
        '`_kBracketed` flag on the cancellation RequestOptions', () async {
      final started = Completer<void>();
      final server = await TestServer.start((req) async {
        started.complete();
        await Completer<void>().future; // hangs until the connection dies
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      final loading = DiomanLoading(onChanged: states.add);
      installStateful(dio, cancel: DiomanCancel(), loading: loading);

      final call = dio.get<void>(tkData2);
      await started.future;
      cancelAll(dio, tkTest);
      await expectLater(call.timeout(const Duration(seconds: 2)),
          throwsA(isA<DioException>()));

      expect(states, [true, false],
          reason: 'a caller driving a global spinner off this callback '
              'correctly sees it turn back off after the cancellation');
      expect(loading.activeCount, 0,
          reason: 'the internal counter is back to 0 too, not just the '
              'callback — a later unrelated request starts its own fresh '
              'batch instead of looking like it joined a stuck one');
    });
  });
}
