import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 记录 setProperty / open 调用顺序的假播放器。
class _FakePlayer extends Fake implements Player {
  _FakePlayer(this.log) : _native = _FakeNative(log);
  final List<String> log;
  final _FakeNative _native;
  final _stream = _FakeStream();

  @override
  PlatformPlayer get platform => _native;

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> open(Playable playable, {bool play = true}) async => log.add('open');

  @override
  Future<void> dispose() async {}
}

class _FakeNative extends Fake implements NativePlayer {
  _FakeNative(this.log);
  final List<String> log;

  @override
  Future<void> setProperty(String name, String value, {bool waitForInitialization = true}) async {
    // 故意让出一拍，验证 open 会等属性写完。
    await Future<void>.delayed(Duration.zero);
    log.add('set:$name=$value');
  }
}

class _FakeStream extends Fake implements PlayerStream {
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
}

void main() {
  group('MovaMpvKernel TLS', () {
    test('默认关闭：不下发任何 tls 属性', () async {
      final log = <String>[];
      final k = MovaMpvKernel(player: _FakePlayer(log), audioOnly: true, observeQoeSignals: false);
      await k.open('https://x/a.mp4');
      expect(log, ['open']);
    });

    test('tlsCaFile 未开 tlsVerify 时也不下发', () async {
      final log = <String>[];
      final k = MovaMpvKernel(player: _FakePlayer(log), audioOnly: true, observeQoeSignals: false, tlsCaFile: '/a.pem');
      await k.open('https://x/a.mp4');
      expect(log, ['open']);
    });

    test('开启：tls-verify=yes 先于 open 落地', () async {
      final log = <String>[];
      final k = MovaMpvKernel(player: _FakePlayer(log), audioOnly: true, observeQoeSignals: false, tlsVerify: true);
      await k.open('https://x/a.mp4');
      expect(log, ['set:tls-verify=yes', 'open']);
    });

    test('开启并带 CA 文件：先 tls-ca-file 再 tls-verify，再 open', () async {
      final log = <String>[];
      final k = MovaMpvKernel(
        player: _FakePlayer(log),
        audioOnly: true,
        observeQoeSignals: false,
        tlsVerify: true,
        tlsCaFile: '/data/ca.pem',
      );
      await k.open('https://x/a.mp4');
      expect(log, ['set:tls-ca-file=/data/ca.pem', 'set:tls-verify=yes', 'open']);
    });
  });
}
