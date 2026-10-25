import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mova/src/core/kernel/mpv_defaults.dart';
import 'package:mova/src/core/kernel/mpv_kernel.dart';

/// 记录 setProperty / open 调用顺序、可模拟"打开后 mpv 识别出格式"的假播放器。
class _FakePlayer extends Fake implements Player {
  _FakePlayer(this.log) : native = _FakeNative(log);
  final List<String> log;
  final _FakeNative native;
  final _stream = _FakeStream();

  /// 为 true 时 open 抛错（模拟打开失败）。
  bool failOpen = false;

  /// 按 URI 推断格式：whep -> whep，rtsp -> rtsp，.m3u8 -> hls，.ts -> mpegts，其余 mp4。
  static String formatOf(String uri) {
    if (uri.startsWith('whep')) return 'whep';
    if (uri.startsWith('rtsp')) return 'rtsp';
    if (uri.endsWith('.m3u8')) return 'hls';
    if (uri.endsWith('.ts')) return 'mpegts';
    return 'mov,mp4,m4a,3gp,3g2,mj2';
  }

  /// 按 URI 登记的 seekable / duration 读数序列；未登记时为"可 seek、时长恒定 40s"。
  final Map<String, (List<String>, List<String>)> profiles = {};

  @override
  PlatformPlayer get platform => native;

  @override
  PlayerStream get stream => _stream;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    log.add('open');
    if (failOpen) throw StateError('open failed');
    final uri = (playable as Media).uri;
    native.format = formatOf(uri);
    final prof = profiles[uri];
    native.seekable = _Seq(prof?.$1 ?? const ['yes']);
    native.duration = _Seq(prof?.$2 ?? const ['40.0']);
    // 模拟加载完成后 mpv 刷新 track-list。
    Future<void>.delayed(const Duration(milliseconds: 5), () => _stream.tracksCtl.add(_loaded));
  }

  @override
  Future<void> dispose() async {}
}

/// 已识别出真实轨道的 track-list。
final _loaded = Tracks(video: [VideoTrack.auto(), VideoTrack.no(), VideoTrack('1', null, null)]);

class _FakeNative extends Fake implements NativePlayer {
  _FakeNative(this.log);
  final List<String> log;

  /// 假的初始属性值（模拟 media_kit 已改过的默认值）。
  static const origBack = '33554432';
  static const origSeek = 'auto';

  /// 当前 `file-format` 属性值。
  String format = '';

  /// 为 true 时读原值抛错（模拟读不到）。
  bool failRead = false;

  /// `seekable` 的逐次读数序列（读完后重复最后一个值）。
  _Seq seekable = _Seq(const ['yes']);

  /// `duration` 的逐次读数序列；空串表示 mpv 报告不可用。
  _Seq duration = _Seq(const ['40.0']);

  @override
  Future<String> getProperty(String name, {bool waitForInitialization = true}) async {
    if (name == kFileFormat) return format;
    if (name == kSeekable) return seekable.next();
    if (name == kDuration) return duration.next();
    if (failRead) throw StateError('read failed');
    return name == kDemuxerMaxBackBytes ? origBack : origSeek;
  }

  @override
  Future<void> setProperty(String name, String value, {bool waitForInitialization = true}) async {
    await Future<void>.delayed(Duration.zero);
    log.add('set:$name=$value');
  }
}

/// 按次序返回读数的序列，读完后一直返回最后一个值。
class _Seq {
  _Seq(this.values);
  final List<String> values;
  int _i = 0;

  /// 取下一个读数。
  String next() => values[_i < values.length ? _i++ : values.length - 1];
}

class _FakeStream extends Fake implements PlayerStream {
  final tracksCtl = StreamController<Tracks>.broadcast();
  @override
  Stream<Tracks> get tracks => tracksCtl.stream;
  @override
  Stream<int?> get width => const Stream.empty();
  @override
  Stream<int?> get height => const Stream.empty();
}

const _on = ['set:$kDemuxerMaxBackBytes=$kLiveMaxBackBytes', 'set:$kDemuxerSeekableCache=$kLiveSeekableCache'];
const _off = ['set:$kDemuxerMaxBackBytes=${_FakeNative.origBack}', 'set:$kDemuxerSeekableCache=${_FakeNative.origSeek}'];
const _offFallback = ['set:$kDemuxerMaxBackBytes=$kVodMaxBackBytes', 'set:$kDemuxerSeekableCache=$kVodSeekableCache'];
const _whep = 'whep://x/a';
const _hls = 'https://x/live.m3u8';
const _mp4 = 'https://x/a.mp4';
const _rtsp = 'rtsp://x/a';
const _liveTs = 'http://x/live.ts';
const _vodTs = 'http://x/vod.ts';

/// 测试里的兜底探测间隔（真实默认 1.5s）。
const _probeGap = Duration(milliseconds: 10);

/// 等假播放器的 track-list 事件及随后的属性写入落地。
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  late List<String> log;
  late _FakePlayer player;
  late MovaMpvKernel k;

  setUp(() {
    log = <String>[];
    player = _FakePlayer(log);
    k = MovaMpvKernel(player: player, audioOnly: true, observeQoeSignals: false, liveProbeInterval: _probeGap);
  });

  group('按真实格式限制后向缓冲', () {
    test('mp4：始终不碰属性', () async {
      await k.open(_mp4);
      await settle();
      expect(log, ['open']);
    });

    test('hls（含 HLS 直播）：不限制', () async {
      await k.open(_hls);
      await settle();
      expect(log, ['open']);
    });

    test('whep：open 后识别出格式才套限制', () async {
      await k.open(_whep);
      expect(log, ['open']);
      await settle();
      expect(log, ['open', ..._on]);
    });

    test('whep 重复事件：只套一次', () async {
      await k.open(_whep);
      await settle();
      player._stream.tracksCtl.add(_loaded);
      await settle();
      expect(log, ['open', ..._on]);
    });

    test('whep -> hls：切源前还原原值，hls 不再限制', () async {
      await k.open(_whep);
      await settle();
      log.clear();
      await k.open(_hls);
      await settle();
      expect(log, [..._off, 'open']);
    });

    test('whep -> mp4 -> whep：再次限制', () async {
      await k.open(_whep);
      await settle();
      await k.open(_mp4);
      await settle();
      log.clear();
      await k.open(_whep);
      await settle();
      expect(log, ['open', ..._on]);
    });

    test('还原时读不到原值：用兜底常量', () async {
      player.native.failRead = true;
      await k.open(_whep);
      await settle();
      log.clear();
      await k.open(_mp4);
      expect(log, [..._offFallback, 'open']);
    });

    test('限制中打开失败：先还原，不残留限制', () async {
      await k.open(_whep);
      await settle();
      log.clear();
      player.failOpen = true;
      await expectLater(k.open(_whep), throwsStateError);
      await settle();
      expect(log, [..._off, 'open']);
    });

    test('whep 打开失败：从未套限制', () async {
      player.failOpen = true;
      await expectLater(k.open(_whep), throwsStateError);
      await settle();
      expect(log, ['open']);
    });

    test('whep 加载中途换成 hls：不残留限制', () async {
      await k.open(_whep);
      await k.open(_hls);
      await settle();
      expect(log, ['open', 'open']);
    });

    test('空轨道（切源时的重置事件）不触发判断', () async {
      await k.open(_whep);
      player._stream.tracksCtl.add(const Tracks());
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(log, ['open']);
      await settle();
      expect(log, ['open', ..._on]);
    });
  });

  group('兜底：不可 seek 且时长随时间增长', () {
    test('集合内格式（注入 rtsp）：打开后即限制', () async {
      final kr = MovaMpvKernel(
        player: player,
        audioOnly: true,
        observeQoeSignals: false,
        liveProbeInterval: _probeGap,
        realtimeFormats: {...kRealtimeFileFormats, 'rtsp'},
      );
      await kr.open(_rtsp);
      await settle();
      expect(log, ['open', ..._on]);
    });

    test('默认集合不含 rtsp：rtsp 若可 seek 则不限制', () async {
      await k.open(_rtsp);
      await settle();
      expect(log, ['open']);
    });

    test('裸 TS 直播（seekable=no，时长递增）：限制', () async {
      player.profiles[_liveTs] = (['no'], ['1.0', '2.5']);
      await k.open(_liveTs);
      await settle();
      expect(log, ['open', ..._on]);
    });

    test('裸 TS 直播（seekable=no，始终无时长）：限制', () async {
      player.profiles[_liveTs] = (['no'], ['']);
      await k.open(_liveTs);
      await settle();
      expect(log, ['open', ..._on]);
    });

    test('点播 .ts（seekable=yes）：不限制', () async {
      await k.open(_vodTs);
      await settle();
      expect(log, ['open']);
    });

    test('seekable=no 但时长恒定（无 Range 的点播）：不限制', () async {
      player.profiles[_vodTs] = (['no'], ['40.0']);
      await k.open(_vodTs);
      await settle();
      expect(log, ['open']);
    });

    test('时长一次有一次无：不限制', () async {
      player.profiles[_liveTs] = (['no'], ['', '3.0']);
      await k.open(_liveTs);
      await settle();
      expect(log, ['open']);
    });

    test('hls 即使 seekable=no 且时长递增：不限制（保留缓存内回拉）', () async {
      player.profiles[_hls] = (['no'], ['30.0', '31.5']);
      await k.open(_hls);
      await settle();
      expect(log, ['open']);
    });

    test('点播 mp4 瞬态（seekable 先 no 后 yes，时长递增）：不限制', () async {
      player.profiles[_mp4] = (['no', 'yes'], ['1.0', '2.5']);
      await k.open(_mp4);
      await settle();
      expect(log, ['open']);
    });

    test('seekable 先 yes：第一次就放弃，不再继续探测', () async {
      player.profiles[_liveTs] = (['yes', 'no'], ['1.0', '2.5']);
      await k.open(_liveTs);
      await settle();
      expect(log, ['open']);
    });

    test('探测期间换源：不残留限制', () async {
      player.profiles[_liveTs] = (['no'], ['1.0', '2.5']);
      await k.open(_liveTs);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      await k.open(_mp4);
      await settle();
      expect(log, ['open', 'open']);
    });

    test('兜底限制后换源：还原原值', () async {
      player.profiles[_liveTs] = (['no'], ['1.0', '2.5']);
      await k.open(_liveTs);
      await settle();
      log.clear();
      await k.open(_mp4);
      await settle();
      expect(log, [..._off, 'open']);
    });

    test('兜底限制后打开失败：不残留限制', () async {
      player.profiles[_liveTs] = (['no'], ['1.0', '2.5']);
      await k.open(_liveTs);
      await settle();
      log.clear();
      player.failOpen = true;
      await expectLater(k.open(_liveTs), throwsStateError);
      await settle();
      expect(log, [..._off, 'open']);
    });

    test('探测期间 dispose：不抛错、不再写属性', () async {
      player.profiles[_liveTs] = (['no'], ['1.0', '2.5']);
      await k.open(_liveTs);
      await Future<void>.delayed(const Duration(milliseconds: 12));
      await k.dispose();
      await settle();
      expect(log, ['open']);
    });
  });
}
