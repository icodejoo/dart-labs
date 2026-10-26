import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/kernel/source_options_kernel.dart';

/// 记录 setProperty / open 顺序的假播放器；getProperty 返回当前"mpv 里的值"。
class _FakePlayer extends Fake implements Player {
  _FakePlayer(this.log, this.native);
  final List<String> log;
  final _FakeNative native;
  final _stream = _FakeStream();

  @override
  PlatformPlayer get platform => native;

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> open(Playable playable, {bool play = true}) async => log.add('open:${(playable as Media).uri}');

  @override
  Future<void> dispose() async {}
}

class _FakeNative extends Fake implements NativePlayer {
  _FakeNative(this.log);
  final List<String> log;

  /// 假 mpv 里当前的属性值。
  final Map<String, String> props = {'demuxer-lavf-o': '', 'cache': 'auto'};

  /// 为 true 时 setProperty 抛错（模拟 mpv 拒绝该选项）。
  bool failSet = false;

  @override
  Future<String> getProperty(String name, {bool waitForInitialization = true}) async => props[name] ?? '';

  @override
  Future<void> setProperty(String name, String value, {bool waitForInitialization = true}) async {
    await Future<void>.delayed(Duration.zero);
    if (failSet) throw StateError('rejected');
    props[name] = value;
    log.add('set:$name=$value');
  }
}

class _FakeStream extends Fake implements PlayerStream {
  @override
  Stream<Tracks> get tracks => const Stream.empty();
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
}

void main() {
  late List<String> log;
  late _FakeNative native;
  late MovaMpvKernel kernel;

  setUp(() {
    log = <String>[];
    native = _FakeNative(log);
    kernel = MovaMpvKernel(player: _FakePlayer(log, native), audioOnly: true, observeQoeSignals: false);
  });

  test('内核具备按源选项能力', () {
    expect(kernel, isA<MovaSourceOptionsKernel>());
  });

  test('没有暂存选项：open 前不下发任何属性', () async {
    await kernel.open('whep+http://h/x');
    expect(log, ['open:whep+http://h/x']);
  });

  test('暂存的选项在 open 前落地', () async {
    kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=3000000'});
    await kernel.open('whep+http://h/x');
    expect(log, ['set:demuxer-lavf-o=media_timeout=3000000', 'open:whep+http://h/x']);
  });

  test('暂存只对紧随其后的一次 open 生效，下一次 open 还原原值，不泄漏到下一个源', () async {
    kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=3000000', 'cache': 'no'});
    await kernel.open('whep+http://h/x');
    expect(native.props['demuxer-lavf-o'], 'media_timeout=3000000');
    log.clear();
    await kernel.open('https://h/b.mp4'); // 没有再暂存
    expect(native.props['demuxer-lavf-o'], '');
    expect(native.props['cache'], 'auto');
    expect(log.last, 'open:https://h/b.mp4');
    expect(log.where((e) => e.startsWith('set:')), hasLength(2));
    log.clear();
    await kernel.open('https://h/c.mp4');
    expect(log, ['open:https://h/c.mp4'], reason: '已还原，不再重复写');
  });

  test('连续两个带选项的源：先还原再下发新的', () async {
    kernel.stageSourceOptions({'cache': 'no'});
    await kernel.open('a');
    log.clear();
    kernel.stageSourceOptions({'demuxer-lavf-o': 'x=1'});
    await kernel.open('b');
    expect(log, ['set:cache=auto', 'set:demuxer-lavf-o=x=1', 'open:b']);
    expect(native.props['cache'], 'auto');
  });

  test('mpv 拒绝某个选项：吞掉错误，open 照常进行，且之后的还原不会抛', () async {
    native.failSet = true;
    kernel.stageSourceOptions({'cache': 'no'});
    await kernel.open('a');
    expect(log, ['open:a']);
    native.failSet = false;
    await kernel.open('b');
    expect(log.last, 'open:b');
  });
}
