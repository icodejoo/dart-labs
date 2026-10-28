// 规则层：share 的 start 策略、成功结算与已弃用的兼容 getter
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../../test/support/fixtures.dart';

/// 兜底超时：跟随者悬挂时用例会挂住，靠它判失败。
const _guard = Duration(seconds: 3);

/// 共享请求的路径。
const _path = '/shared';

/// 同时发起的调用方数量（1 个首发 + 2 个跟随者）。
const _callers = 3;

/// 一套 share 测试台：首发的适配器响应被门控卡住，等跟随者都挂上再放行。
class _Rig {
  /// 装 [share]（默认 start 策略），适配器回 `{n: 第几次}`。
  _Rig(this.share) {
    adapter = RecordingAdapter((o, n) async {
      await gate.future;
      return ResponseBody.fromString('{"n":$n}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        'x-origin': ['server'],
      });
    });
    dio = fakeDio(adapter)..interceptors.addAll([const DiomanKey(), share]);
    share.dio = dio;
  }

  /// 被测的 share。
  final DiomanShare share;

  /// 放行首发响应的门。
  final gate = Completer<void>();

  /// 记录请求的适配器。
  late final RecordingAdapter adapter;

  /// 装好插件的 Dio。
  late final Dio dio;

  /// 同时发起 [_callers] 个相同请求，等跟随者挂好后放行，返回各自的响应。
  Future<List<Response<dynamic>>> burst() async {
    final pending = [
      for (var i = 0; i < _callers; i++) dio.get<dynamic>(_path)
    ];
    await settleAsync();
    gate.complete();
    return Future.wait(pending).timeout(_guard);
  }
}

/// 注册本文件的规则层用例。
void main() {
  test('[DiomanSharePolicy.start] 首发真正发出，其余同 key 调用等它的结果，HTTP 只发一次；结算后新请求重新发起',
      () async {
    final rig = _Rig(DiomanShare(policy: DiomanSharePolicy.start));
    addTearDown(rig.share.dispose);

    final results = await rig.burst();

    expect(rig.adapter.calls, 1, reason: '3 个调用方只产生 1 次 HTTP');
    expect(results.map((r) => r.data), everyElement({'n': 1}));

    final later = await rig.dio.get<dynamic>(_path).timeout(_guard);
    expect(later.data, {'n': 2}, reason: '共享条目已结算摘除，后来的请求重新发出');
    expect(rig.adapter.calls, 2);
  });

  test(
      '[DiomanShare.onResponse] 成功时结算共享条目：首发与每个跟随者各拿独立的响应副本（头、extra、requestOptions 互不影响）',
      () async {
    final rig = _Rig(DiomanShare());
    addTearDown(rig.share.dispose);

    final results = await rig.burst();

    expect(results.map((r) => r.statusCode), everyElement(200));
    for (var i = 0; i < _callers; i++) {
      for (var j = i + 1; j < _callers; j++) {
        expect(results[i], isNot(same(results[j])), reason: '不是同一个 Response');
        expect(
            results[i].requestOptions, isNot(same(results[j].requestOptions)),
            reason: '各自带着自己的 RequestOptions');
      }
    }
    // 改一个副本的头与 extra，不影响其它副本。
    results[0].headers.add('x-mark', 'only-first');
    results[0].extra['mark'] = true;
    for (final other in results.skip(1)) {
      expect(other.headers.value('x-mark'), isNull);
      expect(other.extra.containsKey('mark'), isFalse);
      expect(other.headers.value('x-origin'), 'server',
          reason: '原有响应头在副本里完整保留');
    }
  });

  test(
      '[DiomanShare.hasMultipleDownstreamSettlers][DiomanShare.registerDownstreamSettler] 已弃用的兼容计数不影响结算：登记多次后共享依旧只发一次、跟随者照常拿到结果',
      () async {
    final share = DiomanShare();
    for (var i = 0; i < 3; i++) {
      share.registerDownstreamSettler();
    }
    expect(share.hasMultipleDownstreamSettlers, isTrue);
    final rig = _Rig(share);
    addTearDown(share.dispose);

    final results = await rig.burst();

    expect(rig.adapter.calls, 1);
    expect(results.map((r) => r.data), everyElement({'n': 1}));
  });
}
