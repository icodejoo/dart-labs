// ignore_for_file: avoid_relative_lib_imports
// 规则层：loading
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:dioman/src/loading_plugin.dart';
import 'package:test/test.dart';
import '../../test/accept/lib/literals.dart';
import '../../test/support/fixtures.dart';
import '../../test/support/test_server.dart';

/// 注册本文件的规则层用例。
void main() {
  group(tkEnabledInheritsFromTheConstructorWhenNotOverridden, () {
    test(
        '[DiomanLoading.enabled][DiomanLoadingOptions.enabled] a per-request DiomanLoadingOptions that omits enabled does NOT '
        "re-enable a plugin constructed with enabled: false", () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final states = <bool>[];
      dio.interceptors
          .add(DiomanLoading(onChanged: states.add, enabled: false));

      await dio.get<void>(
        tkX,
        options: Options(extra: {
          tkDiomanLoading2: const DiomanLoadingOptions(onChanged: null),
        }),
      );

      expect(states, isEmpty,
          reason: 'enabled:null on the override must inherit the '
              "constructor's enabled:false, not silently default to true");
    });
  });

  group('DiomanLoadingOptions.onChanged (edge-triggered, not additive)', () {
    test(
        '[DiomanLoading.onResponse][DiomanLoading.new(onChanged)][DiomanLoadingOptions.onChanged] a solo request with its own onChanged fires it at the 0→1→0 edge '
        'instead of the plugin default, and still participates in the '
        'shared counter', () async {
      final server = await TestServer.start((req) => respondJson(req, {}, 200));
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final defaultStates = <bool>[];
      final loading = DiomanLoading(onChanged: defaultStates.add);
      dio.interceptors.add(loading);

      final ownStates = <bool>[];
      await dio.get<void>(
        tkX,
        options: Options(
          extra: {
            tkDiomanLoading2: DiomanLoadingOptions(onChanged: ownStates.add)
          },
        ),
      );

      expect(ownStates, [true, false],
          reason: 'a request alone in the batch causes both edges, so its '
              'own onChanged must fire for both');
      expect(defaultStates, isEmpty,
          reason: "the plugin's default onChanged must NOT also fire — only "
              'one callback is invoked per edge');
      expect(loading.activeCount, 0,
          reason: 'the request must still have incremented/decremented the '
              'shared counter like any other request');
    });
    test(
        "[DiomanLoading.activeCount][DiomanLoading.new(onChanged)][DiomanLoadingOptions.onChanged] a request's own onChanged does not fire if it doesn't land on the "
        'batch edge (another request is already keeping the counter above '
        'zero) — counting is still accurate either way', () async {
      final completers = <String, Completer<void>>{
        tkFirst2: Completer<void>(),
        tkSecond: Completer<void>(),
      };
      final server = await TestServer.start((req) async {
        await completers[req.uri.path]!.future;
        await respondJson(req, {}, 200);
      });
      addTearDown(server.close);
      final dio = Dio(BaseOptions(baseUrl: server.baseUrl));
      final defaultStates = <bool>[];
      final loading = DiomanLoading(onChanged: defaultStates.add);
      dio.interceptors.add(loading);

      // Start the first request (causes the 0→1 edge, default onChanged).
      final f1 = dio.get<void>(tkFirst2);
      await Future<void>.delayed(
          const Duration(milliseconds: 20)); // let onRequest run
      expect(loading.activeCount, 1);

      // Start a second request with its own onChanged — count is already 1,
      // so this does NOT land on an edge; its own callback never fires.
      final ownStates = <bool>[];
      final f2 = dio.get<void>(
        tkSecond,
        options: Options(
          extra: {
            tkDiomanLoading2: DiomanLoadingOptions(onChanged: ownStates.add)
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(loading.activeCount, 2,
          reason: 'the second request is still counted even though its own '
              'onChanged never got to fire');

      // First request finishes (2→1, not an edge) — the request finishing
      // isn't the second one, so its own onChanged is irrelevant here and
      // the default isn't called either (no edge).
      completers[tkFirst2]!.complete();
      await f1;
      expect(ownStates, isEmpty,
          reason: 'the first request finishing (2→1) is not an edge at all');
      expect(defaultStates, [true],
          reason: 'still just the one true from the initial 0→1 edge');

      // 最后请求结束后由开启本显示周期的回调成对关闭。
      completers[tkSecond]!.complete();
      await f2;
      expect(ownStates, isEmpty);
      expect(defaultStates, [true, false]);
    });
  });

  test(
      '[DiomanLoading.delay][DiomanLoading.delayClose] loading 延时显示与延时关闭都执行且成对',
      () async {
    final events = <bool>[];
    final plugin = DiomanLoading(
        onChanged: events.add,
        delay: const Duration(milliseconds: 1),
        delayClose: const Duration(milliseconds: 1));
    final options = RequestOptions(path: replayPath);
    plugin.onRequest(options, RequestInterceptorHandler());
    await Future<void>.delayed(replayTick);
    expect(events, [true]);
    plugin.onResponse(
        Response(requestOptions: options), ResponseInterceptorHandler());
    await Future<void>.delayed(replayTick);
    expect(events, [true, false]);
    plugin.dispose();
  });
}
