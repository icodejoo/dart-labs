import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/model/source.dart';

/// MovaSource 的按源 mpv / demuxer 选项（含 WHEP 便捷项）。
void main() {
  const whep = 'whep+http://h:8889/x/whep';

  test('默认没有任何选项', () {
    const s = MovaSource(whep, type: MovaStreamType.live);
    expect(s.mpvOptions, isEmpty);
    expect(s.demuxerOptions, isEmpty);
    expect(s.whepMediaTimeout, isNull);
    expect(s.mpvOptionsFor(whep), isEmpty);
  });

  test('mpvOptions 原样透传', () {
    const s = MovaSource(whep, mpvOptions: {'cache': 'no', 'network-timeout': '5'});
    expect(s.mpvOptionsFor(whep), {'cache': 'no', 'network-timeout': '5'});
  });

  test('demuxerOptions 合成 demuxer-lavf-o（key=value 逗号分隔）', () {
    const s = MovaSource(whep, demuxerOptions: {'media_timeout': '3000000', 'foo': 'bar'});
    expect(s.mpvOptionsFor(whep), {'demuxer-lavf-o': 'media_timeout=3000000,foo=bar'});
  });

  test('whepMediaTimeout 换算成微秒写入 media_timeout，仅对 whep 地址生效', () {
    const s = MovaSource(whep, alternatives: ['https://h/a.m3u8'], whepMediaTimeout: Duration(seconds: 3));
    expect(s.mpvOptionsFor(whep), {'demuxer-lavf-o': 'media_timeout=3000000'});
    expect(s.mpvOptionsFor('WHEPS+https://h/x'), {'demuxer-lavf-o': 'media_timeout=3000000'});
    expect(s.mpvOptionsFor('https://h/a.m3u8'), isEmpty, reason: '备选地址不是 WHEP，不下发');
  });

  test('显式 demuxerOptions 的 media_timeout 优先于 whepMediaTimeout', () {
    const s = MovaSource(whep, demuxerOptions: {'media_timeout': '1'}, whepMediaTimeout: Duration(seconds: 3));
    expect(s.mpvOptionsFor(whep), {'demuxer-lavf-o': 'media_timeout=1'});
  });

  test('mpvOptions 里自带 demuxer-lavf-o 时与合成项拼接而不是覆盖', () {
    const s = MovaSource(
      whep,
      mpvOptions: {'demuxer-lavf-o': 'fflags=nobuffer', 'cache': 'no'},
      whepMediaTimeout: Duration(milliseconds: 500),
    );
    expect(s.mpvOptionsFor(whep), {'demuxer-lavf-o': 'fflags=nobuffer,media_timeout=500000', 'cache': 'no'});
  });

  test('含逗号/等号/引号/空白的值用 %长度%值 转义', () {
    const s = MovaSource(whep, demuxerOptions: {'headers': 'a=1,b=2'});
    expect(s.mpvOptionsFor(whep), {'demuxer-lavf-o': 'headers=%7%a=1,b=2'});
  });

  test('返回的是拷贝：改它不影响源', () {
    const s = MovaSource(whep, mpvOptions: {'cache': 'no'});
    s.mpvOptionsFor(whep)['x'] = 'y';
    expect(s.mpvOptionsFor(whep), {'cache': 'no'});
  });

  test('sameAs 把选项也算进去', () {
    const a = MovaSource(whep, mpvOptions: {'cache': 'no'});
    expect(a.sameAs(const MovaSource(whep, mpvOptions: {'cache': 'no'})), isTrue);
    expect(a.sameAs(const MovaSource(whep, mpvOptions: {'cache': 'yes'})), isFalse);
    expect(a.sameAs(const MovaSource(whep)), isFalse);
    expect(const MovaSource(whep, demuxerOptions: {'a': '1'}).sameAs(const MovaSource(whep)), isFalse);
    expect(const MovaSource(whep, whepMediaTimeout: Duration(seconds: 1)).sameAs(const MovaSource(whep)), isFalse);
  });

  test('pick 透传选项', () {
    final s = MovaSource.pick(
      [' $whep '],
      type: MovaStreamType.live,
      mpvOptions: const {'cache': 'no'},
      demuxerOptions: const {'a': '1'},
      whepMediaTimeout: const Duration(seconds: 2),
    )!;
    expect(s.mpvOptions, {'cache': 'no'});
    expect(s.demuxerOptions, {'a': '1'});
    expect(s.whepMediaTimeout, const Duration(seconds: 2));
  });
}
