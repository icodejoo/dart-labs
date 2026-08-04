import 'package:flutter_test/flutter_test.dart';
import 'package:videoman/src/core/stt/cue.dart';
import 'package:videoman/src/core/stt/srt.dart';

void main() {
  group('formatSrt', () {
    test('formats a single cue with 1-based index and comma milliseconds', () {
      final srt = formatSrt([
        const VmSttCue(text: '大家好', start: Duration(seconds: 1), end: Duration(seconds: 3, milliseconds: 500)),
      ]);
      expect(srt, '1\n00:00:01,000 --> 00:00:03,500\n大家好\n\n');
    });

    test('formats multiple cues with sequential indices', () {
      final srt = formatSrt([
        const VmSttCue(text: 'a', start: Duration.zero, end: Duration(seconds: 1)),
        const VmSttCue(text: 'b', start: Duration(seconds: 1), end: Duration(seconds: 2)),
      ]);
      expect(srt, contains('1\n00:00:00,000 --> 00:00:01,000\na\n'));
      expect(srt, contains('2\n00:00:01,000 --> 00:00:02,000\nb\n'));
    });

    test('rolls hours over correctly for long content', () {
      final srt = formatSrt([
        const VmSttCue(
          text: 'late',
          start: Duration(hours: 1, minutes: 2, seconds: 3),
          end: Duration(hours: 1, minutes: 2, seconds: 5),
        ),
      ]);
      expect(srt, contains('01:02:03,000 --> 01:02:05,000'));
    });
  });

  group('parseSrt', () {
    test('parses a well-formed multi-cue file', () {
      const text = '1\n00:00:01,000 --> 00:00:03,500\n大家好\n\n'
          '2\n00:00:03,500 --> 00:00:05,000\n再见\n\n';
      final cues = parseSrt(text);
      expect(cues, hasLength(2));
      expect(cues[0].text, '大家好');
      expect(cues[0].start, const Duration(seconds: 1));
      expect(cues[0].end, const Duration(seconds: 3, milliseconds: 500));
      expect(cues[1].text, '再见');
    });

    test('handles CRLF line endings and a leading BOM', () {
      const text =
          '﻿1\r\n00:00:00,000 --> 00:00:01,000\r\nhello\r\n\r\n';
      final cues = parseSrt(text);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'hello');
    });

    test('joins multi-line cue text with newlines', () {
      const text = '1\n00:00:00,000 --> 00:00:01,000\nline one\nline two\n\n';
      final cues = parseSrt(text);
      expect(cues[0].text, 'line one\nline two');
    });

    test('skips malformed blocks instead of throwing', () {
      const text = '1\nnot a timing line\ntext\n\n'
          '2\n00:00:01,000 --> 00:00:02,000\nvalid\n\n';
      final cues = parseSrt(text);
      expect(cues, hasLength(1));
      expect(cues[0].text, 'valid');
    });

    test('round-trips through formatSrt', () {
      final original = [
        const VmSttCue(text: '第一句', start: Duration.zero, end: Duration(seconds: 2)),
        const VmSttCue(text: '第二句\n带换行', start: Duration(seconds: 2), end: Duration(seconds: 4)),
      ];
      final roundTripped = parseSrt(formatSrt(original));
      expect(roundTripped, original);
    });
  });
}
