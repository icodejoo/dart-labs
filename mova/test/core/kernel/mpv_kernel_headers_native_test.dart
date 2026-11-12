import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// Verifies cache isolation through real libmpv hooks and HTTP requests.
///
/// 通过真实 libmpv 钩子和 HTTP 请求验证缓存隔离。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = File('libmpv/windows-x64/libmpv-2.dll');
  test('真实 mpv 延迟加载同 URL：隔离请求头且不改变 HTTP 目标', () async {
    MediaKit.ensureInitialized(libmpv: library.absolute.path);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <({String target, String? token, String? referer, String? agent})>[];
    final secondRequested = Completer<void>();
    final bothRequested = Completer<void>();
    final subscription = server.listen((request) async {
      requests.add((target: request.uri.toString(), token: request.headers.value('x-token'),
        referer: request.headers.value('referer'), agent: request.headers.value('user-agent')));
      if (requests.length == 1) secondRequested.complete();
      if (requests.length == 2) bothRequested.complete();
      request.response.headers.contentType = ContentType('audio', 'wav');
      request.response.add(_silentWav());
      await request.response.close();
    });
    final players = [Player(), Player()];
    final kernels = [for (final player in players)
      MovaMpvKernel(player: player, audioOnly: true, observeQoeSignals: false)];
    final entered = Completer<void>();
    final release = Completer<void>();
    (players[0].platform as NativePlayer).onLoadHooks.add(() async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    });
    addTearDown(() async {
      if (!release.isCompleted) release.complete();
      for (final kernel in kernels) {
        await kernel.dispose();
      }
      await subscription.cancel();
      await server.close(force: true);
    });
    for (final player in players) {
      await (player.platform as NativePlayer).setProperty('ao', 'null');
    }
    final uri = 'http://127.0.0.1:${server.port}/same.wav?signature=a%2Fb#original';
    kernels[0].stageSourceOptions({'http-header-fields':
      'X-Token: user-a,Referer: https://cp3.example/a,User-Agent: mova-a'});
    await kernels[0].open(uri);
    await entered.future.timeout(const Duration(seconds: 10));
    kernels[1].stageSourceOptions({'http-header-fields':
      'X-Token: user-b,Referer: https://cp3.example/b,User-Agent: mova-b'});
    await kernels[1].open(uri);
    await secondRequested.future.timeout(const Duration(seconds: 10));
    release.complete();
    await bothRequested.future.timeout(const Duration(seconds: 10));
    expect(requests.take(2).toList(), [
      (target: '/same.wav?signature=a%2Fb', token: 'user-b', referer: 'https://cp3.example/b', agent: 'mova-b'),
      (target: '/same.wav?signature=a%2Fb', token: 'user-a', referer: 'https://cp3.example/a', agent: 'mova-a'),
    ]);
  }, skip: !Platform.isWindows || !library.existsSync()
      ? 'Requires the repository Windows libmpv binary' : false);
}

/// Encodes one second of silent PCM without external media fixtures.
///
/// 编码一秒静音 PCM，无需外部媒体夹具。
Uint8List _silentWav() {
  final bytes = Uint8List(44 + 16000);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, 'RIFF'.codeUnits);
  data.setUint32(4, bytes.length - 8, Endian.little);
  bytes.setRange(8, 16, 'WAVEfmt '.codeUnits);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, 8000, Endian.little);
  data.setUint32(28, 16000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  bytes.setRange(36, 40, 'data'.codeUnits);
  data.setUint32(40, 16000, Endian.little);
  return bytes;
}
