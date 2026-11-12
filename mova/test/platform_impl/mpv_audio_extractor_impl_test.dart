import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/platform_impl/mpv_audio_extractor_impl.dart';

/// Records native options and can reject a format requirement.
///
/// 记录原生选项，并可拒绝格式要求。
class _Native extends Fake implements NativePlayer {
  final properties = <String, String>{};
  String? rejectedProperty;

  /// Records each option, rejecting the selected property if requested.
  ///
  /// 记录每个选项，并按需拒绝选定的属性。
  @override
  Future<void> setProperty(
    String name,
    String value, {
    bool waitForInitialization = true,
  }) async {
    if (name == rejectedProperty) throw StateError('unsupported format');
    properties[name] = value;
  }
}

/// Supplies completion events without a native decoder.
///
/// 无需原生解码器即可提供完成事件。
class _Streams extends Fake implements PlayerStream {
  final completedController = StreamController<bool>.broadcast();

  /// Exposes the controllable completion stream.
  ///
  /// 暴露可控的完成流。
  @override
  Stream<bool> get completed => completedController.stream;
}

/// Models a player that flushes its output only after disposal completes.
///
/// 模拟直到释放完成才刷新输出的播放器。
class _Player extends Fake implements Player {
  final native = _Native();
  final testStreams = _Streams();
  final opened = Completer<void>();
  final disposing = Completer<void>();
  final propertiesAtOpen = <String, String>{};
  Completer<void>? disposeGate;
  bool failDispose = false;
  bool completeOnOpen = false;
  int disposals = 0;

  /// Exposes the recorded native options.
  ///
  /// 暴露记录原生选项的接口。
  @override
  NativePlayer get platform => native;

  /// Exposes the completion stream.
  ///
  /// 暴露完成流。
  @override
  PlayerStream get stream => testStreams;

  /// Writes a partial output and captures options before decode starts.
  ///
  /// 写出半成品，并在解码开始前记录选项。
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    propertiesAtOpen.addAll(native.properties);
    await File(native.properties['ao-pcm-file']!).writeAsString('partial');
    opened.complete();
    if (completeOnOpen) testStreams.completedController.add(true);
  }

  /// Flushes the output after the gate opens and optionally reports failure.
  ///
  /// 闸门打开后刷新输出，并可报告失败。
  @override
  Future<void> dispose() async {
    disposals++;
    disposing.complete();
    await disposeGate?.future;
    final path = native.properties['ao-pcm-file'];
    if (path != null) await File(path).writeAsString('flushed');
    if (failDispose) throw StateError('dispose');
  }
}

/// Verifies cancellation cleanup ordering and the audio output requirements.
///
/// 验证取消清理顺序与音频输出要求。
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mova_audio_review_');
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final failDispose in [false, true]) {
    test(
      'cancellation waits for pending disposal before deleting WAV (failure: $failDispose) / 取消后等待释放再删 WAV',
      () async {
        final player = _Player()
          ..disposeGate = Completer<void>()
          ..failDispose = failDispose;
        final extractor = MovaAudioExtractor(
          playerFactory: () => player,
          tempDirectory: () async => directory.path,
        );
        addTearDown(player.testStreams.completedController.close);
        var settled = false;
        final result = extractor.extractWav('https://h/audio').then((value) {
          settled = true;
          return value;
        });
        await player.opened.future;
        final path = player.native.properties['ao-pcm-file']!;
        final disposal = extractor.dispose();
        await player.disposing.future;
        try {
          await pumpEventQueue();
          expect(settled, isFalse);
          expect(await File(path).exists(), isTrue);
        } finally {
          player.disposeGate!.complete();
          await disposal;
          await result;
        }
        expect(await result, isNull);
        expect(await File(path).exists(), isFalse);
        expect(player.disposals, 1);
        expect(player.testStreams.completedController.hasListener, isFalse);
      },
    );
  }

  test(
    'audio format is mono 16kHz before opening media / 打开媒体前设置单声道 16kHz',
    () async {
      final player = _Player()..completeOnOpen = true;
      final extractor = MovaAudioExtractor(
        playerFactory: () => player,
        tempDirectory: () async => directory.path,
      );
      addTearDown(extractor.dispose);
      addTearDown(player.testStreams.completedController.close);
      final output = await extractor.extractWav('https://h/stereo_48k');
      expect(output, isNotNull);
      expect(player.propertiesAtOpen['audio-samplerate'], '16000');
      expect(player.propertiesAtOpen['audio-channels'], 'mono');
      expect(await File(output!).readAsString(), 'flushed');
      expect(player.disposals, 1);
    },
  );

  for (final property in ['audio-samplerate', 'audio-channels']) {
    test(
      'unsupported $property returns null and releases player / 格式设置失败返回 null 并释放播放器',
      () async {
        final player = _Player()
          ..completeOnOpen = true
          ..native.rejectedProperty = property;
        final extractor = MovaAudioExtractor(
          playerFactory: () => player,
          tempDirectory: () async => directory.path,
        );
        addTearDown(extractor.dispose);
        addTearDown(player.testStreams.completedController.close);
        expect(await extractor.extractWav('https://h/audio'), isNull);
        expect(player.opened.isCompleted, isFalse);
        expect(player.disposals, 1);
        expect(await directory.list().toList(), isEmpty);
      },
    );
  }
}
