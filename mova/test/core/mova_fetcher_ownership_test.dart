import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';

import '../support/fake_kernel.dart';

/// 记录关闭次数的宿主 HTTP 端口。
class _HostFetch implements IMovaHttpFetch {
  /// 宿主端口被关闭的次数。
  int closes = 0;

  /// 返回空结果，不触网。
  @override
  Future<Uint8List?> get(Uri url) async => null;

  /// 记录资源关闭。
  @override
  Future<void> close() async => closes++;
}

/// 构造无平台依赖且不开控制条计时器的真实播放器。
Mova _mova(MovaPreviewOpts preview, {IMovaHttpFetch? fetcher}) =>
    Mova(
      kernel: FakeKernel(),
      fetcher: fetcher,
      brightness: MovaFallbackBrightness(),
      pip: MovaNoopPip(),
      orient: MovaNoopOrient(),
      options: MovaOpts(
        preview: preview,
        controls: const MovaCtrlsOpts(autoHide: false),
      ),
    );

void main() {
  const configurations = {
    'no VTT': MovaPreviewOpts(vttEnabled: false),
    'custom sources': MovaPreviewOpts(sources: []),
    'default VTT': MovaPreviewOpts(),
  };
  for (final entry in configurations.entries) {
    test('F-G owned fetcher cancels hanging probe and timer with ${entry.key}', () async {
      final timers = <Timer>[];
      await runZoned(() async {
        final headers = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        server.listen((req) {
          req.response.write('#EXTM3U\n');
          unawaited(req.response.flush().then((_) => headers.complete()));
        });
        final mova = _mova(entry.value);
        addTearDown(mova.dispose);
        await mova.open(MovaSource('http://127.0.0.1:${server.port}/master.m3u8'));
        final probe = mova.loadQualities();
        await headers.future.timeout(const Duration(seconds: 2));
        expect(timers.where((t) => t.isActive), hasLength(1));
        await mova.dispose().timeout(const Duration(seconds: 1));
        await probe.timeout(const Duration(seconds: 1));
        expect(timers.every((t) => !t.isActive), isTrue);
        await mova.dispose();
      }, zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          final timer = parent.createTimer(zone, duration, callback);
          if (duration == const Duration(seconds: 10)) timers.add(timer);
          return timer;
        },
      ));
    });

    test('F-G injected fetcher remains host owned with ${entry.key}', () async {
      final fetcher = _HostFetch();
      final mova = _mova(entry.value, fetcher: fetcher);
      await mova.open(const MovaSource('https://h/master.m3u8'));
      await mova.loadQualities();
      await mova.dispose();
      await mova.dispose();
      expect(fetcher.closes, 0);
      await fetcher.close();
      expect(fetcher.closes, 1);
    });
  }
}
