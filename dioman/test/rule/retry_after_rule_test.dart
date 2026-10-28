// 规则层：retry 的等待时长——Retry-After、delayMax、retryAfterMax 及其单请求覆盖
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// 整个用例的兜底超时：封顶失效时会等很久，靠它把用例判失败。
const _guard = Duration(seconds: 3);

/// 极短的 Retry-After（秒），换算成 20 毫秒。
const _shortAfter = '0.02';

/// 较长的 Retry-After（秒），换算成 150 毫秒，用来测"没被封顶"。
const _midAfter = '0.15';

/// 极长的 Retry-After（秒），一小时，必须被封顶才能在 [_guard] 内结束。
const _hourAfter = '3600';

/// 封顶值：足够短，等待几乎不可察觉。
const _tinyCap = Duration(milliseconds: 30);

/// 一毫秒的封顶，用来证明"这个封顶不管另一条路径"。
const _oneMs = Duration(milliseconds: 1);

/// 与 [_midAfter] 等长的原始退避。
const _midDelay = Duration(milliseconds: 150);

/// 未封顶时等待的下限（略小于 150 毫秒，留出计时误差）。
const _midFloor = Duration(milliseconds: 120);

/// 一小时，用来当"必须被封顶"的原始退避。
const _hour = Duration(hours: 1);

/// 一次"首发失败 → 重试成功"的观测结果。
typedef _Outcome = ({int delayCalls, Duration elapsed, int calls});

/// 星期缩写，按 [DateTime.weekday]（周一为 1）索引。
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 月份缩写，按月份 -1 索引。
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 把 [t] 格式化成 HTTP 日期（`Wed, 21 Oct 2026 07:28:00 GMT`）。
String _httpDate(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_weekdays[u.weekday - 1]}, ${two(u.day)} ${_months[u.month - 1]} '
      '${u.year} ${two(u.hour)}:${two(u.minute)}:${two(u.second)} GMT';
}

/// 首发回 [status]（可带 Retry-After 头），重试回 200，返回观测结果。
///
/// [rawDelay] 是 delay 回调给出的原始退避；回调被调用的次数记在结果里——
/// Retry-After 被采用时 delay 回调不会被调用。
Future<_Outcome> _retryOnce({
  required int status,
  String? retryAfter,
  Duration rawDelay = Duration.zero,
  bool respectRetryAfter = true,
  List<int>? afterStatusCodes,
  Duration? retryAfterMax,
  Duration? delayMax,
  Object? jitter,
  DiomanRetryOptions? override,
}) async {
  var delayCalls = 0;
  final adapter = RecordingAdapter((o, n) async => n == 1
      ? ResponseBody.fromString('{}', status, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
          if (retryAfter != null) 'retry-after': [retryAfter],
        })
      : jsonBody({}, 200));
  final dio = fakeDio(adapter);
  final handle = Dioman.install(dio,
      retry: DiomanRetry(
        max: 1,
        respectRetryAfter: respectRetryAfter,
        afterStatusCodes: afterStatusCodes,
        retryAfterMax: retryAfterMax,
        delayMax: delayMax,
        jitter: jitter,
        delay: (_, __, ___, ____) {
          delayCalls++;
          return rawDelay;
        },
      ));
  final watch = Stopwatch()..start();
  try {
    final res = await dio
        .get<dynamic>('/x',
            options: override == null
                ? null
                : Options(extra: {DiomanRetry.pluginName: override}))
        .timeout(_guard);
    expect(res.statusCode, 200);
  } finally {
    watch.stop();
    handle.dispose();
  }
  return (delayCalls: delayCalls, elapsed: watch.elapsed, calls: adapter.calls);
}

/// 注册本文件的规则层用例。
void main() {
  group('Retry-After 的信任范围 afterStatusCodes', () {
    test(
        '[DiomanRetry.afterStatusCodes][DiomanRetry.new(afterStatusCodes)] 默认只在 413/429/503 上信 Retry-After；自定义列表替换默认',
        () async {
      for (final status in [429, 503]) {
        final r = await _retryOnce(status: status, retryAfter: _shortAfter);
        expect(r.delayCalls, 0, reason: '$status 在默认列表里，头部生效，不再问 delay');
        expect(r.calls, 2);
      }
      final off = await _retryOnce(status: 500, retryAfter: _shortAfter);
      expect(off.delayCalls, 1, reason: '500 不在默认列表里，头部被忽略，走 delay');

      final custom = await _retryOnce(
          status: 500, retryAfter: _shortAfter, afterStatusCodes: [500]);
      expect(custom.delayCalls, 0, reason: '自定义列表让 500 的头部生效');
      final replaced = await _retryOnce(
          status: 503, retryAfter: _shortAfter, afterStatusCodes: [500]);
      expect(replaced.delayCalls, 1, reason: '自定义列表是替换而不是追加，503 不再被信任');
    });

    test(
        '[DiomanRetryOptions.afterStatusCodes][DiomanRetryOptions.new(afterStatusCodes)] 单请求覆盖信任 Retry-After 的状态码',
        () async {
      final widen = await _retryOnce(
          status: 500,
          retryAfter: _shortAfter,
          override: const DiomanRetryOptions(afterStatusCodes: [500]));
      expect(widen.delayCalls, 0, reason: '覆盖后 500 的头部生效');

      final narrow = await _retryOnce(
          status: 503,
          retryAfter: _shortAfter,
          override: const DiomanRetryOptions(afterStatusCodes: []));
      expect(narrow.delayCalls, 1, reason: '覆盖成空列表后任何状态的头部都不信');
    });
  });

  group('是否尊重 Retry-After respectRetryAfter', () {
    test(
        '[DiomanRetry.respectRetryAfter][DiomanRetry.new(respectRetryAfter)] 默认 true：秒数与 HTTP 日期都按头等待；false 时头部被忽略',
        () async {
      expect(DiomanRetry().respectRetryAfter, isTrue);

      final seconds = await _retryOnce(status: 503, retryAfter: _shortAfter);
      expect(seconds.delayCalls, 0, reason: '数字秒按头等待');

      final future = _httpDate(DateTime.now().add(_hour));
      final date = await _retryOnce(
          status: 503, retryAfter: future, retryAfterMax: _tinyCap);
      expect(date.delayCalls, 0, reason: 'HTTP 日期能被解析并采用（被 retryAfterMax 封顶）');
      expect(date.elapsed, lessThan(_guard));

      final past =
          await _retryOnce(status: 503, retryAfter: _httpDate(DateTime(2000)));
      expect(past.delayCalls, 0, reason: '过去的日期解析成功，等待归零');

      final garbage = await _retryOnce(status: 503, retryAfter: 'soon');
      expect(garbage.delayCalls, 1, reason: '解析不了的头部退回 delay');

      final ignored = await _retryOnce(
          status: 503, retryAfter: _shortAfter, respectRetryAfter: false);
      expect(ignored.delayCalls, 1, reason: 'false 时即使状态码和头部都合格也走 delay');
    });

    test(
        '[DiomanRetry.respectRetryAfter] 头部等待按头部时长而不是 delay 回调；没有头部时仍走 delay',
        () async {
      final byHeader = await _retryOnce(
          status: 503, retryAfter: _midAfter, rawDelay: Duration.zero);
      expect(byHeader.elapsed, greaterThanOrEqualTo(_midFloor),
          reason: '实际等了头部指定的 150ms，而不是 delay 的 0');

      final noHeader = await _retryOnce(status: 503, rawDelay: _midDelay);
      expect(noHeader.delayCalls, 1, reason: '503 没带头部：回落 delay');
      expect(noHeader.elapsed, greaterThanOrEqualTo(_midFloor));
    });

    test(
        '[DiomanRetryOptions.respectRetryAfter][DiomanRetryOptions.new(respectRetryAfter)] 单请求能双向覆盖是否尊重 Retry-After',
        () async {
      final off = await _retryOnce(
          status: 503,
          retryAfter: _shortAfter,
          override: const DiomanRetryOptions(respectRetryAfter: false));
      expect(off.delayCalls, 1, reason: '单请求 false 覆盖插件的 true');

      final on = await _retryOnce(
          status: 503,
          retryAfter: _shortAfter,
          respectRetryAfter: false,
          override: const DiomanRetryOptions(respectRetryAfter: true));
      expect(on.delayCalls, 0, reason: '单请求 true 覆盖插件的 false');
    });
  });

  group('封顶 retryAfterMax / delayMax', () {
    test(
        '[DiomanRetry.retryAfterMax][DiomanRetry.new(retryAfterMax)] 封顶 Retry-After 换算出的等待；默认不封顶；不管 delay 回调的值',
        () async {
      final capped = await _retryOnce(
          status: 503, retryAfter: _hourAfter, retryAfterMax: _tinyCap);
      expect(capped.elapsed, lessThan(_guard), reason: '一小时的头部被封到 30ms');

      final uncapped = await _retryOnce(status: 503, retryAfter: _midAfter);
      expect(uncapped.elapsed, greaterThanOrEqualTo(_midFloor),
          reason: '默认不封顶，等满头部时长');

      final notDelay = await _retryOnce(
          status: 500, rawDelay: _midDelay, retryAfterMax: _oneMs);
      expect(notDelay.elapsed, greaterThanOrEqualTo(_midFloor),
          reason: 'retryAfterMax 只管头部，不封 delay 回调');
    });

    test(
        '[DiomanRetryOptions.retryAfterMax][DiomanRetryOptions.new(retryAfterMax)] 单请求覆盖 Retry-After 封顶',
        () async {
      final tighten = await _retryOnce(
          status: 503,
          retryAfter: _hourAfter,
          override: const DiomanRetryOptions(retryAfterMax: _tinyCap));
      expect(tighten.elapsed, lessThan(_guard));

      final loosen = await _retryOnce(
          status: 503,
          retryAfter: _midAfter,
          retryAfterMax: _oneMs,
          override:
              const DiomanRetryOptions(retryAfterMax: Duration(seconds: 1)));
      expect(loosen.elapsed, greaterThanOrEqualTo(_midFloor),
          reason: '单请求放宽后不再被插件的 1ms 封住');
    });

    test(
        '[DiomanRetry.delayMax][DiomanRetry.new(delayMax)] 封顶 delay（含抖动之后）；默认不封顶；不管 Retry-After',
        () async {
      final capped =
          await _retryOnce(status: 500, rawDelay: _hour, delayMax: _tinyCap);
      expect(capped.elapsed, lessThan(_guard), reason: '一小时的 delay 被封到 30ms');

      final jittered = await _retryOnce(
          status: 500, jitter: (Duration raw) => _hour, delayMax: _tinyCap);
      expect(jittered.elapsed, lessThan(_guard), reason: '抖动放大后的值同样被封顶');

      final uncapped = await _retryOnce(status: 500, rawDelay: _midDelay);
      expect(uncapped.elapsed, greaterThanOrEqualTo(_midFloor),
          reason: '默认不封顶');

      final header = await _retryOnce(
          status: 503, retryAfter: _midAfter, delayMax: _oneMs);
      expect(header.elapsed, greaterThanOrEqualTo(_midFloor),
          reason: 'delayMax 不管 Retry-After 换算出的等待');
    });

    test(
        '[DiomanRetryOptions.delayMax][DiomanRetryOptions.new(delayMax)] 单请求覆盖 delay 封顶',
        () async {
      final tighten = await _retryOnce(
          status: 500,
          rawDelay: _hour,
          override: const DiomanRetryOptions(delayMax: _tinyCap));
      expect(tighten.elapsed, lessThan(_guard));

      final loosen = await _retryOnce(
          status: 500,
          rawDelay: _midDelay,
          delayMax: _oneMs,
          override: const DiomanRetryOptions(delayMax: Duration(seconds: 1)));
      expect(loosen.elapsed, greaterThanOrEqualTo(_midFloor),
          reason: '单请求放宽后不再被插件的 1ms 封住');
    });
  });
}
