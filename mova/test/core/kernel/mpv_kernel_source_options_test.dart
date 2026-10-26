import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/kernel/mpv_keyvalue.dart';
import 'package:mova/src/core/kernel/source_options_kernel.dart';

/// 记录 setProperty / command / open 顺序的假播放器；getProperty 返回当前"mpv 里的值"。
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

  /// 假 mpv 里当前的普通属性值。
  final Map<String, String> props = {'cache': 'auto'};

  /// 假 mpv 里 `demuxer-lavf-o` 的键值项（按插入顺序），初值同 media_kit 的默认值。
  final Map<String, String> lavf = {
    'seg_max_retry': '5',
    'strict': 'experimental',
    'allowed_extensions': 'ALL',
    'protocol_whitelist': 'file,crypto,data',
  };

  /// 为 true 时 setProperty / command 抛错（模拟 mpv 拒绝该选项）。
  bool failSet = false;

  /// mpv 拒绝（解析失败）的写入记录，对应真机上的 `Expected '=' and a value.`。
  final List<String> rejected = [];

  @override
  Future<String> getProperty(String name, {bool waitForInitialization = true}) async {
    // 和真机一致：读出的串不给含逗号的值加引，没法再被严格解析。
    if (name == 'demuxer-lavf-o') return lavf.entries.map((e) => '${e.key}=${e.value}').join(',');
    return props[name] ?? '';
  }

  @override
  Future<void> setProperty(String name, String value, {bool waitForInitialization = true}) async {
    await Future<void>.delayed(Duration.zero);
    if (failSet) throw StateError('rejected');
    if (name == 'demuxer-lavf-o') {
      final parsed = parseMpvKeyValueList(value);
      if (parsed == null) {
        rejected.add(value);
        return;
      }
      lavf
        ..clear()
        ..addEntries(parsed);
      log.add('set:$name=$value');
      return;
    }
    props[name] = value;
    log.add('set:$name=$value');
  }

  @override
  Future<void> command(List<String> command, {bool waitForInitialization = true}) async {
    await Future<void>.delayed(Duration.zero);
    if (failSet) throw StateError('rejected');
    final [cmd, name, op, value] = command;
    expect(cmd, 'change-list');
    expect(name, 'demuxer-lavf-o');
    switch (op) {
      case 'add':
        final parsed = parseMpvKeyValueList(value);
        if (parsed == null) {
          rejected.add(value);
          return;
        }
        for (final e in parsed) {
          lavf
            ..remove(e.key)
            ..[e.key] = e.value;
        }
      case 'append':
        final eq = value.indexOf('=');
        final key = value.substring(0, eq);
        lavf
          ..remove(key)
          ..[key] = value.substring(eq + 1);
      case 'remove':
        lavf.remove(value);
      default:
        fail('unexpected op $op');
    }
    log.add('list:$op:$value');
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
    expect(log, ['list:add:media_timeout=3000000', 'open:whep+http://h/x']);
  });

  test('暂存只对紧随其后的一次 open 生效，下一次 open 还原原值，不泄漏到下一个源', () async {
    final defaults = Map.of(native.lavf);
    kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=3000000', 'cache': 'no'});
    await kernel.open('whep+http://h/x');
    expect(native.lavf['media_timeout'], '3000000');
    log.clear();
    await kernel.open('https://h/b.mp4'); // 没有再暂存
    expect(native.lavf, defaults);
    expect(native.props['cache'], 'auto');
    expect(log, ['set:cache=auto', 'list:remove:media_timeout', 'open:https://h/b.mp4']);
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
    expect(log, ['set:cache=auto', 'list:add:x=1', 'open:b']);
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

  group('demuxer-lavf-o 键值列表', () {
    test('下发后原有键一个不丢（含值里带逗号的 protocol_whitelist）', () async {
      kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=3000000,foo=bar'});
      await kernel.open('whep+http://h/x');
      expect(native.lavf, {
        'seg_max_retry': '5',
        'strict': 'experimental',
        'allowed_extensions': 'ALL',
        'protocol_whitelist': 'file,crypto,data',
        'media_timeout': '3000000',
        'foo': 'bar',
      });
    });

    test('切到点播源后不残留，默认值原样，且不产生 mpv 拒绝', () async {
      final defaults = Map.of(native.lavf);
      kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=3000000,foo=bar'});
      await kernel.open('whep+http://h/x');
      await kernel.open('https://h/vod.mp4');
      expect(native.lavf, defaults);
      expect(native.lavf.containsKey('media_timeout'), isFalse);
      expect(native.rejected, isEmpty);
    });

    test('同名键原来有值：本源期间被覆盖，还原后回到原值（含逗号的值）', () async {
      final defaults = Map.of(native.lavf);
      kernel.stageSourceOptions({'demuxer-lavf-o': 'protocol_whitelist=http,strict=normal'});
      await kernel.open('a');
      expect(native.lavf['strict'], 'normal');
      expect(native.lavf['protocol_whitelist'], 'http');
      await kernel.open('b');
      expect(native.lavf, containsPair('strict', 'experimental'));
      expect(native.lavf, containsPair('protocol_whitelist', 'file,crypto,data'));
      expect(native.lavf, defaults); // Map 相等不看顺序
      expect(native.rejected, isEmpty);
    });

    test('值带逗号/等号的用 %长度% 写法：按解码后的值下发并还原', () async {
      kernel.stageSourceOptions({'demuxer-lavf-o': 'headers=%7%a=1,b=2'});
      await kernel.open('a');
      expect(native.lavf['headers'], 'a=1,b=2');
      await kernel.open('b');
      expect(native.lavf.containsKey('headers'), isFalse);
    });

    test('语法不合法：整项跳过，不写 mpv、不记还原', () async {
      final defaults = Map.of(native.lavf);
      kernel.stageSourceOptions({'demuxer-lavf-o': 'oops'});
      await kernel.open('a');
      expect(log, ['open:a']);
      await kernel.open('b');
      expect(native.lavf, defaults);
    });

    test('mpv 拒绝写入：不记还原，之后切源不抛', () async {
      native.failSet = true;
      kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=1'});
      await kernel.open('a');
      native.failSet = false;
      await kernel.open('b');
      expect(log.last, 'open:b');
      expect(native.lavf.containsKey('media_timeout'), isFalse);
    });
  });
}
