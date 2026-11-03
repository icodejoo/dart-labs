import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:mova/mova.dart';
import '../support/fake_kernel.dart';

/// 带会话标记的识别器；模拟异步任务捕获旧代际。
class _Recognizer extends MovaNoopSttEngine implements MovaSttSessionEngine {
  /// 字幕出口。
  final out = StreamController<MovaSttCue>.broadcast();

  /// 最新会话代际。
  int epoch = 0;

  /// 启动次数。
  int starts = 0;

  /// 停止次数。
  int stops = 0;

  /// 实现测试所需的识别或播放器端口。
  @override
  Stream<MovaSttCue> get cues => out.stream;

  /// 实现测试所需的识别或播放器端口。
  @override
  void bindSession(int epoch) => this.epoch = epoch;

  /// 实现测试所需的识别或播放器端口。
  @override
  Future<void> start(Duration atPosition) async {
    starts++;
  }

  /// 实现测试所需的识别或播放器端口。
  @override
  Future<void> stop() async {
    stops++;
  }

  /// 推送捕获 [generation] 的字幕；null 模拟旧端口。
  void emit(int? generation) => out.add(
    MovaSttCue(
      text: 'cue',
      start: Duration.zero,
      end: const Duration(seconds: 10),
      sessionEpoch: generation,
    ),
  );

  /// 实现测试所需的识别或播放器端口。
  @override
  Future<void> dispose() => out.close();
}

/// 为默认输出目录提供工作区路径。
class _Paths extends PathProviderPlatform {
  /// 返回当前测试的输出目录。
  /// 实现测试所需的识别或播放器端口。
  @override
  Future<String?> getTemporaryPath() async => '.dart_tool';
}

/// 模拟属性设置成功或抛错的原生播放器。
class _Native extends Fake implements NativePlayer {
  /// [fail] 为 true 时模拟初始化异常。
  _Native(this.fail);

  /// 属性设置是否失败。
  final bool fail;

  /// 设置测试属性，失败时抛出错误。
  /// 实现测试所需的识别或播放器端口。
  @override
  Future<void> setProperty(String property, String value, {bool waitForInitialization = true}) async {
    if (fail) throw StateError('property');
  }
}

/// 不连接真实原生内核的播放器平台。
class _Platform extends Fake implements PlatformPlayer {}

/// 只暴露完成事件的测试流。
class _Streams extends Fake implements PlayerStream {
  /// 控制完成事件。
  final done = StreamController<bool>.broadcast();

  /// 实现测试所需的识别或播放器端口。
  @override
  Stream<bool> get completed => done.stream;
}

/// 记录资源释放，模拟 open 异常或永不完成的解码。
class _Player extends Fake implements Player {
  /// 是否在 open 抛错。
  bool fail = false;

  /// 测试时注入原生属性通道。
  NativePlayer? native;

  /// 资源释放次数。
  int disposals = 0;

  /// 原生初始化是否已尝试。
  final opened = Completer<void>();

  /// 可控制的事件流。
  final testStreams = _Streams();

  /// 实现测试所需的识别或播放器端口。
  @override
  PlatformPlayer get platform => native ?? _Platform();

  /// 实现测试所需的识别或播放器端口。
  @override
  PlayerStream get stream => testStreams;

  /// 实现测试所需的识别或播放器端口。
  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (!opened.isCompleted) opened.complete();
    if (fail) throw StateError('open');
  }

  /// 实现测试所需的识别或播放器端口。
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

/// B10 原生资源与字幕会话回归。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('音频抽取 open 异常后释放 Player 和订阅，之后仍可 dispose', () async {
    final previous = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths();
    addTearDown(() => PathProviderPlatform.instance = previous);
    for (final setupFailure in [true, false]) {
      final player = _Player()
        ..fail = true
        ..native = _Native(setupFailure);
      final extractor = MovaAudioExtractor(playerFactory: () => player);
      expect(await extractor.extractWav('a'), isNull);
      expect(player.disposals, 1);
      expect(player.testStreams.done.hasListener, isFalse);
      await extractor.dispose();
      expect(player.disposals, 1);
      await player.testStreams.done.close();
    }
  });
  test('音频抽取超时或主动取消都立即释放且恰好一次', () async {
    for (final cancel in [false, true]) {
      final player = _Player();
      final extractor = MovaAudioExtractor(
        playerFactory: () => player,
        tempDirectory: () async => '.dart_tool',
        timeout: const Duration(milliseconds: 20),
      );
      final result = extractor.extractWav('a');
      await player.opened.future;
      if (cancel) await extractor.dispose();
      expect(await result.timeout(const Duration(seconds: 1)), isNull);
      expect(player.disposals, 1);
      expect(player.testStreams.done.hasListener, isFalse);
      await extractor.dispose();
      expect(await extractor.extractWav('b'), isNull);
      expect(player.disposals, 1);
      await player.testStreams.done.close();
    }
  });
  test('换源不改 isRunning，旧任务迟到 cue 被丢弃，新代际 cue 可用', () async {
    final recognizer = _Recognizer();
    final service = MovaSttService(
      config: MovaSttConfig(enabled: true, engine: recognizer),
    );
    addTearDown(service.dispose);
    service.attach(const MovaSource('a'));
    await service.start();
    final old = recognizer.epoch;
    recognizer.emit(old);
    service.attach(const MovaSource('b'));
    recognizer.emit(old);
    await Future<void>.delayed(Duration.zero);
    expect(service.current, isNull);
    expect(service.isRunning, isTrue);
    expect(recognizer.stops, 0);
    recognizer.emit(recognizer.epoch);
    await Future<void>.delayed(Duration.zero);
    expect(service.current?.sessionEpoch, recognizer.epoch);
    await service.start();
    expect(recognizer.starts, 1);
    expect(
      MovaSttCue(
        text: 'cue',
        start: Duration.zero,
        end: const Duration(seconds: 10),
        sessionEpoch: old,
      ),
      isNot(service.current),
    );
  });
  test('旧端口无标记 cue 仅首源兼容，重复打开同源也不收旧结果', () async {
    final recognizer = _Recognizer();
    final service = MovaSttService(
      config: MovaSttConfig(enabled: true, engine: recognizer),
    );
    addTearDown(service.dispose);
    service.attach(const MovaSource('a'));
    recognizer.emit(null);
    await Future<void>.delayed(Duration.zero);
    expect(service.current, isNotNull);
    service.attach(const MovaSource('a'));
    recognizer.emit(null);
    recognizer.emit(1);
    await Future<void>.delayed(Duration.zero);
    expect(service.current, isNull);
    expect(service.isRunning, isFalse);
  });
  test('audioOnly 引擎不启动 STT、不订阅 cue，仍报告 disabled', () async {
    final recognizer = _Recognizer();
    final reasons = <MovaSttBlockReason>[];
    final engine = createMovaEngine(
      kernel: FakeKernel.audioOnly(),
      audioOnly: true,
      options: MovaOpts(
        preview: const MovaPreviewConfig(enabled: false),
        stt: MovaSttConfig(
          enabled: true,
          engine: recognizer,
          onBlocked: reasons.add,
        ),
      ),
    );
    addTearDown(engine.dispose);
    await engine.open(const MovaSource('a'));
    await engine.stt.start();
    expect(engine.stt.isRunning, isFalse);
    expect(recognizer.starts, 0);
    expect(recognizer.out.hasListener, isFalse);
    expect(reasons, [MovaSttBlockReason.disabled]);
  });
}
