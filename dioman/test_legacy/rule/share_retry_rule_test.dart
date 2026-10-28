// 规则层：share 的 policy=retry（重试次数、间隔、宿主绑定）与单请求覆盖
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../../test/support/fixtures.dart';

/// 插件名 / extra 键的期望值。
const _pluginName = 'dioman:share';

/// 兜底超时：间隔或次数失控时用例会挂住，靠它判失败。
const _guard = Duration(seconds: 3);

/// 明显可测的重试间隔。
const _gap = Duration(milliseconds: 150);

/// 间隔下限（略小于 [_gap]，留出计时误差）。
const _gapFloor = Duration(milliseconds: 120);

/// 没有间隔时两次请求之间允许的最大耗时。
const _noGapCeiling = Duration(milliseconds: 100);

/// 一小时：只要被采用，用例就会超时失败。
const _hour = Duration(hours: 1);

/// 共享请求的路径。
const _path = '/shared';

/// 带单请求覆盖的 Options。
Options _override(DiomanShareOptions o) =>
    Options(extra: {DiomanShare.pluginName: o});

/// 一套 share 测试台：key + share 装在假适配器 Dio 上，share 已绑定宿主。
class _Rig {
  /// 用 [handler] 当适配器逻辑，装 [share]。
  _Rig(AdapterHandler handler, this.share, {Transformer? transformer})
      : adapter = RecordingAdapter(handler) {
    dio = fakeDio(adapter, transformer: transformer)
      ..interceptors.addAll([const DiomanKey(), share]);
    share.dio = dio;
  }

  /// 被测的 share。
  final DiomanShare share;

  /// 记录请求的适配器。
  final RecordingAdapter adapter;

  /// 装好插件的 Dio。
  late final Dio dio;
}

/// 首发回 500、之后回 200 的适配器逻辑；到达时间记进 [arrivals]。
AdapterHandler _failOnce(List<DateTime> arrivals, {Future<void>? gate}) =>
    (o, n) async {
      arrivals.add(DateTime.now());
      if (n == 1 && gate != null) await gate;
      return jsonBody({'n': n}, n == 1 ? 500 : 200);
    };

/// 每次都回 500 的适配器逻辑。
Future<ResponseBody> _alwaysFail(RequestOptions o, int n) async =>
    jsonBody({}, 500);

/// 吞掉预期内的 DioException，返回是否失败。
Future<bool> _failed(Future<Response<dynamic>> request) async {
  try {
    await request.timeout(_guard);
    return false;
  } on DioException {
    return true;
  }
}

/// 注册本文件的规则层用例。
void main() {
  test(
      '[DiomanShare.name][DiomanShare.pluginName] 插件名固定为 dioman:share，同时是单请求覆盖的 extra 键',
      () async {
    expect(DiomanShare.pluginName, _pluginName);
    expect(DiomanShare().name, DiomanShare.pluginName);

    final rig = _Rig((o, n) async => jsonBody({}, 200), DiomanShare());
    addTearDown(rig.share.dispose);
    final pending = [
      rig.dio.get<dynamic>(_path),
      rig.dio.get<dynamic>(_path,
          options: _override(const DiomanShareOptions(enabled: false))),
    ];
    await Future.wait(pending);
    expect(rig.adapter.calls, 2, reason: '用静态常量当 extra 键，第二个请求退出共享');
  });

  test('[DiomanShare.dio] 绑定宿主后 policy=retry 的内部重发借用宿主的 adapter 与 transformer',
      () async {
    final transformer = CountingTransformer();
    final rig = _Rig((o, n) async => jsonBody({'n': n}, n == 1 ? 500 : 200),
        DiomanShare(policy: DiomanSharePolicy.retry, retries: 1),
        transformer: transformer);
    addTearDown(rig.share.dispose);

    final res = await rig.dio.get<dynamic>(_path).timeout(_guard);

    expect(res.data, {'n': 2});
    expect(rig.adapter.calls, 2, reason: '首发和内部重发都经过宿主适配器');
    expect(transformer.responses, 2, reason: '内部重发复用宿主 transformer');
  });

  group('重试间隔 interval', () {
    test(
        '[DiomanShare.interval][DiomanShare.new(interval)] policy=retry 每次内部重试前等待 interval，默认 0 即刻重试',
        () async {
      expect(DiomanShare().interval, Duration.zero);

      final fast = <DateTime>[];
      final noWait = _Rig(_failOnce(fast),
          DiomanShare(policy: DiomanSharePolicy.retry, retries: 1));
      addTearDown(noWait.share.dispose);
      await noWait.dio.get<dynamic>(_path).timeout(_guard);
      expect(noWait.adapter.calls, 2);
      expect(fast[1].difference(fast[0]), lessThan(_noGapCeiling),
          reason: '默认间隔为 0');

      final slow = <DateTime>[];
      final waited = _Rig(
          _failOnce(slow),
          DiomanShare(
              policy: DiomanSharePolicy.retry, retries: 1, interval: _gap));
      addTearDown(waited.share.dispose);
      await waited.dio.get<dynamic>(_path).timeout(_guard);
      expect(slow[1].difference(slow[0]), greaterThanOrEqualTo(_gapFloor),
          reason: '重试前等了 interval');
    });

    test(
        '[DiomanShareOptions.interval][DiomanShareOptions.new(interval)] 单请求覆盖重试间隔；只有 leader 建条目时的覆盖生效，follower 的被忽略',
        () async {
      // 覆盖放宽：插件 0，单请求 150ms。
      final a = <DateTime>[];
      final widen = _Rig(_failOnce(a),
          DiomanShare(policy: DiomanSharePolicy.retry, retries: 1));
      addTearDown(widen.share.dispose);
      await widen.dio
          .get<dynamic>(_path,
              options: _override(const DiomanShareOptions(interval: _gap)))
          .timeout(_guard);
      expect(a[1].difference(a[0]), greaterThanOrEqualTo(_gapFloor));

      // 覆盖收紧：插件一小时，单请求 0。
      final b = <DateTime>[];
      final tighten = _Rig(
          _failOnce(b),
          DiomanShare(
              policy: DiomanSharePolicy.retry, retries: 1, interval: _hour));
      addTearDown(tighten.share.dispose);
      await tighten.dio
          .get<dynamic>(_path,
              options:
                  _override(const DiomanShareOptions(interval: Duration.zero)))
          .timeout(_guard);
      expect(tighten.adapter.calls, 2);

      // follower 带一小时的覆盖，leader 没有：follower 的覆盖不参与。
      final gate = Completer<void>();
      final c = <DateTime>[];
      final leaderOnly = _Rig(_failOnce(c, gate: gate.future),
          DiomanShare(policy: DiomanSharePolicy.retry, retries: 1));
      addTearDown(leaderOnly.share.dispose);
      final leader = leaderOnly.dio.get<dynamic>(_path);
      final follower = leaderOnly.dio.get<dynamic>(_path,
          options: _override(const DiomanShareOptions(interval: _hour)));
      await settleAsync();
      gate.complete();
      final results = await Future.wait([leader, follower]).timeout(_guard);
      expect(results.map((r) => r.statusCode), [200, 200]);
      expect(leaderOnly.adapter.calls, 2, reason: '两个调用方共享同一条请求链');
    });
  });

  group('重试次数 retries', () {
    test(
        '[DiomanShareOptions.retries][DiomanShareOptions.new(retries)] 单请求覆盖重试次数；只有 leader 建条目时的覆盖生效',
        () async {
      // 插件 0 次，单请求 2 次：首发 + 2 次重试。
      final more = _Rig(_alwaysFail,
          DiomanShare(policy: DiomanSharePolicy.retry, retries: 0));
      addTearDown(more.share.dispose);
      expect(
          await _failed(more.dio.get<dynamic>(_path,
              options: _override(const DiomanShareOptions(retries: 2)))),
          isTrue);
      expect(more.adapter.calls, 3);

      // 插件 3 次，单请求 1 次：覆盖压过插件。
      final fewer = _Rig(_alwaysFail,
          DiomanShare(policy: DiomanSharePolicy.retry, retries: 3));
      addTearDown(fewer.share.dispose);
      expect(
          await _failed(fewer.dio.get<dynamic>(_path,
              options: _override(const DiomanShareOptions(retries: 1)))),
          isTrue);
      expect(fewer.adapter.calls, 2);

      // follower 带 5 次覆盖，leader 没有（插件 1 次）：按 leader 的 1 次。
      final gate = Completer<void>();
      final rig = _Rig((o, n) async {
        if (n == 1) await gate.future;
        return jsonBody({}, 500);
      }, DiomanShare(policy: DiomanSharePolicy.retry, retries: 1));
      addTearDown(rig.share.dispose);
      final leader = _failed(rig.dio.get<dynamic>(_path));
      final follower = _failed(rig.dio.get<dynamic>(_path,
          options: _override(const DiomanShareOptions(retries: 5))));
      await settleAsync();
      gate.complete();
      expect(await Future.wait([leader, follower]), [true, true]);
      expect(rig.adapter.calls, 2, reason: '首发 + leader 的 1 次重试');
    });
  });
}
