import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_defaults.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 只提供 error/宽高流的假播放器。
class _FakePlayer extends Fake implements Player {
  final errors = StreamController<String>.broadcast();
  late final _stream = _FakeStream(errors.stream);

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> dispose() async {}
}

class _FakeStream extends Fake implements PlayerStream {
  _FakeStream(this._errors);
  final Stream<String> _errors;

  @override
  Stream<String> get error => _errors;
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
}

void main() {
  group('movaProtocolWhitelist', () {
    test('含 dtls', () {
      expect(movaProtocolWhitelist(), contains('dtls'));
    });

    test('是 media_kit 默认白名单的超集，且只多 dtls', () {
      final upstream = const PlayerConfiguration().protocolWhitelist;
      final mine = movaProtocolWhitelist();
      expect(mine, containsAll(upstream));
      expect(mine.toSet().difference(upstream.toSet()), {'dtls'});
    });

    test('复制的常量与 media_kit 当前默认一致（升级 media_kit 时报警）', () {
      expect(kMediaKitDefaultProtocols, const PlayerConfiguration().protocolWhitelist);
    });
  });

  group('isBenignMpvError', () {
    test('识别 mpv 的两行 seek 拒绝信息', () {
      expect(isBenignMpvError('Cannot seek in this stream.'), isTrue);
      expect(isBenignMpvError("You can force it with '--force-seekable=yes'."), isTrue);
    });

    test('真实错误不被吞', () {
      expect(isBenignMpvError('Failed to open file'), isFalse);
      expect(isBenignMpvError(''), isFalse);
    });
  });

  group('MovaMpvKernel.error', () {
    test('丢弃无害 seek 提示，其余原样透传', () async {
      final p = _FakePlayer();
      final k = MovaMpvKernel(player: p, audioOnly: true, observeQoeSignals: false);
      final got = <Object>[];
      final sub = k.error.listen(got.add);
      p.errors
        ..add('Cannot seek in this stream.')
        ..add("You can force it with '--force-seekable=yes'.")
        ..add('Failed to open file');
      await Future<void>.delayed(Duration.zero);
      expect(got, ['Failed to open file']);
      await sub.cancel();
    });
  });
}
