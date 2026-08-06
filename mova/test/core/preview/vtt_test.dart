import 'package:flutter_test/flutter_test.dart';
import 'package:mova/src/core/preview/models.dart';
import 'package:mova/src/core/preview/vtt.dart';

/// Base URL every relative sprite path in these fixtures resolves against.
///
/// 这些用例中相对雪碧图路径解析所依据的基准 URL。
final Uri _base = Uri.parse('https://host/media/video.mp4.vtt');

void main() {
  test('parses cues with #xywh crops and resolves relative sprite paths', () {
    const vtt = 'WEBVTT\n'
        '\n'
        '00:00:00.000 --> 00:00:10.000\n'
        'sprite-0.jpg#xywh=0,0,160,90\n'
        '\n'
        '00:00:10.000 --> 00:00:20.000\n'
        'sprite-0.jpg#xywh=160,0,160,90\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.length, 2);
    expect(idx.cues[0].start, Duration.zero);
    expect(idx.cues[0].end, const Duration(seconds: 10));
    expect(idx.cues[0].image, Uri.parse('https://host/media/sprite-0.jpg'));
    expect(idx.cues[0].crop, const MovaThumbCrop(x: 0, y: 0, w: 160, h: 90));
    expect(idx.cues[1].crop, const MovaThumbCrop(x: 160, y: 0, w: 160, h: 90));
  });

  test('a cue without #xywh means the whole image', () {
    const vtt = 'WEBVTT\n\n00:00:00.000 --> 00:00:05.000\nframe-0.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.crop, isNull);
    expect(idx.cues.single.image, Uri.parse('https://host/media/frame-0.jpg'));
  });

  test('absolute sprite URLs are kept as-is', () {
    const vtt = 'WEBVTT\n'
        '\n'
        '00:00:00.000 --> 00:00:05.000\n'
        'https://cdn.example.com/s.jpg#xywh=0,0,10,10\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.image, Uri.parse('https://cdn.example.com/s.jpg'));
  });

  test('supports hours, cue identifiers, comments and CRLF line endings', () {
    const vtt = 'WEBVTT\r\n'
        '\r\n'
        'NOTE this is a comment\r\n'
        '\r\n'
        '1\r\n'
        '01:02:03.500 --> 01:02:13.500\r\n'
        'sprite-1.jpg#xywh=0,90,160,90\r\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(
      idx.cues.single.start,
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
    );
    expect(
      idx.cues.single.end,
      const Duration(hours: 1, minutes: 2, seconds: 13, milliseconds: 500),
    );
    expect(idx.cues.single.crop, const MovaThumbCrop(x: 0, y: 90, w: 160, h: 90));
  });

  test('supports the MM:SS.mmm short timestamp form', () {
    const vtt = 'WEBVTT\n\n02:03.000 --> 02:13.000\ns.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.start, const Duration(minutes: 2, seconds: 3));
    expect(idx.cues.single.end, const Duration(minutes: 2, seconds: 13));
  });

  test('malformed timing lines, empty payloads and junk are skipped', () {
    const vtt = 'WEBVTT\n'
        '\n'
        'nonsense line\n'
        '\n'
        '00:00:00.000 -> 00:00:10.000\n'
        'bad-arrow.jpg\n'
        '\n'
        '00:00:10.000 --> 00:00:20.000\n'
        '\n'
        '00:00:20.000 --> 00:00:30.000\n'
        'good.jpg#xywh=0,0,160,90\n'
        '\n'
        'xx:yy:zz.qqq --> 00:00:40.000\n'
        'bad-time.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.length, 1);
    expect(idx.cues.single.image, Uri.parse('https://host/media/good.jpg'));
  });

  test('an empty or non-WEBVTT document yields an empty index', () {
    expect(parseVttThumbs('', base: _base).isEmpty, isTrue);
    expect(parseVttThumbs('   \n\n', base: _base).isEmpty, isTrue);
    expect(parseVttThumbs('not a vtt file at all', base: _base).isEmpty, isTrue);
  });

  test('cues come back sorted ascending by start even if the file is not', () {
    const vtt = 'WEBVTT\n'
        '\n'
        '00:00:20.000 --> 00:00:30.000\n'
        'c.jpg\n'
        '\n'
        '00:00:00.000 --> 00:00:10.000\n'
        'a.jpg\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.first.image.pathSegments.last, 'a.jpg');
    expect(idx.cueAt(const Duration(seconds: 25))!.image.pathSegments.last, 'c.jpg');
  });

  test('a malformed #xywh fragment degrades to no crop rather than dropping the cue', () {
    const vtt = 'WEBVTT\n\n00:00:00.000 --> 00:00:10.000\ns.jpg#xywh=0,0,abc\n';
    final idx = parseVttThumbs(vtt, base: _base);
    expect(idx.cues.single.crop, isNull);
    expect(idx.cues.single.image, Uri.parse('https://host/media/s.jpg'));
  });
}
