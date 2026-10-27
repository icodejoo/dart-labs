import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';
import 'package:mova/src/core/options/options.dart';

void main() {
  const whep = 'whep+http://h:8889/x/whep';
  const http = 'https://h/a.mp4';

  group('MovaTimeouts → mpv 选项映射', () {
    test('network 折成整秒 network-timeout（向上取整、至少 1）', () {
      expect(const MovaTimeouts(network: Duration(seconds: 12)).mpvOptionsFor(http), {'network-timeout': '12'});
      expect(const MovaTimeouts(network: Duration(milliseconds: 1200)).mpvOptionsFor(http), {'network-timeout': '2'});
      expect(const MovaTimeouts(network: Duration(milliseconds: 10)).mpvOptionsFor(http), {'network-timeout': '1'});
      expect(const MovaTimeouts().mpvOptionsFor(http), isEmpty);
    });

    test('WHEP 三项换算成微秒，只对 whep 地址生效', () {
      const t = MovaTimeouts(whepHandshake: Duration(seconds: 5), whepFirstFrame: Duration(seconds: 8), whepMedia: Duration(seconds: 3));
      expect(t.demuxerOptionsFor(whep), {
        'handshake_timeout': '5000000',
        'first_frame_timeout': '8000000',
        'media_timeout': '3000000',
      });
      expect(t.demuxerOptionsFor(http), isEmpty);
    });

    test('经 MovaSource.mpvOptionsFor 合成：network-timeout 与 demuxer-lavf-o', () {
      const t = MovaTimeouts(network: Duration(seconds: 10), whepHandshake: Duration(seconds: 5), whepMedia: Duration(seconds: 3));
      expect(const MovaSource(whep).mpvOptionsFor(whep, timeouts: t), {
        'network-timeout': '10',
        'demuxer-lavf-o': 'handshake_timeout=5000000,media_timeout=3000000',
      });
      expect(const MovaSource(http).mpvOptionsFor(http, timeouts: t), {'network-timeout': '10'});
      expect(const MovaSource(http).mpvOptionsFor(http), isEmpty);
    });

    test('源级显式设置优先：mpvOptions / demuxerOptions / whepMediaTimeout', () {
      const t = MovaTimeouts(network: Duration(seconds: 10), whepHandshake: Duration(seconds: 5), whepMedia: Duration(seconds: 3));
      final byMpv = const MovaSource(whep, mpvOptions: {'network-timeout': '30'}).mpvOptionsFor(whep, timeouts: t);
      expect(byMpv['network-timeout'], '30');
      final byDemuxer = const MovaSource(whep, demuxerOptions: {'media_timeout': '9000000'}).mpvOptionsFor(whep, timeouts: t);
      expect(byDemuxer['demuxer-lavf-o'], 'media_timeout=9000000,handshake_timeout=5000000');
      final byShortcut = const MovaSource(whep, whepMediaTimeout: Duration(seconds: 7)).mpvOptionsFor(whep, timeouts: t);
      expect(byShortcut['demuxer-lavf-o'], contains('media_timeout=7000000'));
      expect(byShortcut['demuxer-lavf-o'], isNot(contains('3000000')));
      final byRaw = const MovaSource(whep, mpvOptions: {'demuxer-lavf-o': 'media_timeout=1000000'}).mpvOptionsFor(whep, timeouts: t);
      expect(byRaw['demuxer-lavf-o'], 'media_timeout=1000000,handshake_timeout=5000000');
    });
  });

  group('MovaTimeouts 窗口', () {
    test('默认窗口：非 WHEP 60s，WHEP 起播 80s、卡顿 5s', () {
      const t = MovaTimeouts();
      expect(t.startWindowFor(http), Duration(seconds: 60));
      expect(t.startWindowFor(whep), Duration(seconds: 80));
      expect(t.stallWindowFor(whep), Duration(seconds: 5));
    });

    test('network 小于 ffmpeg 重连窗口时按 11s 计', () {
      expect(const MovaTimeouts(network: Duration(seconds: 5)).startWindowFor(http), Duration(seconds: 11));
    });
  });
}
