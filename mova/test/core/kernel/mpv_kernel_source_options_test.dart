import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';
import 'package:mova/src/core/kernel/mpv_keyvalue.dart';
import 'package:mova/src/core/kernel/source_options_kernel.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/model/playback_error.dart';

/// Records native operations and defers Media cache lookup until load.
///
/// 记录原生操作，将 Media 缓存读取推迟到加载钩子执行时。
class _FakePlayer extends Fake implements Player {
  _FakePlayer(this.log, this.native);
  final List<String> log;
  final _FakeNative native;
  final _stream = _FakeStream();
  final opened = <Media>[];

  /// Mirrors media_kit 1.2.6's unload clearing and lazy on_load cache lookup.
  ///
  /// 模拟 media_kit 1.2.6 卸载清头及 on_load 惰性读取缓存的行为。
  Map<String, String>? loadHeaders(int index) {
    native.props['http-header-fields'] = '';
    final headers = Media(opened[index].uri).httpHeaders;
    if (headers != null) {
      native.props['http-header-fields'] = headers.entries
          .map((e) => '${e.key}: ${e.value}')
          .join(',');
    }
    return headers;
  }

  @override
  PlatformPlayer get platform => native;

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add(playable as Media);
    log.add('open:${playable.uri}');
  }

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

  /// One-shot barriers for property and list writes.
  ///
  /// 属性及列表写入的一次性阻塞点。
  Future<void> Function()? beforeSet;
  Future<void> Function()? beforeCommand;

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
    final barrier = beforeSet;
    beforeSet = null;
    await barrier?.call();
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
    final barrier = beforeCommand;
    beforeCommand = null;
    await barrier?.call();
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

/// Supplies empty player streams for isolated kernel option tests.
///
/// 为内核选项隔离测试提供空播放器流。
class _FakeStream extends Fake implements PlayerStream {
  /// No player failures are emitted by this fixture.
  ///
  /// 此夹具不发出播放器错误。
  @override
  Stream<String> get error => const Stream.empty();

  /// No native logs are emitted by this fixture.
  ///
  /// 此夹具不发出原生日志。
  @override
  Stream<PlayerLog> get log => const Stream.empty();
  @override
  Stream<Tracks> get tracks => const Stream.empty();
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
}

/// Exercises source option application, restoration and header isolation.
///
/// 验证按源选项下发、还原以及请求头隔离。
void main() {
  for (final entry in {
    'Referer': 'https://cp3.example/authorized',
    'X-Token': '甲,乙: token',
    'User-Agent': 'custom agent',
  }.entries) {
    test('C07 Media 加载钩子接收 ${entry.key} 且下次打开清除', () async {
      final log = <String>[];
      final player = _FakePlayer(log, _FakeNative(log));
      final kernel = MovaMpvKernel(player: player, audioOnly: true, observeQoeSignals: false);
      addTearDown(kernel.dispose);
      final source = MovaSource('https://h/a.m3u8', headers: {entry.key: entry.value});
      kernel.stageSourceOptions(source.mpvOptionsFor(source.uri));
      await kernel.open(source.uri);
      expect(player.opened.last.httpHeaders, source.requestHeaders);
      expect(player.loadHeaders(0), source.requestHeaders);
      await kernel.open('https://h/b.mp4');
      expect(player.opened.last.httpHeaders, isEmpty);
      expect(player.loadHeaders(1), isEmpty);
    });
  }

  test('同 URL 双内核延迟加载钩子保持各自 token', () async {
    final log = <String>[];
    final first = _FakePlayer(log, _FakeNative(log));
    final second = _FakePlayer(log, _FakeNative(log));
    final kernels = [
      for (final player in [first, second])
        MovaMpvKernel(
          player: player,
          audioOnly: true,
          observeQoeSignals: false,
        ),
    ];
    for (final kernel in kernels) {
      addTearDown(kernel.dispose);
    }
    const uri = 'https://h/same.m3u8?signature=a%2Fb#original';
    kernels[0].stageSourceOptions({
      'http-header-fields': 'Authorization: user-a',
    });
    await kernels[0].open(uri);
    kernels[1].stageSourceOptions({
      'http-header-fields': 'Authorization: user-b',
    });
    await kernels[1].open(uri);
    expect(first.opened.single.uri, isNot(second.opened.single.uri));
    expect(Uri.parse(first.opened.single.uri).query, Uri.parse(uri).query);
    expect(
      Uri.parse(first.opened.single.uri).fragment,
      startsWith('original&'),
    );
    expect(second.loadHeaders(0), {'Authorization': 'user-b'});
    expect(first.loadHeaders(0), {'Authorization': 'user-a'});
  });

  test('同内核同 URL 重试早于首次加载钩子时请求头按尝试隔离', () async {
    final log = <String>[];
    final player = _FakePlayer(log, _FakeNative(log));
    final kernel = MovaMpvKernel(
      player: player,
      audioOnly: true,
      observeQoeSignals: false,
    );
    addTearDown(kernel.dispose);
    for (final token in ['initial', 'retry']) {
      kernel.stageSourceOptions({'http-header-fields': 'X-Token: $token'});
      await kernel.open('https://h/retry.mp4');
    }
    expect(player.loadHeaders(0), {'X-Token': 'initial'});
    expect(player.loadHeaders(1), {'X-Token': 'retry'});
    await kernel.open('https://h/retry.mp4');
    expect(player.loadHeaders(2), isEmpty);
  });

  test('畸形请求头保留 null 并报告非抛出诊断且后续加载可恢复', () async {
    final log = <String>[];
    final player = _FakePlayer(log, _FakeNative(log));
    final kernel = MovaMpvKernel(
      player: player,
      audioOnly: true,
      observeQoeSignals: false,
    );
    addTearDown(kernel.dispose);
    expect(kernel.error.isBroadcast, isTrue);
    expect(kernel.kernelErrors.isBroadcast, isTrue);
    final errors = <Object>[];
    final diagnostics = <MovaKernelError>[];
    final errorSub = kernel.error.listen(errors.add);
    final diagnosticSub = kernel.kernelErrors.listen(diagnostics.add);
    addTearDown(errorSub.cancel);
    addTearDown(diagnosticSub.cancel);
    kernel.stageSourceOptions({'http-header-fields': 'X-Token: secret'});
    await kernel.open('https://h/bad.mp4');
    kernel.stageSourceOptions({
      'http-header-fields': '"X-Token: unclosed-secret',
    });
    await expectLater(kernel.open('https://h/bad.mp4'), completes);
    expect(player.opened.last.httpHeaders, isNull);
    expect(Media(player.opened.last.uri).httpHeaders, isNull);
    await Future<void>.delayed(Duration.zero);
    expect(errors.single.toString(), contains('Invalid http-header-fields'));
    expect(errors.single.toString(), isNot(contains('secret')));
    expect(diagnostics.single.subsystem, 'mova-options');
    expect(
      classifyMovaPlaybackError(
        diagnostics.single.error,
        subsystem: diagnostics.single.subsystem,
        afterFirstFrame: false,
      ).fatal,
      isFalse,
    );
    kernel.stageSourceOptions({'http-header-fields': 'X-Token: recovered'});
    await kernel.open('https://h/bad.mp4');
    expect(player.loadHeaders(2), {'X-Token': 'recovered'});
  });
  late List<String> log;
  late _FakeNative native;
  late MovaMpvKernel kernel;

  setUp(() {
    log = <String>[];
    native = _FakeNative(log);
    kernel = MovaMpvKernel(player: _FakePlayer(log, native), audioOnly: true, observeQoeSignals: false);
  });

  for (final listWrite in [true, false]) {
    test('B2 overlapping opens serialize source options listWrite=$listWrite', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      // Pause A inside a native write, then request B with different values.
      //
      // 将 A 阻塞在原生写入内，再请求选项值不同的 B。
      Future<void> blockWrite() async {
        entered.complete();
        await release.future;
      }

      if (listWrite) {
        native.beforeCommand = blockWrite;
      } else {
        native.beforeSet = blockWrite;
      }
      final defaults = Map.of(native.lavf);
      kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=100', 'cache': 'no'});
      final first = kernel.open('a');
      await entered.future;
      kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=200', 'cache': 'yes'});
      final second = kernel.open('b');
      await pumpEventQueue();
      expect(log, isNot(contains('set:cache=yes')));
      release.complete();
      await Future.wait([first, second]);
      expect(log.where((v) => v.startsWith('open:')), ['open:b']);
      expect(native.props['cache'], 'yes');
      expect(native.lavf['media_timeout'], '200');
      await kernel.open('c');
      expect(native.props['cache'], 'auto');
      expect(native.lavf, defaults);
      await kernel.dispose();
    });
  }

  test('B2 overlapping restore preserves option baselines for the newest source', () async {
    final defaults = Map.of(native.lavf);
    kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=100', 'cache': 'no'});
    await kernel.open('a');
    final entered = Completer<void>();
    final release = Completer<void>();
    native.beforeCommand = () async {
      entered.complete();
      await release.future;
    };
    kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=200', 'cache': 'yes'});
    final second = kernel.open('b');
    await entered.future;
    kernel.stageSourceOptions({'demuxer-lavf-o': 'media_timeout=300', 'cache': 'always'});
    final third = kernel.open('c');
    await pumpEventQueue();
    expect(log, isNot(contains('set:cache=always')));
    release.complete();
    await Future.wait([second, third]);
    expect(log.where((v) => v.startsWith('open:')), ['open:a', 'open:c']);
    expect(native.props['cache'], 'always');
    expect(native.lavf['media_timeout'], '300');
    await kernel.open('d');
    expect(native.props['cache'], 'auto');
    expect(native.lavf, defaults);
    await kernel.dispose();
  });

  test('内核具备按源选项能力', () {
    expect(kernel, isA<IMovaSourceOptionsKernel>());
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
