import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/engine.dart';
import 'package:mova/src/core/events/events.dart';
import 'package:mova/src/core/kernel/mpv_defaults.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

const _codecAttempt = 'Could not open codec.';
const _decoderFailed = "Failed to initialize a decoder for codec 'h264'.";
const _formatFailed = 'Failed to recognize file format.';
const _cannotSeek = 'Cannot seek in this stream.';
const _forceSeekable = "You can force it with '--force-seekable=yes'.";
const _fileFailed = 'Failed to open file';

/// A player double exposing streams without a native mpv instance.
///
/// 无需原生 mpv 实例、只提供流的假播放器。
class _FakePlayer extends Fake implements Player {
  final errors = StreamController<String>.broadcast();
  late final _stream = _FakeStream(errors.stream);

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> dispose() async {}
}

/// Empty playback streams plus injectable error diagnostics.
///
/// 提供空播放流与可注入的错误诊断。
class _FakeStream extends Fake implements PlayerStream {
  @override
  Stream<bool> get playing => const Stream.empty();
  @override
  Stream<bool> get buffering => const Stream.empty();
  @override
  Stream<bool> get completed => const Stream.empty();
  @override
  Stream<Duration> get position => const Stream.empty();
  @override
  Stream<Duration> get duration => const Stream.empty();
  @override
  Stream<Duration> get buffer => const Stream.empty();
  @override
  Stream<Tracks> get tracks => const Stream.empty();
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
      expect(isBenignMpvError(_cannotSeek), isTrue);
      expect(isBenignMpvError(_forceSeekable), isTrue);
    });

    test('真实错误不被吞', () {
      expect(isBenignMpvError(_fileFailed), isFalse);
      expect(isBenignMpvError(''), isFalse);
    });

    test('单次 codec 尝试失败可降级，允许日志首尾空白', () {
      expect(isBenignMpvError(_codecAttempt), isTrue);
      expect(isBenignMpvError('  $_codecAttempt\n'), isTrue);
    });

    test('只精确过滤 codec 尝试行，不扩展为同前缀过滤', () {
      expect(isBenignMpvError('$_codecAttempt Additional failure'), isFalse);
      expect(isBenignMpvError(_decoderFailed), isFalse);
      expect(isBenignMpvError(_formatFailed), isFalse);
    });
  });

  group('MovaMpvKernel.error', () {
    test('丢弃无害 seek 提示，其余原样透传', () async {
      final p = _FakePlayer();
      final k = MovaMpvKernel(player: p, audioOnly: true, observeQoeSignals: false);
      final got = <Object>[];
      final sub = k.error.listen(got.add);
      p.errors
        ..add(_cannotSeek)
        ..add(_forceSeekable)
        ..add(_fileFailed);
      await Future<void>.delayed(Duration.zero);
      expect(got, [_fileFailed]);
      await sub.cancel();
      await k.dispose();
      await p.errors.close();
    });
  });

  group('codec diagnostics with recovery disabled', () {
    late _FakePlayer player;
    late MovaEngine engine;
    late List<MovaErrorEvent> errors;
    late StreamSubscription<MovaEvent> subscription;

    setUp(() {
      player = _FakePlayer();
      engine = MovaEngine(kernel: MovaMpvKernel(player: player, audioOnly: true, observeQoeSignals: false));
      errors = [];
      subscription = engine.events.listen((event) {
        if (event is MovaErrorEvent) errors.add(event);
      });
    });

    tearDown(() async {
      await subscription.cancel();
      await engine.dispose();
      await player.errors.close();
    });

    test('回落成功的三次 codec 尝试不置 error、不发错误事件', () async {
      player.errors
        ..add(_codecAttempt)
        ..add(_codecAttempt)
        ..add(_codecAttempt);
      await Future<void>.delayed(Duration.zero);
      expect(engine.state.error, isNull);
      expect(errors, isEmpty);
    });

    test('codec 打开失败且耗尽解码器时仍置 error 并发错误事件', () async {
      player.errors
        ..add(_codecAttempt)
        ..add(_decoderFailed);
      await Future<void>.delayed(Duration.zero);
      expect(engine.state.error, _decoderFailed);
      expect(errors.map((event) => event.error), [_decoderFailed]);
    });

    test('裁剪掉的容器仍置 error 并发错误事件', () async {
      player.errors.add(_formatFailed);
      await Future<void>.delayed(Duration.zero);
      expect(engine.state.error, _formatFailed);
      expect(errors.map((event) => event.error), [_formatFailed]);
    });

    test('原有 Cannot seek 两行不置 error、不发错误事件', () async {
      player.errors
        ..add(_cannotSeek)
        ..add(_forceSeekable);
      await Future<void>.delayed(Duration.zero);
      expect(engine.state.error, isNull);
      expect(errors, isEmpty);
    });
  });
}
