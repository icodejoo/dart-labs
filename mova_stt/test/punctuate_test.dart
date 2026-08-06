import 'package:flutter_test/flutter_test.dart';
import 'package:mova/mova.dart';
import 'package:mova_stt/mova_stt.dart';

MovaSttCue _cue(String text, int startMs, int endMs) => MovaSttCue(
      text: text,
      start: Duration(milliseconds: startMs),
      end: Duration(milliseconds: endMs),
    );

void main() {
  group('insertPauseBasedPunctuation', () {
    test('appends a full stop before a long pause', () {
      final result = insertPauseBasedPunctuation([
        _cue('你好', 0, 1000),
        _cue('世界', 1700, 2500), // 700ms gap ≥ default 600ms longPause
      ]);
      expect(result[0].text, '你好。');
      // Last cue has no "next" gap to measure, so it's treated as a long
      // trailing pause too — every cue in the output ends punctuated.
      expect(result[1].text, '世界。');
    });

    test('appends a comma before a short pause', () {
      final result = insertPauseBasedPunctuation([
        _cue('你好', 0, 1000),
        _cue('世界', 1300, 2000), // 300ms gap: shortPause <= gap < longPause
      ]);
      expect(result[0].text, '你好，');
    });

    test('appends nothing when the next cue follows immediately', () {
      final result = insertPauseBasedPunctuation([
        _cue('你好', 0, 1000),
        _cue('世界', 1050, 2000), // 50ms gap < default 200ms shortPause
      ]);
      expect(result[0].text, '你好');
    });

    test('the last cue gets a full stop, treated as a long trailing pause', () {
      final result = insertPauseBasedPunctuation([_cue('结束', 0, 1000)]);
      expect(result[0].text, '结束。');
    });

    test('leaves already-punctuated text untouched (idempotent)', () {
      final once = insertPauseBasedPunctuation([
        _cue('你好', 0, 1000),
        _cue('世界', 1700, 2500),
      ]);
      final twice = insertPauseBasedPunctuation(once);
      expect(twice, once);
    });

    test('does not mutate the input list', () {
      final input = [_cue('你好', 0, 1000), _cue('世界', 1700, 2500)];
      final before = input[0].text;
      insertPauseBasedPunctuation(input);
      expect(input[0].text, before);
    });

    test('empty text is left untouched', () {
      final result = insertPauseBasedPunctuation([_cue('', 0, 1000)]);
      expect(result[0].text, '');
    });
  });
}
