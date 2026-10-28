// 规则层：timeout 的插件名、默认档位、send 超时与请求级开关
import 'package:dio/dio.dart';
import 'package:dioman/dioman.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// 插件名 / extra 键的期望值。
const _pluginName = 'dioman:timeout';

/// BaseOptions 自带的 connect 超时，用来区分"被改写"与"没动"。
const _baseConnect = Duration(seconds: 4);

/// BaseOptions 自带的 receive 超时。
const _baseReceive = Duration(seconds: 5);

/// BaseOptions 自带的 send 超时。
const _baseSend = Duration(seconds: 6);

/// 插件配置里的 send 超时。
const _tierSend = Duration(seconds: 8);

/// 建一个带 BaseOptions 超时的 Dio，返回 Dio 与记录请求选项的适配器。
(Dio, RecordingAdapter) _rig(DiomanTimeout plugin) {
  final adapter = RecordingAdapter((o, n) async => jsonBody({}, 200));
  final dio = fakeDio(adapter);
  dio.options
    ..connectTimeout = _baseConnect
    ..receiveTimeout = _baseReceive
    ..sendTimeout = _baseSend;
  dio.interceptors.add(plugin);
  return (dio, adapter);
}

/// 注册本文件的规则层用例。
void main() {
  test(
      '[DiomanTimeout.name][DiomanTimeout.pluginName] 插件名固定为 dioman:timeout，同时是单请求覆盖的 extra 键',
      () async {
    expect(DiomanTimeout.pluginName, _pluginName);
    final plugin = DiomanTimeout(probe: () => NetworkQuality.excellent);
    expect(plugin.name, DiomanTimeout.pluginName);

    final (dio, adapter) = _rig(plugin);
    await dio.get<dynamic>('/x');
    expect(adapter.seen.last.connectTimeout, const Duration(seconds: 10));
    // 用静态常量当 extra 键关掉本次改写，保留 BaseOptions 的超时。
    await dio.get<dynamic>('/x',
        options: Options(extra: {
          DiomanTimeout.pluginName: const DiomanTimeoutOptions(enabled: false),
        }));
    expect(adapter.seen.last.connectTimeout, _baseConnect);
  });

  test(
      '[DiomanTimeoutOptions.enabled][DiomanTimeoutOptions.new(enabled)] null 沿用插件的开关；true 可在插件关闭时点亮本次；false 在插件开启时关掉本次',
      () async {
    final (off, offAdapter) = _rig(DiomanTimeout(
        probe: () => NetworkQuality.poor,
        enabled: false,
        timeouts: const {
          NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
        }));
    Options withOptions(DiomanTimeoutOptions o) =>
        Options(extra: {DiomanTimeout.pluginName: o});

    await off.get<dynamic>('/x');
    expect(offAdapter.seen.last.connectTimeout, _baseConnect,
        reason: '插件关闭，不改写');
    await off.get<dynamic>('/x',
        options: withOptions(const DiomanTimeoutOptions()));
    expect(offAdapter.seen.last.connectTimeout, _baseConnect,
        reason: 'enabled 为 null 沿用插件的 false');
    await off.get<dynamic>('/x',
        options: withOptions(const DiomanTimeoutOptions(enabled: true)));
    expect(offAdapter.seen.last.connectTimeout, const Duration(seconds: 7),
        reason: 'true 覆盖插件的 false');

    final (on, onAdapter) =
        _rig(DiomanTimeout(probe: () => NetworkQuality.poor, timeouts: const {
      NetworkQuality.poor: DiomanTimeouts(connect: Duration(seconds: 7)),
    }));
    await on.get<dynamic>('/x',
        options: withOptions(const DiomanTimeoutOptions(enabled: false)));
    expect(onAdapter.seen.last.connectTimeout, _baseConnect);
  });

  test(
      '[DiomanTimeouts.send][DiomanTimeouts.new(send)] send 非空时覆盖 sendTimeout，其余字段为空则保持 BaseOptions',
      () async {
    final (dio, adapter) =
        _rig(DiomanTimeout(probe: () => NetworkQuality.poor, timeouts: const {
      NetworkQuality.poor: DiomanTimeouts(send: _tierSend),
    }));

    await dio.post<dynamic>('/x', data: 'body');

    final seen = adapter.seen.last;
    expect(seen.sendTimeout, _tierSend);
    expect(seen.connectTimeout, _baseConnect, reason: 'connect 为空，不动');
    expect(seen.receiveTimeout, _baseReceive, reason: 'receive 为空，不动');
  });

  test(
      '[NetworkQuality.excellent][NetworkQuality.good][NetworkQuality.poor][NetworkQuality.none] 默认档位表：excellent 10s、good 15s、poor 30s、none 10s（只改 connect）',
      () async {
    const expected = {
      NetworkQuality.excellent: Duration(seconds: 10),
      NetworkQuality.good: Duration(seconds: 15),
      NetworkQuality.poor: Duration(seconds: 30),
      NetworkQuality.none: Duration(seconds: 10),
    };
    var quality = NetworkQuality.excellent;
    final (dio, adapter) = _rig(DiomanTimeout(probe: () => quality));

    for (final entry in expected.entries) {
      quality = entry.key;
      await dio.get<dynamic>('/x');
      final seen = adapter.seen.last;
      expect(seen.connectTimeout, entry.value,
          reason: '${entry.key} 的默认 connect');
      expect(seen.receiveTimeout, _baseReceive, reason: '默认表不碰 receive');
      expect(seen.sendTimeout, _baseSend, reason: '默认表不碰 send');
    }
    // none 只是普通一档：不会拦截请求，也不会抛错。
    expect(adapter.calls, expected.length);
  });
}
